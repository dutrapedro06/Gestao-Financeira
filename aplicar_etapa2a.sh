#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 2A..."

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


@app.get("/")
def raiz(usuario=Depends(usuario_atual_opcional)):
    if usuario is None:
        return RedirectResponse(url="/login")
    return RedirectResponse(url="/contas")


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
        <a href="/contas" class="text-slate-300 hover:text-white">Contas</a>
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
cat > 'app/repositories/base.py' << 'ARQUIVO_FIM'
"""Acesso a dados genérico para entidades que pertencem a um usuário."""

from typing import Any, Generic, TypeVar

from sqlalchemy import func
from sqlalchemy.orm import Session

T = TypeVar("T")


class RepositorioDoUsuario(Generic[T]):
    """Toda consulta é filtrada por usuario_id, garantindo o isolamento entre usuários."""

    def __init__(self, model: type[T]):
        self.model: Any = model

    def listar(self, db: Session, usuario_id: int) -> list[T]:
        return (
            db.query(self.model)
            .filter(self.model.usuario_id == usuario_id)
            .order_by(self.model.nome)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, item_id: int) -> T | None:
        return (
            db.query(self.model)
            .filter(self.model.id == item_id, self.model.usuario_id == usuario_id)
            .first()
        )

    def obter_por_nome(self, db: Session, usuario_id: int, nome: str) -> T | None:
        return (
            db.query(self.model)
            .filter(
                self.model.usuario_id == usuario_id,
                func.lower(self.model.nome) == nome.lower(),
            )
            .first()
        )

    def adicionar(self, db: Session, item: T) -> T:
        db.add(item)
        db.commit()
        db.refresh(item)
        return item

    def salvar(self, db: Session, item: T) -> T:
        db.commit()
        db.refresh(item)
        return item

    def remover(self, db: Session, item: T) -> None:
        db.delete(item)
        db.commit()

ARQUIVO_FIM

mkdir -p 'app/repositories'
cat > 'app/repositories/cadastros.py' << 'ARQUIVO_FIM'
"""Repositórios de contas, categorias e fontes de renda."""

from typing import Any

from sqlalchemy.orm import Session

from app.models import (
    Categoria,
    Conta,
    FonteDeRenda,
    Lancamento,
    RegraRecorrencia,
    TransferenciaEntreContas,
)
from app.repositories.base import RepositorioDoUsuario


def _existe(db: Session, model: Any, **filtros: Any) -> bool:
    return db.query(model.id).filter_by(**filtros).first() is not None


class RepositorioContas(RepositorioDoUsuario[Conta]):
    def em_uso(self, db: Session, conta_id: int) -> bool:
        return (
            _existe(db, Lancamento, conta_id=conta_id)
            or _existe(db, RegraRecorrencia, conta_id=conta_id)
            or _existe(db, TransferenciaEntreContas, conta_origem_id=conta_id)
            or _existe(db, TransferenciaEntreContas, conta_destino_id=conta_id)
        )


class RepositorioCategorias(RepositorioDoUsuario[Categoria]):
    def em_uso(self, db: Session, categoria_id: int) -> bool:
        return _existe(db, Lancamento, categoria_id=categoria_id) or _existe(
            db, RegraRecorrencia, categoria_id=categoria_id
        )


class RepositorioFontesRenda(RepositorioDoUsuario[FonteDeRenda]):
    def em_uso(self, db: Session, fonte_id: int) -> bool:
        return _existe(db, Lancamento, fonte_renda_id=fonte_id) or _existe(
            db, RegraRecorrencia, fonte_renda_id=fonte_id
        )


contas = RepositorioContas(Conta)
categorias = RepositorioCategorias(Categoria)
fontes_renda = RepositorioFontesRenda(FonteDeRenda)

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/cadastros.py' << 'ARQUIVO_FIM'
"""Regras de negócio dos cadastros básicos: contas, categorias e fontes de renda."""

from typing import Any

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda
from app.models.enums import TipoLancamento
from app.repositories import cadastros as repos

TAMANHO_MAXIMO_NOME = 80


class ErroDeNegocio(Exception):
    """Violação de regra de negócio; a mensagem pode ser exibida ao usuário."""


class NaoEncontrado(ErroDeNegocio):
    pass


