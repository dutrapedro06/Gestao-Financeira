#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 5..."

mkdir -p 'app'
cat > 'app/main.py' << 'ARQUIVO_FIM'
"""
Ponto de entrada da aplicação: cria a instância FastAPI, registra
middlewares e inclui os routers.
"""

from fastapi import Depends, FastAPI
from fastapi.responses import RedirectResponse
from sqlalchemy import text
from sqlalchemy.orm import Session
from starlette.middleware.sessions import SessionMiddleware

from app.config import settings
from app.database import get_db
from app.web import auth as auth_web
from app.web import categorias as categorias_web
from app.web import contas as contas_web
from app.web import dashboard as dashboard_web
from app.web import fontes_renda as fontes_renda_web
from app.web import lancamentos as lancamentos_web
from app.web import projecao as projecao_web
from app.web import recorrencias as recorrencias_web
from app.web import transferencias as transferencias_web
from app.web.deps import usuario_atual_opcional

app = FastAPI(
    title="Gestão Financeira Pessoal",
    description="Sistema web para controle financeiro pessoal.",
    version="0.1.0",
)

# Sessão via cookie assinado (não é possível decodificar/alterar sem a
# secret_key). Guarda só o usuario_id — nunca dados sensíveis no cookie.
app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)

app.include_router(auth_web.router)
app.include_router(contas_web.router)
app.include_router(dashboard_web.router)
app.include_router(categorias_web.router)
app.include_router(fontes_renda_web.router)
app.include_router(lancamentos_web.router)
app.include_router(transferencias_web.router)
app.include_router(recorrencias_web.router)
app.include_router(projecao_web.router)


@app.get("/")
def raiz(usuario=Depends(usuario_atual_opcional)):
    if usuario is None:
        return RedirectResponse(url="/login")
    return RedirectResponse(url="/lancamentos")


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict:
    """
    Confirma que a aplicação consegue de fato executar uma query no
    Postgres — não só que a variável DATABASE_URL existe, mas que a
    conexão funciona de ponta a ponta. Serve tanto para validação
    local quanto como health check em produção.
    """
    db.execute(text("SELECT 1"))
    return {"banco_de_dados": "conectado"}

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/base.html' << 'ARQUIVO_FIM'
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{% block titulo %}Gestão Financeira{% endblock %}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/htmx.org@2.0.4"></script>
    <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
    {% if usuario %}
    <nav class="border-b border-slate-800 px-4 py-3 flex items-center gap-4 text-sm">
        <a href="/" class="font-semibold">Gestão Financeira</a>
        <a href="/dashboard" class="text-slate-300 hover:text-white">Dashboard</a>
        <a href="/projecao" class="text-slate-300 hover:text-white">Projeção</a>
        <a href="/lancamentos" class="text-slate-300 hover:text-white">Lançamentos</a>
        <a href="/contas" class="text-slate-300 hover:text-white">Contas</a>
        <a href="/transferencias" class="text-slate-300 hover:text-white">Transferências</a>
        <a href="/recorrencias" class="text-slate-300 hover:text-white">Recorrências</a>
        <a href="/categorias" class="text-slate-300 hover:text-white">Categorias</a>
        <a href="/fontes-renda" class="text-slate-300 hover:text-white">Fontes de renda</a>
        <span class="ml-auto text-slate-400">{{ usuario.nome }}</span>
        <form method="post" action="/logout"><button class="text-slate-400 hover:text-white">Sair</button></form>
    </nav>
    {% endif %}
    <main class="max-w-3xl mx-auto mt-10 px-4">
        {% block conteudo %}{% endblock %}
    </main>
</body>
</html>

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/graficos.py' << 'ARQUIVO_FIM'
"""
Geração dos gráficos do dashboard como HTML (Plotly), prontos para
serem embutidos direto no template Jinja2 (sem precisar de um frontend
JS separado — mesma filosofia da Rota A definida no ADR 0002).
"""

import pandas as pd
import plotly.graph_objects as go

