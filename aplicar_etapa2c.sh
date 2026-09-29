#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 2C..."

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
from app.web import fontes_renda as fontes_renda_web
from app.web import lancamentos as lancamentos_web
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
app.include_router(categorias_web.router)
app.include_router(fontes_renda_web.router)
app.include_router(lancamentos_web.router)
app.include_router(transferencias_web.router)


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
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
    {% if usuario %}
    <nav class="border-b border-slate-800 px-4 py-3 flex items-center gap-4 text-sm">
        <a href="/" class="font-semibold">Gestão Financeira</a>
        <a href="/lancamentos" class="text-slate-300 hover:text-white">Lançamentos</a>
        <a href="/contas" class="text-slate-300 hover:text-white">Contas</a>
        <a href="/transferencias" class="text-slate-300 hover:text-white">Transferências</a>
        <a href="/categorias" class="text-slate-300 hover:text-white">Categorias</a>
        <a href="/fontes-renda" class="text-slate-300 hover:text-white">Fontes de renda</a>
        <span class="ml-auto text-slate-400">{{ usuario.nome }}</span>
        <form method="post" action="/logout"><button class="text-slate-400 hover:text-white">Sair</button></form>
    </nav>
    {% endif %}
    <main class="max-w-2xl mx-auto mt-10 px-4">
        {% block conteudo %}{% endblock %}
    </main>
</body>
</html>

ARQUIVO_FIM

mkdir -p 'app/repositories'
cat > 'app/repositories/transferencias.py' << 'ARQUIVO_FIM'
"""
Repositório de TransferenciaEntreContas.

Assim como Lancamento, não tem usuario_id direto — o isolamento é via
join com Conta (a conta de origem é suficiente, já que origem e destino
sempre pertencem ao mesmo usuário nesta modelagem).
"""

from sqlalchemy.orm import Session

from app.models import Conta, TransferenciaEntreContas


