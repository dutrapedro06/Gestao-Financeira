#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 4..."

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
cat > 'app/services/dashboard_service.py' << 'ARQUIVO_FIM'
"""
Agregações para o dashboard, usando Pandas.

Ponto importante sobre "saldo geral": transferências entre contas do
mesmo usuário se cancelam (saem de uma, entram em outra), então o saldo
geral só depende de receitas e despesas — não precisa considerar
TransferenciaEntreContas aqui (diferente do saldo POR conta, calculado
em saldo_service.py).
"""

from datetime import date, timedelta
from decimal import Decimal

import pandas as pd
from sqlalchemy.orm import Session

from app.models import Conta, Lancamento
from app.models.enums import TipoLancamento


def _query_lancamentos(
    db: Session,
    usuario_id: int,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    categoria_id: int | None = None,
    fonte_id: int | None = None,
) -> list[Lancamento]:
    query = (
        db.query(Lancamento)
        .join(Conta, Lancamento.conta_id == Conta.id)
        .filter(Conta.usuario_id == usuario_id)
    )
    if data_inicio:
        query = query.filter(Lancamento.data >= data_inicio)
    if data_fim:
        query = query.filter(Lancamento.data <= data_fim)
    if categoria_id:
        query = query.filter(Lancamento.categoria_id == categoria_id)
    if fonte_id:
        query = query.filter(Lancamento.fonte_renda_id == fonte_id)
    return query.all()


def _para_dataframe(lancamentos: list[Lancamento]) -> pd.DataFrame:
    if not lancamentos:
        return pd.DataFrame(columns=["data", "tipo", "valor", "categoria"])
    return pd.DataFrame(
        [
            {
                "data": l.data,
                "tipo": l.tipo.value,
                "valor": float(l.valor),
                "categoria": l.categoria.nome,
            }
            for l in lancamentos
        ]
    )


def resumo_periodo(
    db: Session, usuario_id: int, data_inicio: date, data_fim: date,
    categoria_id: int | None = None, fonte_id: int | None = None,
) -> dict:
    lancamentos = _query_lancamentos(db, usuario_id, data_inicio, data_fim, categoria_id, fonte_id)
    df = _para_dataframe(lancamentos)

    total_receitas = float(df.loc[df["tipo"] == "receita", "valor"].sum()) if not df.empty else 0.0
    total_despesas = float(df.loc[df["tipo"] == "despesa", "valor"].sum()) if not df.empty else 0.0

    return {
        "lancamentos": lancamentos,
        "dataframe": df,
        "total_receitas": total_receitas,
        "total_despesas": total_despesas,
        "saldo_periodo": total_receitas - total_despesas,
    }


def gastos_por_categoria(df: pd.DataFrame) -> pd.DataFrame:
    despesas = df[df["tipo"] == "despesa"]
    if despesas.empty:
        return pd.DataFrame(columns=["categoria", "valor"])
    return (
        despesas.groupby("categoria", as_index=False)["valor"]
        .sum()
        .sort_values("valor", ascending=False)
    )


def saldo_geral_antes_de(db: Session, usuario_id: int, data: date) -> Decimal:
    """Saldo geral acumulado de tudo que aconteceu ANTES de 'data' (exclusive)."""
    lancamentos = _query_lancamentos(db, usuario_id, data_fim=data - timedelta(days=1))
    total = Decimal("0")
    for l in lancamentos:
        total += l.valor if l.tipo == TipoLancamento.RECEITA else -l.valor
    return total


def evolucao_saldo(
    db: Session, usuario_id: int, data_inicio: date, data_fim: date, saldo_inicial: Decimal
) -> pd.DataFrame:
    """Saldo geral acumulado dia a dia, começando de saldo_inicial."""
    lancamentos = _query_lancamentos(db, usuario_id, data_inicio, data_fim)
    df = _para_dataframe(lancamentos)

    dias = pd.date_range(data_inicio, data_fim, freq="D")
    if df.empty:
        variacao_diaria = pd.Series([0.0] * len(dias), index=dias)
    else:
        df["sinal"] = df["valor"] * df["tipo"].map({"receita": 1, "despesa": -1})
        diario = df.groupby("data")["sinal"].sum()
        diario.index = pd.to_datetime(diario.index)
        variacao_diaria = diario.reindex(dias, fill_value=0.0)

    saldo_acumulado = variacao_diaria.cumsum() + float(saldo_inicial)
    return pd.DataFrame({"data": dias, "saldo": saldo_acumulado.values})

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

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/dashboard.py' << 'ARQUIVO_FIM'
"""Rota web do dashboard."""

from datetime import date

from fastapi import APIRouter, Depends, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.services import dashboard_service as svc
from app.services.cadastros import servico_categorias, servico_fontes_renda
from app.services.graficos import grafico_evolucao_saldo, grafico_gastos_por_categoria
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/dashboard")
templates = Jinja2Templates(directory="app/templates")