class ServicoCadastro:
    def __init__(self, repo: Any, rotulo: str):
        self.repo = repo
        self.rotulo = rotulo

    def listar(self, db: Session, usuario_id: int) -> list:
        return self.repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, item_id: int):
        item = self.repo.obter(db, usuario_id, item_id)
        if item is None:
            raise NaoEncontrado(f"{self.rotulo} não encontrada.")
        return item

    def criar(self, db: Session, usuario_id: int, nome: str, **extra: Any):
        nome = self._validar_nome(db, usuario_id, nome)
        return self.repo.adicionar(db, self._construir(usuario_id, nome, **extra))

    def atualizar(self, db: Session, usuario_id: int, item_id: int, nome: str, **extra: Any):
        item = self.obter(db, usuario_id, item_id)
        nome = self._validar_nome(db, usuario_id, nome, ignorar_id=item.id)
        self._aplicar(db, item, nome, **extra)
        return self.repo.salvar(db, item)

    def excluir(self, db: Session, usuario_id: int, item_id: int) -> None:
        item = self.obter(db, usuario_id, item_id)
        if self.repo.em_uso(db, item.id):
            raise ErroDeNegocio(
                f"{self.rotulo} possui movimentações e não pode ser excluída."
            )
        self.repo.remover(db, item)

    def _validar_nome(
        self, db: Session, usuario_id: int, nome: str | None, ignorar_id: int | None = None
    ) -> str:
        nome = (nome or "").strip()
        if not nome:
            raise ErroDeNegocio("Informe um nome.")
        if len(nome) > TAMANHO_MAXIMO_NOME:
            raise ErroDeNegocio(f"O nome deve ter no máximo {TAMANHO_MAXIMO_NOME} caracteres.")
        existente = self.repo.obter_por_nome(db, usuario_id, nome)
        if existente is not None and existente.id != ignorar_id:
            raise ErroDeNegocio(f"Já existe {self.rotulo.lower()} com esse nome.")
        return nome

    def _construir(self, usuario_id: int, nome: str, **extra: Any):
        return self.repo.model(usuario_id=usuario_id, nome=nome)

    def _aplicar(self, db: Session, item: Any, nome: str, **extra: Any) -> None:
        item.nome = nome


class ServicoCategorias(ServicoCadastro):
    @staticmethod
    def _tipo(valor: str | None) -> TipoLancamento:
        try:
            return TipoLancamento(valor)
        except ValueError:
            raise ErroDeNegocio("Tipo inválido.") from None

    def _construir(self, usuario_id: int, nome: str, tipo: str | None = None, **extra: Any):
        return Categoria(usuario_id=usuario_id, nome=nome, tipo=self._tipo(tipo))

    def _aplicar(self, db: Session, item: Categoria, nome: str, tipo: str | None = None, **extra: Any) -> None:
        novo_tipo = self._tipo(tipo)
        if novo_tipo != item.tipo and self.repo.em_uso(db, item.id):
            raise ErroDeNegocio("Não é possível alterar o tipo de uma categoria já utilizada.")
        item.nome = nome
        item.tipo = novo_tipo


servico_contas = ServicoCadastro(repos.contas, "Conta")
servico_categorias = ServicoCategorias(repos.categorias, "Categoria")
servico_fontes_renda = ServicoCadastro(repos.fontes_renda, "Fonte de renda")

__all__ = [
    "Conta",
    "FonteDeRenda",
    "ErroDeNegocio",
    "NaoEncontrado",
    "servico_contas",
    "servico_categorias",
    "servico_fontes_renda",
]

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/saldo_service.py' << 'ARQUIVO_FIM'
"""Cálculo de saldo. O saldo nunca é armazenado: sempre derivado do histórico."""

from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models import Lancamento, TransferenciaEntreContas
from app.models.enums import TipoLancamento


def _soma(db: Session, coluna, *filtros) -> Decimal:
    total = db.query(func.coalesce(func.sum(coluna), 0)).filter(*filtros).scalar()
    return Decimal(str(total))


def saldo_conta(db: Session, conta_id: int) -> Decimal:
    receitas = _soma(
        db, Lancamento.valor, Lancamento.conta_id == conta_id, Lancamento.tipo == TipoLancamento.RECEITA
    )
    despesas = _soma(
        db, Lancamento.valor, Lancamento.conta_id == conta_id, Lancamento.tipo == TipoLancamento.DESPESA
    )
    recebido = _soma(
        db, TransferenciaEntreContas.valor, TransferenciaEntreContas.conta_destino_id == conta_id
    )
    enviado = _soma(
        db, TransferenciaEntreContas.valor, TransferenciaEntreContas.conta_origem_id == conta_id
    )
    return receitas - despesas + recebido - enviado