_LAYOUT_PADRAO = dict(
    template="plotly_dark",
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    margin=dict(l=10, r=10, t=10, b=10),
    height=300,
    font=dict(color="#cbd5e1"),
)


def grafico_gastos_por_categoria(df: pd.DataFrame) -> str:
    if df.empty:
        return ""
    figura = go.Figure(go.Bar(x=df["categoria"], y=df["valor"], marker_color="#fb7185"))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$")
    return figura.to_html(include_plotlyjs=False, full_html=False)


def grafico_evolucao_saldo(df: pd.DataFrame) -> str:
    if df.empty:
        return ""
    figura = go.Figure(go.Scatter(x=df["data"], y=df["saldo"], mode="lines", line=dict(color="#34d399", width=2)))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$")
    return figura.to_html(include_plotlyjs=False, full_html=False)


def grafico_projecao(df_historico: pd.DataFrame, df_projecao: pd.DataFrame) -> str:
    figura = go.Figure()
    if not df_historico.empty:
        figura.add_trace(go.Scatter(
            x=df_historico["data"], y=df_historico["saldo"], mode="lines",
            name="Histórico", line=dict(color="#34d399", width=2),
        ))
    if not df_projecao.empty:
        figura.add_trace(go.Scatter(
            x=df_projecao["data"], y=df_projecao["saldo"], mode="lines",
            name="Projeção", line=dict(color="#facc15", width=2, dash="dash"),
        ))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$", showlegend=True)
    return figura.to_html(include_plotlyjs=False, full_html=False)

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/projecao_service.py' << 'ARQUIVO_FIM'
"""
Projeção de saldo futuro (ADR 0005).

saldo_projetado(data_futura) = saldo_atual + lançamentos futuros já
conhecidos (derivados das RegraRecorrencia ativas), calculado sob
demanda — nenhum lançamento futuro é persistido no banco com
antecedência, só os já realizados.
"""

from datetime import date, timedelta
from decimal import Decimal

import pandas as pd

from app.models.enums import TipoLancamento
from app.repositories.regras_recorrencia import regras_recorrencia as repo
from app.services.dashboard_service import saldo_geral_antes_de
from app.services.ocorrencias import ocorrencias_ate


def saldo_atual(db, usuario_id: int, referencia: date | None = None) -> Decimal:
    """Saldo geral real, incluindo tudo até 'referencia' (hoje, por padrão)."""
    referencia = referencia or date.today()
    return saldo_geral_antes_de(db, usuario_id, referencia + timedelta(days=1))