@router.get("")
def exibir(
    request: Request,
    data_inicio: str | None = None,
    data_fim: str | None = None,
    categoria_id: int | None = None,
    fonte_id: int | None = None,
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    hoje = date.today()
    inicio = date.fromisoformat(data_inicio) if data_inicio else hoje.replace(day=1)
    fim = date.fromisoformat(data_fim) if data_fim else hoje
    if fim < inicio:
        inicio, fim = fim, inicio

    resumo = svc.resumo_periodo(db, usuario.id, inicio, fim, categoria_id, fonte_id)
    saldo_inicial = svc.saldo_geral_antes_de(db, usuario.id, inicio)
    df_evolucao = svc.evolucao_saldo(db, usuario.id, inicio, fim, saldo_inicial)

    contexto = {
        "usuario": usuario,
        "data_inicio": inicio.isoformat(),
        "data_fim": fim.isoformat(),
        "categoria_id": categoria_id,
        "fonte_id": fonte_id,
        "categorias": servico_categorias.listar(db, usuario.id),
        "fontes": servico_fontes_renda.listar(db, usuario.id),
        "total_receitas": resumo["total_receitas"],
        "total_despesas": resumo["total_despesas"],
        "saldo_periodo": resumo["saldo_periodo"],
        "lancamentos": sorted(resumo["lancamentos"], key=lambda l: l.data, reverse=True),
        "grafico_categorias": grafico_gastos_por_categoria(svc.gastos_por_categoria(resumo["dataframe"])),
        "grafico_saldo": grafico_evolucao_saldo(df_evolucao),
    }
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/dashboard.html" if is_htmx else "dashboard.html"
    return templates.TemplateResponse(request, nome_template, contexto)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/dashboard.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Dashboard — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/dashboard.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/dashboard.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-6">Dashboard</h1>

<form hx-get="/dashboard" hx-target="#pagina" hx-swap="outerHTML"
      class="bg-slate-900 border border-slate-800 rounded-md p-4 mb-6 grid grid-cols-2 md:grid-cols-5 gap-3 items-end">
  <div>
    <label class="text-xs text-slate-400 block mb-1">De</label>
    <input type="date" name="data_inicio" value="{{ data_inicio }}"
           class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>
  <div>
    <label class="text-xs text-slate-400 block mb-1">Até</label>
    <input type="date" name="data_fim" value="{{ data_fim }}"
           class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>
  <select name="categoria_id" class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    <option value="">Todas as categorias</option>
    {% for c in categorias %}
    <option value="{{ c.id }}" {% if categoria_id == c.id %}selected{% endif %}>{{ c.nome }}</option>
    {% endfor %}
  </select>
  <select name="fonte_id" class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    <option value="">Todas as fontes</option>
    {% for f in fontes %}
    <option value="{{ f.id }}" {% if fonte_id == f.id %}selected{% endif %}>{{ f.nome }}</option>
    {% endfor %}
  </select>
  <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">Filtrar</button>
</form>

<div class="grid grid-cols-3 gap-3 mb-6">
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <div class="text-slate-400 text-xs">Receitas no período</div>
    <div class="text-lg font-semibold text-emerald-300">R$ {{ "%.2f"|format(total_receitas) }}</div>
  </div>
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <div class="text-slate-400 text-xs">Despesas no período</div>
    <div class="text-lg font-semibold text-rose-300">R$ {{ "%.2f"|format(total_despesas) }}</div>
  </div>
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <div class="text-slate-400 text-xs">Saldo do período</div>
    <div class="text-lg font-semibold">R$ {{ "%.2f"|format(saldo_periodo) }}</div>
  </div>
</div>

<div class="grid md:grid-cols-2 gap-4 mb-6">
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <h2 class="text-sm text-slate-400 mb-2">Gastos por categoria</h2>
    {% if grafico_categorias %}
      {{ grafico_categorias | safe }}
    {% else %}
      <p class="text-slate-500 text-sm py-10 text-center">Sem despesas no período.</p>
    {% endif %}
  </div>
  <div class="bg-slate-900 border border-slate-800 rounded-md p-4">
    <h2 class="text-sm text-slate-400 mb-2">Evolução do saldo geral</h2>
    {{ grafico_saldo | safe }}
  </div>
</div>

<h2 class="text-lg font-semibold mb-2">Lançamentos do período</h2>
<ul class="space-y-2">
  {% for l in lancamentos %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3 flex items-center justify-between">
    <div>
      <span class="font-medium">{{ l.categoria.nome }}</span>
      <span class="text-slate-400"> · {{ l.conta.nome }}</span>
      {% if l.descricao %}<span class="text-slate-500 text-sm"> — {{ l.descricao }}</span>{% endif %}
    </div>
    <div class="flex items-center gap-4">
      <span class="text-slate-400 text-sm">{{ l.data.strftime("%d/%m/%Y") }}</span>
      <span class="tabular-nums {{ 'text-rose-300' if l.tipo.value == 'despesa' else 'text-emerald-300' }}">
        {{ "-" if l.tipo.value == "despesa" else "+" }}R$ {{ "%.2f"|format(l.valor) }}
      </span>
    </div>
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhum lançamento no período.</li>
  {% endfor %}
</ul>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_dashboard_service.py' << 'ARQUIVO_FIM'
"""Testes das agregações do dashboard (Pandas)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services import dashboard_service as svc
from app.services.cadastros import servico_categorias, servico_contas
from app.services.lancamentos import servico_lancamentos


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
    mercado = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    transporte = servico_categorias.criar(db, usuario.id, "Transporte", tipo="despesa")
    salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")

    servico_lancamentos.criar(db, usuario.id, tipo="receita", conta_id=conta.id, categoria_id=salario.id, valor="1000", data="2026-09-01")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=mercado.id, valor="200", data="2026-09-05")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=mercado.id, valor="50", data="2026-09-10")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=transporte.id, valor="80", data="2026-09-15")
    return {"conta": conta}


def test_resumo_periodo_soma_receitas_e_despesas(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30))
    assert resumo["total_receitas"] == 1000
    assert resumo["total_despesas"] == 330
    assert resumo["saldo_periodo"] == 670


def test_resumo_periodo_respeita_o_filtro_de_data(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 6))
    assert resumo["total_despesas"] == 200  # só a do dia 5, não a do dia 10 nem 15


def test_gastos_por_categoria_agrupa_e_soma(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30))
    agrupado = svc.gastos_por_categoria(resumo["dataframe"])

    mercado = agrupado[agrupado["categoria"] == "Mercado"]["valor"].iloc[0]
    transporte = agrupado[agrupado["categoria"] == "Transporte"]["valor"].iloc[0]
    assert mercado == 250  # 200 + 50
    assert transporte == 80


def test_gastos_por_categoria_vazio_quando_sem_despesas(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta")
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 1, 1), date(2026, 1, 31))
    agrupado = svc.gastos_por_categoria(resumo["dataframe"])
    assert agrupado.empty


def test_saldo_geral_antes_de_ignora_o_que_vem_depois(db, usuario, cenario):
    # antes do dia 10: só a receita de 1000 e a despesa de 200 (dia 5)
    saldo = svc.saldo_geral_antes_de(db, usuario.id, date(2026, 9, 10))
    assert saldo == 800


def test_evolucao_saldo_acumula_dia_a_dia(db, usuario, cenario):
    df = svc.evolucao_saldo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30), saldo_inicial=0)

    saldo_dia_1 = df.loc[df["data"] == "2026-09-01", "saldo"].iloc[0]
    saldo_dia_5 = df.loc[df["data"] == "2026-09-05", "saldo"].iloc[0]
    saldo_dia_15 = df.loc[df["data"] == "2026-09-15", "saldo"].iloc[0]
    saldo_dia_30 = df.loc[df["data"] == "2026-09-30", "saldo"].iloc[0]

    assert saldo_dia_1 == 1000
    assert saldo_dia_5 == 800    # 1000 - 200
    assert saldo_dia_15 == 670   # 1000 - 200 - 50 - 80
    assert saldo_dia_30 == 670   # sem mais movimentação, mantém


def test_evolucao_saldo_comeca_do_saldo_inicial_informado(db, usuario, cenario):
    df = svc.evolucao_saldo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 1), saldo_inicial=500)
    assert df["saldo"].iloc[0] == 1500  # 500 de antes + 1000 do dia 1

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_dashboard_web.py' << 'ARQUIVO_FIM'
"""Teste de integração do dashboard: filtros, totais e presença dos gráficos no HTML."""

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


def test_dashboard_mostra_totais_e_graficos(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})

    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1, "valor": "1000", "data": "2026-09-05",
    })
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2, "valor": "200", "data": "2026-09-10",
    })

    resposta = cliente_logado.get("/dashboard?data_inicio=2026-09-01&data_fim=2026-09-30")
    assert resposta.status_code == 200
    assert "R$ 1000.00" in resposta.text   # receitas
    assert "R$ 200.00" in resposta.text    # despesas
    assert "R$ 800.00" in resposta.text    # saldo do período
    assert "Mercado" in resposta.text      # aparece na lista e no gráfico
    assert "plotly" in resposta.text.lower()  # o gráfico foi de fato embutido


def test_dashboard_filtra_por_categoria(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    cliente_logado.post("/categorias", data={"nome": "Transporte", "tipo": "despesa"})
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1, "valor": "200", "data": "2026-09-10",
    })
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2, "valor": "80", "data": "2026-09-12",
    })

    resposta = cliente_logado.get("/dashboard?data_inicio=2026-09-01&data_fim=2026-09-30&categoria_id=1")
    assert "R$ 200.00" in resposta.text
    # "Transporte" ainda aparece no dropdown de filtro (opção disponível) — o que
    # importa é que o valor da despesa de Transporte (80) não entrou no total.
    assert "R$ 80.00" not in resposta.text


def test_dashboard_sem_lancamentos_nao_quebra(cliente_logado):
    resposta = cliente_logado.get("/dashboard")
    assert resposta.status_code == 200
    assert "Sem despesas no período" in resposta.text

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: dashboard com graficos e filtros por periodo/categoria/fonte (Etapa 4)"
rm -- "$0"
echo "Commit feito. Rode: git push"