def saldos_das_contas(db: Session, contas: list) -> dict[int, Decimal]:
    return {conta.id: saldo_conta(db, conta.id) for conta in contas}


def saldo_geral(saldos: dict[int, Decimal]) -> Decimal:
    return sum(saldos.values(), Decimal("0"))

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/contas.py' << 'ARQUIVO_FIM'
"""Rotas web de contas."""

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services import saldo_service
from app.services.cadastros import ErroDeNegocio, NaoEncontrado, servico_contas
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/contas")
templates = Jinja2Templates(directory="app/templates")


def _contexto(db: Session, usuario: Usuario, editando_id: int | None = None, erro: str | None = None) -> dict:
    contas = servico_contas.listar(db, usuario.id)
    saldos = saldo_service.saldos_das_contas(db, contas)
    return {
        "usuario": usuario,
        "contas": contas,
        "saldos": saldos,
        "saldo_geral": saldo_service.saldo_geral(saldos),
        "editando_id": editando_id,
        "erro": erro,
    }


def _renderizar(request, db, usuario, template_completo, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/contas.html" if is_htmx else template_completo
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario, "contas.html")


@router.get("/{conta_id}/editar")
def editar(request: Request, conta_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario, "contas.html", editando_id=conta_id)


@router.post("")
def criar(
    request: Request,
    nome: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_contas.criar(db, usuario.id, nome)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, "contas.html", erro=str(erro))
    return _renderizar(request, db, usuario, "contas.html")


@router.put("/{conta_id}")
def atualizar(
    request: Request,
    conta_id: int,
    nome: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_contas.atualizar(db, usuario.id, conta_id, nome)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, "contas.html", erro=str(erro))
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, "contas.html", editando_id=conta_id, erro=str(erro))
    return _renderizar(request, db, usuario, "contas.html")