def projecao_futura(db, usuario_id: int, ate: date, hoje: date | None = None) -> pd.DataFrame:
    """
    Saldo geral projetado dia a dia, de hoje até 'ate' (inclusive).

    Só considera ocorrências estritamente futuras (data > hoje) das
    regras ativas — o que já aconteceu está refletido no saldo_atual.
    """
    hoje = hoje or date.today()
    saldo_base = float(saldo_atual(db, usuario_id, hoje))

    variacao_por_dia: dict[date, float] = {}
    for regra in repo.listar_ativas(db, usuario_id):
        sinal = 1 if regra.tipo == TipoLancamento.RECEITA else -1
        for ocorrencia in ocorrencias_ate(regra, ate):
            if ocorrencia <= hoje:
                continue
            variacao_por_dia[ocorrencia] = variacao_por_dia.get(ocorrencia, 0.0) + sinal * float(regra.valor)

    dias = pd.date_range(hoje, ate, freq="D")
    saldo = saldo_base
    linhas = []
    for dia in dias:
        data_do_dia = dia.date()
        if data_do_dia > hoje:
            saldo += variacao_por_dia.get(data_do_dia, 0.0)
        linhas.append({"data": dia, "saldo": saldo})

    return pd.DataFrame(linhas)

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/projecao.py' << 'ARQUIVO_FIM'
"""Rota web de projeção de saldo futuro."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.services import dashboard_service, projecao_service
from app.services.graficos import grafico_projecao
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/projecao")
templates = Jinja2Templates(directory="app/templates")

HORIZONTE_PADRAO_DIAS = 90
HISTORICO_PADRAO_DIAS = 30


@router.get("")
def exibir(
    request: Request,
    ate: str | None = None,
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    hoje = date.today()
    data_ate = date.fromisoformat(ate) if ate else hoje + timedelta(days=HORIZONTE_PADRAO_DIAS)
    if data_ate <= hoje:
        data_ate = hoje + timedelta(days=1)

    inicio_historico = hoje - timedelta(days=HISTORICO_PADRAO_DIAS)
    saldo_inicial_historico = dashboard_service.saldo_geral_antes_de(db, usuario.id, inicio_historico)
    df_historico = dashboard_service.evolucao_saldo(db, usuario.id, inicio_historico, hoje, saldo_inicial_historico)

    df_projecao = projecao_service.projecao_futura(db, usuario.id, data_ate, hoje)

    saldo_atual = projecao_service.saldo_atual(db, usuario.id, hoje)
    saldo_final_projetado = df_projecao["saldo"].iloc[-1] if not df_projecao.empty else float(saldo_atual)

    contexto = {
        "usuario": usuario,
        "ate": data_ate.isoformat(),
        "saldo_atual": saldo_atual,
        "saldo_projetado": saldo_final_projetado,
        "data_projecao": data_ate,
        "grafico": grafico_projecao(df_historico, df_projecao),
    }
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/projecao.html" if is_htmx else "projecao.html"
    return templates.TemplateResponse(request, nome_template, contexto)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/projecao.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Projeção — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/projecao.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/projecao.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-1">Projeção de saldo</h1>
<p class="text-slate-400 text-sm mb-6">
  Combina o que já aconteceu (últimos 30 dias) com o que as recorrências ativas garantem que vai acontecer.
</p>

<form hx-get="/projecao" hx-target="#pagina" hx-swap="outerHTML" class="flex items-end gap-3 mb-6">
  <div>
    <label class="text-xs text-slate-400 block mb-1">Projetar até</label>
    <input type="date" name="ate" value="{{ ate }}"
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>
  <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">Projetar</button>
</form>

<div class="grid grid-cols-2 gap-3 mb-6">
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <div class="text-slate-400 text-xs">Saldo atual</div>
    <div class="text-lg font-semibold">R$ {{ "%.2f"|format(saldo_atual) }}</div>
  </div>
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <div class="text-slate-400 text-xs">Saldo projetado em {{ data_projecao.strftime("%d/%m/%Y") }}</div>
    <div class="text-lg font-semibold {{ 'text-emerald-300' if saldo_projetado >= saldo_atual else 'text-rose-300' }}">
      R$ {{ "%.2f"|format(saldo_projetado) }}
    </div>
  </div>
</div>

<div class="bg-slate-900 border border-slate-800 rounded-md p-4">
  {{ grafico | safe }}
</div>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_projecao_service.py' << 'ARQUIVO_FIM'
"""Testes da projeção de saldo futuro (ADR 0005)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services import projecao_service as svc
from app.services.cadastros import servico_categorias, servico_contas
from app.services.lancamentos import servico_lancamentos
from app.services.regras_recorrencia import servico_recorrencias


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    u = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def cenario(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    aluguel = servico_categorias.criar(db, usuario.id, "Aluguel", tipo="despesa")
    salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")
    return {"conta": conta, "aluguel": aluguel, "salario": salario}


def test_saldo_atual_reflete_so_o_que_ja_aconteceu(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="1000", data=date(2026, 9, 1).isoformat(),
    )
    saldo = svc.saldo_atual(db, usuario.id, referencia=date(2026, 9, 15))
    assert saldo == 1000


def test_projecao_sem_recorrencia_mantem_saldo_constante(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="1000", data=date(2026, 9, 1).isoformat(),
    )
    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 9, 20), hoje=date(2026, 9, 15))
    assert (df["saldo"] == 1000).all()