class RepositorioTransferencias:
    def listar(self, db: Session, usuario_id: int, limite: int = 200) -> list[TransferenciaEntreContas]:
        return (
            db.query(TransferenciaEntreContas)
            .join(Conta, TransferenciaEntreContas.conta_origem_id == Conta.id)
            .filter(Conta.usuario_id == usuario_id)
            .order_by(TransferenciaEntreContas.data.desc(), TransferenciaEntreContas.id.desc())
            .limit(limite)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, transferencia_id: int) -> TransferenciaEntreContas | None:
        return (
            db.query(TransferenciaEntreContas)
            .join(Conta, TransferenciaEntreContas.conta_origem_id == Conta.id)
            .filter(TransferenciaEntreContas.id == transferencia_id, Conta.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, transferencia: TransferenciaEntreContas) -> TransferenciaEntreContas:
        db.add(transferencia)
        db.commit()
        db.refresh(transferencia)
        return transferencia

    def salvar(self, db: Session, transferencia: TransferenciaEntreContas) -> TransferenciaEntreContas:
        db.commit()
        db.refresh(transferencia)
        return transferencia

    def remover(self, db: Session, transferencia: TransferenciaEntreContas) -> None:
        db.delete(transferencia)
        db.commit()


transferencias = RepositorioTransferencias()

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/transferencias.py' << 'ARQUIVO_FIM'
"""Regras de negócio das transferências entre contas."""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Conta, TransferenciaEntreContas
from app.repositories.transferencias import transferencias as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_DESCRICAO = 255


def _valor_monetario(valor: str | None) -> Decimal:
    try:
        numero = Decimal(str(valor).replace(",", "."))
    except (InvalidOperation, AttributeError):
        raise ErroDeNegocio("Valor inválido.") from None
    if numero <= 0:
        raise ErroDeNegocio("O valor deve ser maior que zero.")
    return numero


def _data(valor: str | None) -> date:
    try:
        return date.fromisoformat(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio("Data inválida.") from None


def _conta_do_usuario(db: Session, usuario_id: int, conta_id: int) -> Conta:
    conta = db.query(Conta).filter(Conta.id == conta_id, Conta.usuario_id == usuario_id).first()
    if conta is None:
        raise ErroDeNegocio("Conta inválida.")
    return conta


class ServicoTransferencias:
    def listar(self, db: Session, usuario_id: int) -> list[TransferenciaEntreContas]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, transferencia_id: int) -> TransferenciaEntreContas:
        transferencia = repo.obter(db, usuario_id, transferencia_id)
        if transferencia is None:
            raise NaoEncontrado("Transferência não encontrada.")
        return transferencia

    def criar(
        self, db: Session, usuario_id: int, *,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None = None,
    ) -> TransferenciaEntreContas:
        dados = self._validar(db, usuario_id, conta_origem_id, conta_destino_id, valor, data, descricao)
        return repo.adicionar(db, TransferenciaEntreContas(**dados))

    def atualizar(
        self, db: Session, usuario_id: int, transferencia_id: int, *,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None = None,
    ) -> TransferenciaEntreContas:
        transferencia = self.obter(db, usuario_id, transferencia_id)
        dados = self._validar(db, usuario_id, conta_origem_id, conta_destino_id, valor, data, descricao)
        for campo, valor_campo in dados.items():
            setattr(transferencia, campo, valor_campo)
        return repo.salvar(db, transferencia)

    def excluir(self, db: Session, usuario_id: int, transferencia_id: int) -> None:
        transferencia = self.obter(db, usuario_id, transferencia_id)
        repo.remover(db, transferencia)

    def _validar(
        self, db: Session, usuario_id: int,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None,
    ) -> dict:
        if conta_origem_id == conta_destino_id:
            raise ErroDeNegocio("A conta de origem e destino não podem ser a mesma.")

        origem = _conta_do_usuario(db, usuario_id, conta_origem_id)
        destino = _conta_do_usuario(db, usuario_id, conta_destino_id)
        descricao = (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None

        return {
            "conta_origem_id": origem.id,
            "conta_destino_id": destino.id,
            "valor": _valor_monetario(valor),
            "data": _data(data),
            "descricao": descricao,
        }


servico_transferencias = ServicoTransferencias()

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/transferencias.py' << 'ARQUIVO_FIM'
"""Rotas web de transferências entre contas."""

from datetime import date

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services import saldo_service
from app.services.cadastros import servico_contas
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.transferencias import servico_transferencias
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/transferencias")
templates = Jinja2Templates(directory="app/templates")


def _contexto(db: Session, usuario: Usuario, editando: object | None = None, erro: str | None = None) -> dict:
    contas = servico_contas.listar(db, usuario.id)
    return {
        "usuario": usuario,
        "transferencias": servico_transferencias.listar(db, usuario.id),
        "contas": contas,
        "saldos": saldo_service.saldos_das_contas(db, contas),
        "hoje": date.today().isoformat(),
        "editando": editando,
        "erro": erro,
    }


def _renderizar(request: Request, db, usuario, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/transferencias.html" if is_htmx else "transferencias.html"
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario)


@router.get("/{transferencia_id}/editar")
def editar(request: Request, transferencia_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        transferencia = servico_transferencias.obter(db, usuario.id, transferencia_id)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario, editando=transferencia)


@router.post("")
def criar(
    request: Request,
    conta_origem_id: int = Form(...),
    conta_destino_id: int = Form(...),
    valor: str = Form(...),
    data: str = Form(...),
    descricao: str = Form(""),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_transferencias.criar(
            db, usuario.id,
            conta_origem_id=conta_origem_id, conta_destino_id=conta_destino_id,
            valor=valor, data=data, descricao=descricao,
        )
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.put("/{transferencia_id}")
def atualizar(
    request: Request,
    transferencia_id: int,
    conta_origem_id: int = Form(...),
    conta_destino_id: int = Form(...),
    valor: str = Form(...),
    data: str = Form(...),
    descricao: str = Form(""),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_transferencias.atualizar(
            db, usuario.id, transferencia_id,
            conta_origem_id=conta_origem_id, conta_destino_id=conta_destino_id,
            valor=valor, data=data, descricao=descricao,
        )
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    except ErroDeNegocio as erro:
        try:
            transferencia = servico_transferencias.obter(db, usuario.id, transferencia_id)
        except NaoEncontrado:
            transferencia = None
        return _renderizar(request, db, usuario, editando=transferencia, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.delete("/{transferencia_id}")
def excluir(request: Request, transferencia_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_transferencias.excluir(db, usuario.id, transferencia_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/transferencias.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Transferências — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/transferencias.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/transferencias.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-6">Transferências entre contas</h1>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

{% if contas|length < 2 %}
<div class="bg-amber-900/40 border border-amber-700 text-amber-200 text-sm rounded-md px-4 py-2 mb-4">
  Você precisa de pelo menos duas <a href="/contas" class="underline">contas</a> para transferir entre elas.
</div>
{% endif %}

{% set alvo = "/transferencias/" ~ editando.id if editando else "/transferencias" %}
{% set metodo = "hx-put" if editando else "hx-post" %}

<form {{ metodo }}="{{ alvo }}" hx-target="#pagina" hx-swap="outerHTML"
      class="bg-slate-900 border border-slate-800 rounded-md p-4 mb-6 space-y-3">
  <div class="grid grid-cols-2 gap-3">
    <select name="conta_origem_id" required class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="" disabled {% if not editando %}selected{% endif %}>De (origem)</option>
      {% for conta in contas %}
      <option value="{{ conta.id }}" {% if editando and editando.conta_origem_id == conta.id %}selected{% endif %}>{{ conta.nome }}</option>
      {% endfor %}
    </select>
    <select name="conta_destino_id" required class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="" disabled {% if not editando %}selected{% endif %}>Para (destino)</option>
      {% for conta in contas %}
      <option value="{{ conta.id }}" {% if editando and editando.conta_destino_id == conta.id %}selected{% endif %}>{{ conta.nome }}</option>
      {% endfor %}
    </select>
  </div>

  <div class="grid grid-cols-2 gap-3">
    <input type="number" step="0.01" min="0.01" name="valor" placeholder="Valor"
           value="{{ editando.valor if editando else '' }}" required
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    <input type="date" name="data" value="{{ editando.data.isoformat() if editando else hoje }}" required
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>

  <input name="descricao" placeholder="Descrição (opcional)" maxlength="255"
         value="{{ editando.descricao or '' if editando else '' }}"
         class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">

  <div class="flex gap-2">
    <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">
      {{ "Salvar" if editando else "Transferir" }}
    </button>
    {% if editando %}
    <a hx-get="/transferencias" hx-target="#pagina" hx-swap="outerHTML"
       class="text-slate-400 hover:text-white text-sm self-center cursor-pointer">Cancelar</a>
    {% endif %}
  </div>
</form>

<ul class="space-y-2">
  {% for t in transferencias %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3 flex items-center justify-between">
    <div>
      <div class="font-medium">{{ t.conta_origem.nome }} <span class="text-slate-400">→</span> {{ t.conta_destino.nome }}</div>
      {% if t.descricao %}<div class="text-sm text-slate-400">{{ t.descricao }}</div>{% endif %}
    </div>
    <div class="flex items-center gap-4">
      <span class="text-slate-400 text-sm">{{ t.data.strftime("%d/%m/%Y") }}</span>
      <span class="tabular-nums">R$ {{ "%.2f"|format(t.valor) }}</span>
      <a hx-get="/transferencias/{{ t.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
         class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
      <a hx-delete="/transferencias/{{ t.id }}" hx-target="#pagina" hx-swap="outerHTML"
         hx-confirm="Excluir esta transferência?"
         class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
    </div>
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhuma transferência ainda.</li>
  {% endfor %}
</ul>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_servico_transferencias.py' << 'ARQUIVO_FIM'
"""Testes unitários das regras de negócio de transferências entre contas."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Lancamento, Usuario
from app.models.enums import TipoLancamento
from app.services import saldo_service
from app.services.cadastros import servico_contas
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.transferencias import servico_transferencias


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
def contas(db, usuario):
    return {
        "salario": servico_contas.criar(db, usuario.id, "Salário"),
        "investimento": servico_contas.criar(db, usuario.id, "Investimento"),
    }


def test_criar_transferencia(db, usuario, contas):
    t = servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    assert t.valor == 300


def test_nao_permite_mesma_conta_origem_e_destino(db, usuario, contas):
    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, usuario.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["salario"].id,
            valor="100", data=date.today().isoformat(),
        )


def test_valor_zero_e_rejeitado(db, usuario, contas):
    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, usuario.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
            valor="0", data=date.today().isoformat(),
        )


def test_conta_de_outro_usuario_e_rejeitada(db, usuario, contas):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, outro.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
            valor="100", data=date.today().isoformat(),
        )


def test_excluir_transferencia_inexistente(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_transferencias.excluir(db, usuario.id, 999)


def test_transferencia_afeta_saldo_das_duas_contas(db, usuario, contas):
    servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    assert saldo_service.saldo_conta(db, contas["salario"].id) == -300
    assert saldo_service.saldo_conta(db, contas["investimento"].id) == 300


def test_transferencia_nao_conta_como_despesa_por_categoria(db, usuario, contas):
    # Regressão do ADR 0004: transferência não deve aparecer nos gastos por categoria.
    categoria = Categoria(usuario_id=usuario.id, nome="Mercado", tipo=TipoLancamento.DESPESA)
    db.add(categoria)
    db.commit()

    servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )

    total_despesas_por_categoria = (
        db.query(Lancamento).filter(Lancamento.categoria_id == categoria.id).count()
    )
    assert total_despesas_por_categoria == 0

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_transferencias_web.py' << 'ARQUIVO_FIM'
"""Teste de integração: separar parte do salário para investimento via transferência."""

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


def test_separar_parte_do_salario_para_investimento(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    cliente_logado.post("/contas", data={"nome": "Investimento"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})

    # Recebe 1000 de salário
    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1,
        "valor": "1000", "data": "2026-09-28",
    })
    # Separa 300 para investir
    resposta = cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 2,
        "valor": "300", "data": "2026-09-28", "descricao": "Aporte mensal",
    })
    assert "Salário" in resposta.text
    assert "Investimento" in resposta.text
    assert "Aporte mensal" in resposta.text

    saldos = cliente_logado.get("/contas")
    assert "R$ 700.00" in saldos.text   # 1000 - 300, na conta Salário
    assert "R$ 300.00" in saldos.text   # recebido na conta Investimento
    assert "R$ 1000.00" in saldos.text  # saldo geral continua o mesmo


def test_nao_permite_transferir_para_a_mesma_conta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    resposta = cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 1,
        "valor": "100", "data": "2026-09-28",
    })
    assert "não podem ser a mesma" in resposta.text

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: transferências entre contas, fechando a Etapa 2 (Etapa 2C)"
rm -- "$0"
echo "Commit feito. Rode: git push"