@router.delete("/{conta_id}")
def excluir(request: Request, conta_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_contas.excluir(db, usuario.id, conta_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, "contas.html", erro=str(erro))
    return _renderizar(request, db, usuario, "contas.html")

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/categorias.py' << 'ARQUIVO_FIM'
"""Rotas web de categorias."""

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services.cadastros import ErroDeNegocio, NaoEncontrado, servico_categorias
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/categorias")
templates = Jinja2Templates(directory="app/templates")


def _contexto(db: Session, usuario: Usuario, editando_id: int | None = None, erro: str | None = None) -> dict:
    return {
        "usuario": usuario,
        "categorias": servico_categorias.listar(db, usuario.id),
        "editando_id": editando_id,
        "erro": erro,
    }


def _renderizar(request: Request, db, usuario, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/categorias.html" if is_htmx else "categorias.html"
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario)


@router.get("/{categoria_id}/editar")
def editar(request: Request, categoria_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario, editando_id=categoria_id)


@router.post("")
def criar(
    request: Request,
    nome: str = Form(...),
    tipo: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_categorias.criar(db, usuario.id, nome, tipo=tipo)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.put("/{categoria_id}")
def atualizar(
    request: Request,
    categoria_id: int,
    nome: str = Form(...),
    tipo: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_categorias.atualizar(db, usuario.id, categoria_id, nome, tipo=tipo)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, editando_id=categoria_id, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.delete("/{categoria_id}")
def excluir(request: Request, categoria_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_categorias.excluir(db, usuario.id, categoria_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/fontes_renda.py' << 'ARQUIVO_FIM'
"""Rotas web de fontes de renda."""

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services.cadastros import ErroDeNegocio, NaoEncontrado, servico_fontes_renda
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/fontes-renda")
templates = Jinja2Templates(directory="app/templates")


def _contexto(db: Session, usuario: Usuario, editando_id: int | None = None, erro: str | None = None) -> dict:
    return {
        "usuario": usuario,
        "fontes": servico_fontes_renda.listar(db, usuario.id),
        "editando_id": editando_id,
        "erro": erro,
    }


def _renderizar(request: Request, db, usuario, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/fontes_renda.html" if is_htmx else "fontes_renda.html"
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario)


@router.get("/{fonte_id}/editar")
def editar(request: Request, fonte_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario, editando_id=fonte_id)


@router.post("")
def criar(
    request: Request,
    nome: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_fontes_renda.criar(db, usuario.id, nome)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.put("/{fonte_id}")
def atualizar(
    request: Request,
    fonte_id: int,
    nome: str = Form(...),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    try:
        servico_fontes_renda.atualizar(db, usuario.id, fonte_id, nome)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, editando_id=fonte_id, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.delete("/{fonte_id}")
def excluir(request: Request, fonte_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_fontes_renda.excluir(db, usuario.id, fonte_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/contas.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Contas — Gestão Financeira{% endblock %}
{% block conteudo %}
{% include "partials/contas.html" %}
{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/categorias.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Categorias — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/categorias.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/fontes_renda.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Fontes de renda — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/fontes_renda.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/contas.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-1">Contas</h1>
<p class="text-slate-400 mb-6">Saldo geral: <span class="font-medium text-slate-100">R$ {{ "%.2f"|format(saldo_geral) }}</span></p>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

<ul class="space-y-2 mb-6">
  {% for conta in contas %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3">
    {% if conta.id == editando_id %}
    <form hx-put="/contas/{{ conta.id }}" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2 items-center">
      <input name="nome" value="{{ conta.nome }}" required maxlength="80"
             class="flex-1 rounded-md bg-slate-800 border border-slate-700 px-2 py-1 text-sm">
      <button class="text-emerald-400 hover:text-emerald-300 text-sm">Salvar</button>
      <a href="/contas" hx-get="/contas" hx-target="#pagina" hx-swap="outerHTML" class="text-slate-400 hover:text-white text-sm cursor-pointer">Cancelar</a>
    </form>
    {% else %}
    <div class="flex items-center justify-between">
      <div>
        <span class="font-medium">{{ conta.nome }}</span>
        <span class="text-slate-400 text-sm ml-2">{{ conta.moeda }}</span>
      </div>
      <div class="flex items-center gap-4">
        <span class="tabular-nums">R$ {{ "%.2f"|format(saldos[conta.id]) }}</span>
        <a hx-get="/contas/{{ conta.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
           class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
        <a hx-delete="/contas/{{ conta.id }}" hx-target="#pagina" hx-swap="outerHTML"
           hx-confirm="Excluir a conta '{{ conta.nome }}'?"
           class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
      </div>
    </div>
    {% endif %}
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhuma conta cadastrada ainda.</li>
  {% endfor %}
</ul>

<form hx-post="/contas" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2">
  <input name="nome" placeholder="Nova conta (ex: Conta corrente)" required maxlength="80"
         class="flex-1 rounded-md bg-slate-900 border border-slate-700 px-3 py-2">
  <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">Adicionar</button>
</form>
</div>

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/categorias.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-6">Categorias</h1>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

<ul class="space-y-2 mb-6">
  {% for categoria in categorias %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3">
    {% if categoria.id == editando_id %}
    <form hx-put="/categorias/{{ categoria.id }}" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2 items-center">
      <input name="nome" value="{{ categoria.nome }}" required maxlength="80"
             class="flex-1 rounded-md bg-slate-800 border border-slate-700 px-2 py-1 text-sm">
      <select name="tipo" class="rounded-md bg-slate-800 border border-slate-700 px-2 py-1 text-sm">
        <option value="receita" {% if categoria.tipo.value == "receita" %}selected{% endif %}>Receita</option>
        <option value="despesa" {% if categoria.tipo.value == "despesa" %}selected{% endif %}>Despesa</option>
      </select>
      <button class="text-emerald-400 hover:text-emerald-300 text-sm">Salvar</button>
      <a hx-get="/categorias" hx-target="#pagina" hx-swap="outerHTML" class="text-slate-400 hover:text-white text-sm cursor-pointer">Cancelar</a>
    </form>
    {% else %}
    <div class="flex items-center justify-between">
      <div>
        <span class="font-medium">{{ categoria.nome }}</span>
        <span class="text-xs ml-2 px-2 py-0.5 rounded-full {{ 'bg-emerald-900 text-emerald-300' if categoria.tipo.value == 'receita' else 'bg-rose-900 text-rose-300' }}">
          {{ "Receita" if categoria.tipo.value == "receita" else "Despesa" }}
        </span>
      </div>
      <div class="flex items-center gap-4">
        <a hx-get="/categorias/{{ categoria.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
           class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
        <a hx-delete="/categorias/{{ categoria.id }}" hx-target="#pagina" hx-swap="outerHTML"
           hx-confirm="Excluir a categoria '{{ categoria.nome }}'?"
           class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
      </div>
    </div>
    {% endif %}
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhuma categoria cadastrada ainda.</li>
  {% endfor %}
</ul>

<form hx-post="/categorias" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2">
  <input name="nome" placeholder="Nova categoria (ex: Mercado)" required maxlength="80"
         class="flex-1 rounded-md bg-slate-900 border border-slate-700 px-3 py-2">
  <select name="tipo" class="rounded-md bg-slate-900 border border-slate-700 px-3 py-2">
    <option value="despesa">Despesa</option>
    <option value="receita">Receita</option>
  </select>
  <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">Adicionar</button>
</form>
</div>

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/fontes_renda.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-6">Fontes de renda</h1>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

<ul class="space-y-2 mb-6">
  {% for fonte in fontes %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3">
    {% if fonte.id == editando_id %}
    <form hx-put="/fontes-renda/{{ fonte.id }}" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2 items-center">
      <input name="nome" value="{{ fonte.nome }}" required maxlength="80"
             class="flex-1 rounded-md bg-slate-800 border border-slate-700 px-2 py-1 text-sm">
      <button class="text-emerald-400 hover:text-emerald-300 text-sm">Salvar</button>
      <a hx-get="/fontes-renda" hx-target="#pagina" hx-swap="outerHTML" class="text-slate-400 hover:text-white text-sm cursor-pointer">Cancelar</a>
    </form>
    {% else %}
    <div class="flex items-center justify-between">
      <span class="font-medium">{{ fonte.nome }}</span>
      <div class="flex items-center gap-4">
        <a hx-get="/fontes-renda/{{ fonte.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
           class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
        <a hx-delete="/fontes-renda/{{ fonte.id }}" hx-target="#pagina" hx-swap="outerHTML"
           hx-confirm="Excluir a fonte '{{ fonte.nome }}'?"
           class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
      </div>
    </div>
    {% endif %}
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhuma fonte de renda cadastrada ainda.</li>
  {% endfor %}
</ul>

<form hx-post="/fontes-renda" hx-target="#pagina" hx-swap="outerHTML" class="flex gap-2">
  <input name="nome" placeholder="Nova fonte (ex: Salário CLT)" required maxlength="80"
         class="flex-1 rounded-md bg-slate-900 border border-slate-700 px-3 py-2">
  <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">Adicionar</button>
</form>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_saldo_service.py' << 'ARQUIVO_FIM'
"""
Testes unitários do cálculo de saldo. Usa SQLite em memória (não o
Postgres de produção) — o service não depende de nada específico do
dialeto do banco, então isso valida a lógica de forma rápida e isolada.
"""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Conta, Lancamento, TransferenciaEntreContas, Usuario
from app.models.enums import TipoLancamento
from app.services import saldo_service


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    usuario = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(usuario)
    db.commit()
    return usuario


def test_saldo_conta_sem_movimentacao_e_zero(db, usuario):
    conta = Conta(usuario_id=usuario.id, nome="Conta Corrente")
    db.add(conta)
    db.commit()

    assert saldo_service.saldo_conta(db, conta.id) == 0


def test_saldo_conta_soma_receita_e_subtrai_despesa(db, usuario):
    conta = Conta(usuario_id=usuario.id, nome="Conta Corrente")
    categoria = Categoria(usuario_id=usuario.id, nome="Salário", tipo=TipoLancamento.RECEITA)
    db.add_all([conta, categoria])
    db.commit()

    db.add_all([
        Lancamento(
            conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.RECEITA,
            valor=1000, data=date.today(),
        ),
        Lancamento(
            conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
            valor=300, data=date.today(),
        ),
    ])
    db.commit()

    assert saldo_service.saldo_conta(db, conta.id) == 700


def test_transferencia_afeta_as_duas_contas_sem_contar_como_gasto(db, usuario):
    origem = Conta(usuario_id=usuario.id, nome="Salário")
    destino = Conta(usuario_id=usuario.id, nome="Investimento")
    db.add_all([origem, destino])
    db.commit()

    db.add(TransferenciaEntreContas(
        conta_origem_id=origem.id, conta_destino_id=destino.id,
        valor=300, data=date.today(),
    ))
    db.commit()

    assert saldo_service.saldo_conta(db, origem.id) == -300
    assert saldo_service.saldo_conta(db, destino.id) == 300


def test_saldo_geral_soma_todas_as_contas(db, usuario):
    a = Conta(usuario_id=usuario.id, nome="A")
    b = Conta(usuario_id=usuario.id, nome="B")
    db.add_all([a, b])
    db.commit()

    saldos = {a.id: 100, b.id: 50}
    assert saldo_service.saldo_geral(saldos) == 150

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_servico_cadastros.py' << 'ARQUIVO_FIM'
"""Testes unitários dos serviços de cadastro (contas, categorias, fontes de renda)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Conta, Lancamento, Usuario
from app.models.enums import TipoLancamento
from app.services.cadastros import ErroDeNegocio, NaoEncontrado, servico_categorias, servico_contas


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    usuario = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(usuario)
    db.commit()
    return usuario


def test_criar_conta(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    assert conta.id is not None
    assert conta.nome == "Conta Corrente"


def test_nao_permite_nome_duplicado(db, usuario):
    servico_contas.criar(db, usuario.id, "Conta Corrente")
    with pytest.raises(ErroDeNegocio):
        servico_contas.criar(db, usuario.id, "conta corrente")  # case-insensitive


def test_nao_permite_nome_vazio(db, usuario):
    with pytest.raises(ErroDeNegocio):
        servico_contas.criar(db, usuario.id, "   ")


def test_atualizar_conta_inexistente_lanca_nao_encontrado(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_contas.atualizar(db, usuario.id, 999, "Nome qualquer")


def test_excluir_conta_em_uso_e_bloqueado(db, usuario):
    categoria = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    db.add(Lancamento(
        conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
        valor=50, data=date.today(),
    ))
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_contas.excluir(db, usuario.id, conta.id)


def test_excluir_conta_sem_uso_funciona(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    servico_contas.excluir(db, usuario.id, conta.id)
    assert servico_contas.listar(db, usuario.id) == []


def test_isolamento_entre_usuarios(db, usuario):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    servico_contas.criar(db, usuario.id, "Conta do Pedro")
    assert servico_contas.listar(db, outro.id) == []


def test_categoria_nao_pode_trocar_tipo_se_ja_usada(db, usuario):
    categoria = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    db.add(Lancamento(
        conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
        valor=50, data=date.today(),
    ))
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_categorias.atualizar(db, usuario.id, categoria.id, "Mercado", tipo="receita")

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_contas_web.py' << 'ARQUIVO_FIM'
"""
Teste de integração ponta a ponta: login real + CRUD de contas via HTTP,
usando SQLite em memória no lugar do Postgres (mais rápido, sem precisar
do docker-compose para rodar este teste específico).
"""

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
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
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


def test_login_com_credenciais_erradas_mostra_erro():
    cliente = TestClient(app)
    resposta = cliente.post("/login", data={"email": "x@x.com", "senha": "errada"})
    assert resposta.status_code == 401
    assert "incorretos" in resposta.text


def test_criar_e_listar_conta(cliente_logado):
    resposta = cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    assert resposta.status_code == 200
    assert "Conta Corrente" in resposta.text
    assert "R$ 0.00" in resposta.text  # saldo geral, sem lançamentos ainda


def test_nao_permite_conta_duplicada(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    resposta = cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    assert "Já existe" in resposta.text


def test_editar_conta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    resposta = cliente_logado.get("/contas")
    conta_id = 1  # primeira conta criada no banco limpo
    resposta = cliente_logado.put(f"/contas/{conta_id}", data={"nome": "Conta Renomeada"})
    assert "Conta Renomeada" in resposta.text


def test_criar_categoria_e_impedir_exclusao_em_uso(cliente_logado):
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    resposta = cliente_logado.get("/categorias")
    assert "Mercado" in resposta.text
    assert "Despesa" in resposta.text


def test_rotas_exigem_login():
    cliente = TestClient(app)
    resposta = cliente.get("/contas", follow_redirects=False)
    assert resposta.status_code == 401

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: CRUD de contas, categorias e fontes de renda com cálculo de saldo (Etapa 2A)"
rm -- "$0"
echo "Commit feito. Rode: git push"