def test_projecao_incorpora_despesa_recorrente_futura(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="3000", data=date(2026, 9, 1).isoformat(),
    )
    servico_recorrencias.criar(
        db, usuario.id, tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["aluguel"].id,
        valor="1200", frequencia="mensal", dia_referencia="10", data_inicio=date(2026, 9, 10).isoformat(),
    )

    # Hoje é dia 15/09 — o aluguel do dia 10/09 já passou (já deveria ter sido
    # materializado como lançamento real), só o de outubro é projeção de verdade.
    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 10, 15), hoje=date(2026, 9, 15))

    saldo_antes_do_aluguel_de_outubro = df.loc[df["data"] == "2026-10-09", "saldo"].iloc[0]
    saldo_depois_do_aluguel_de_outubro = df.loc[df["data"] == "2026-10-10", "saldo"].iloc[0]

    assert saldo_antes_do_aluguel_de_outubro == 3000
    assert saldo_depois_do_aluguel_de_outubro == 1800  # 3000 - 1200


def test_regra_inativa_nao_entra_na_projecao(db, usuario, cenario):
    regra = servico_recorrencias.criar(
        db, usuario.id, tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["aluguel"].id,
        valor="1200", frequencia="mensal", dia_referencia="10", data_inicio=date(2026, 9, 10).isoformat(),
    )
    servico_recorrencias.alternar_ativa(db, usuario.id, regra.id)

    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 10, 15), hoje=date(2026, 9, 15))
    assert (df["saldo"] == 0).all()

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_projecao_web.py' << 'ARQUIVO_FIM'
"""Teste de integração da projeção de saldo via HTTP."""

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import Usuario
from app.services.auth_service import gerar_hash_senha

engine = create_engine(
    "sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool
)
SessaoTeste = sessionmaker(bind=engine)


def _sobrescrever_db():
    db = SessaoTeste()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(autouse=True)
def banco_limpo():
    Base.metadata.create_all(engine)
    app.dependency_overrides[get_db] = _sobrescrever_db
    yield
    app.dependency_overrides.pop(get_db, None)
    Base.metadata.drop_all(engine)


@pytest.fixture()
def cliente_logado():
    db = SessaoTeste()
    db.add(Usuario(nome="Pedro", email="pedro@example.com", senha_hash=gerar_hash_senha("123456")))
    db.commit()
    db.close()

    cliente = TestClient(app)
    cliente.post("/login", data={"email": "pedro@example.com", "senha": "123456"})
    return cliente


def test_projecao_combina_saldo_atual_com_recorrencia_futura(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})

    hoje = date.today()
    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1,
        "valor": "3000", "data": hoje.isoformat(),
    })
    # Semanal, começando daqui a 3 dias: numa janela de 6 dias cabe exatamente
    # UMA ocorrência futura (a próxima, 7 dias depois, fica de fora) —
    # determinístico independente de qual seja a data real de hoje.
    dia_da_semana_em_3_dias = (hoje.weekday() + 3) % 7
    cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2,
        "valor": "1200", "frequencia": "semanal", "dia_referencia": str(dia_da_semana_em_3_dias),
        "data_inicio": hoje.isoformat(),
    })

    daqui_6_dias = (hoje + timedelta(days=6)).isoformat()
    resposta = cliente_logado.get(f"/projecao?ate={daqui_6_dias}")

    assert resposta.status_code == 200
    assert "R$ 3000.00" in resposta.text  # saldo atual
    assert "plotly" in resposta.text.lower()
    # A única ocorrência da recorrência dentro da janela já deveria ter sido descontada.
    assert "R$ 1800.00" in resposta.text


def test_projecao_sem_dados_nao_quebra(cliente_logado):
    resposta = cliente_logado.get("/projecao")
    assert resposta.status_code == 200
    assert "R$ 0.00" in resposta.text

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: projecao de saldo futuro combinando historico e recorrencias (Etapa 5)"
rm -- "$0"
echo "Commit feito. Rode: git push"
