#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 2B..."

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

mkdir -p 'app/services'
cat > 'app/services/cadastros.py' << 'ARQUIVO_FIM'
"""Regras de negócio dos cadastros básicos: contas, categorias e fontes de renda."""

from typing import Any

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda
from app.models.enums import TipoLancamento
from app.repositories import cadastros as repos

from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_NOME = 80


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
cat > 'app/services/erros.py' << 'ARQUIVO_FIM'
"""Exceções de negócio compartilhadas entre os services."""


class ErroDeNegocio(Exception):
    """Violação de regra de negócio; a mensagem pode ser exibida ao usuário."""


class NaoEncontrado(ErroDeNegocio):
    pass

ARQUIVO_FIM

mkdir -p 'app/repositories'
cat > 'app/repositories/lancamentos.py' << 'ARQUIVO_FIM'
"""
Repositório de Lancamento.

Diferente de Conta/Categoria/FonteDeRenda, Lancamento não tem usuario_id
direto — o isolamento por usuário é garantido via join com Conta.
"""

from sqlalchemy.orm import Session

from app.models import Conta, Lancamento


class RepositorioLancamentos:
    def listar(self, db: Session, usuario_id: int, limite: int = 200) -> list[Lancamento]:
        return (
            db.query(Lancamento)
            .join(Conta, Lancamento.conta_id == Conta.id)
            .filter(Conta.usuario_id == usuario_id)
            .order_by(Lancamento.data.desc(), Lancamento.id.desc())
            .limit(limite)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, lancamento_id: int) -> Lancamento | None:
        return (
            db.query(Lancamento)
            .join(Conta, Lancamento.conta_id == Conta.id)
            .filter(Lancamento.id == lancamento_id, Conta.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, lancamento: Lancamento) -> Lancamento:
        db.add(lancamento)
        db.commit()
        db.refresh(lancamento)
        return lancamento

    def salvar(self, db: Session, lancamento: Lancamento) -> Lancamento:
        db.commit()
        db.refresh(lancamento)
        return lancamento

    def remover(self, db: Session, lancamento: Lancamento) -> None:
        db.delete(lancamento)
        db.commit()


lancamentos = RepositorioLancamentos()

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/lancamentos.py' << 'ARQUIVO_FIM'
"""Regras de negócio dos lançamentos (receitas e despesas)."""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda, Lancamento
from app.models.enums import TipoLancamento
from app.repositories.lancamentos import lancamentos as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_DESCRICAO = 255


def _tipo(valor: str | None) -> TipoLancamento:
    try:
        return TipoLancamento(valor)
    except ValueError:
        raise ErroDeNegocio("Tipo inválido.") from None


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


def _categoria_do_usuario(db: Session, usuario_id: int, categoria_id: int, tipo: TipoLancamento) -> Categoria:
    categoria = (
        db.query(Categoria).filter(Categoria.id == categoria_id, Categoria.usuario_id == usuario_id).first()
    )
    if categoria is None:
        raise ErroDeNegocio("Categoria inválida.")
    if categoria.tipo != tipo:
        raise ErroDeNegocio(
            f"A categoria '{categoria.nome}' é de {categoria.tipo.value}, "
            f"não pode ser usada num lançamento de {tipo.value}."
        )
    return categoria


def _fonte_renda_do_usuario(db: Session, usuario_id: int, fonte_renda_id: int | None) -> FonteDeRenda | None:
    if not fonte_renda_id:
        return None
    fonte = (
        db.query(FonteDeRenda)
        .filter(FonteDeRenda.id == fonte_renda_id, FonteDeRenda.usuario_id == usuario_id)
        .first()
    )
    if fonte is None:
        raise ErroDeNegocio("Fonte de renda inválida.")
    return fonte


class ServicoLancamentos:
    def listar(self, db: Session, usuario_id: int) -> list[Lancamento]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, lancamento_id: int) -> Lancamento:
        lancamento = repo.obter(db, usuario_id, lancamento_id)
        if lancamento is None:
            raise NaoEncontrado("Lançamento não encontrado.")
        return lancamento

    def criar(
        self,
        db: Session,
        usuario_id: int,
        *,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None = None,
        descricao: str | None = None,
    ) -> Lancamento:
        lancamento = Lancamento(
            **self._validar(db, usuario_id, tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
        )
        return repo.adicionar(db, lancamento)

    def atualizar(
        self,
        db: Session,
        usuario_id: int,
        lancamento_id: int,
        *,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None = None,
        descricao: str | None = None,
    ) -> Lancamento:
        lancamento = self.obter(db, usuario_id, lancamento_id)
        dados = self._validar(db, usuario_id, tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
        for campo, valor_campo in dados.items():
            setattr(lancamento, campo, valor_campo)
        return repo.salvar(db, lancamento)

    def excluir(self, db: Session, usuario_id: int, lancamento_id: int) -> None:
        lancamento = self.obter(db, usuario_id, lancamento_id)
        repo.remover(db, lancamento)

    def _validar(
        self,
        db: Session,
        usuario_id: int,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None,
        descricao: str | None,
    ) -> dict:
        tipo_validado = _tipo(tipo)
        conta = _conta_do_usuario(db, usuario_id, conta_id)
        categoria = _categoria_do_usuario(db, usuario_id, categoria_id, tipo_validado)
        # Fonte de renda só faz sentido numa receita — ignorada silenciosamente numa despesa.
        fonte = (
            _fonte_renda_do_usuario(db, usuario_id, fonte_renda_id)
            if tipo_validado == TipoLancamento.RECEITA
            else None
        )
        descricao = (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None

        return {
            "tipo": tipo_validado,
            "conta_id": conta.id,
            "categoria_id": categoria.id,
            "fonte_renda_id": fonte.id if fonte else None,
            "valor": _valor_monetario(valor),
            "data": _data(data),
            "descricao": descricao,
        }


servico_lancamentos = ServicoLancamentos()

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/lancamentos.py' << 'ARQUIVO_FIM'
"""Rotas web de lançamentos (receitas e despesas)."""

from datetime import date

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services import saldo_service
from app.services.cadastros import servico_categorias, servico_contas, servico_fontes_renda
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.lancamentos import servico_lancamentos
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/lancamentos")
templates = Jinja2Templates(directory="app/templates")


def _contexto(
    db: Session,
    usuario: Usuario,
    editando: object | None = None,
    erro: str | None = None,
) -> dict:
    contas = servico_contas.listar(db, usuario.id)
    return {
        "usuario": usuario,
        "lancamentos": servico_lancamentos.listar(db, usuario.id),
        "contas": contas,
        "categorias": servico_categorias.listar(db, usuario.id),
        "fontes": servico_fontes_renda.listar(db, usuario.id),
        "saldos": saldo_service.saldos_das_contas(db, contas),
        "hoje": date.today().isoformat(),
        "editando": editando,
        "erro": erro,
    }


def _renderizar(request: Request, db, usuario, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/lancamentos.html" if is_htmx else "lancamentos.html"
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


def _dados_form(
    tipo: str, conta_id: int, categoria_id: int, valor: str, data: str, fonte_renda_id: int, descricao: str
) -> dict:
    return {
        "tipo": tipo,
        "conta_id": conta_id,
        "categoria_id": categoria_id,
        "fonte_renda_id": fonte_renda_id or None,
        "valor": valor,
        "data": data,
        "descricao": descricao,
    }


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario)


@router.get("/{lancamento_id}/editar")
def editar(request: Request, lancamento_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        lancamento = servico_lancamentos.obter(db, usuario.id, lancamento_id)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario, editando=lancamento)


@router.post("")
def criar(
    request: Request,
    tipo: str = Form(...),
    conta_id: int = Form(...),
    categoria_id: int = Form(...),
    valor: str = Form(...),
    data: str = Form(...),
    fonte_renda_id: int = Form(None),
    descricao: str = Form(""),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    dados = _dados_form(tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
    try:
        servico_lancamentos.criar(db, usuario.id, **dados)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.put("/{lancamento_id}")
def atualizar(
    request: Request,
    lancamento_id: int,
    tipo: str = Form(...),
    conta_id: int = Form(...),
    categoria_id: int = Form(...),
    valor: str = Form(...),
    data: str = Form(...),
    fonte_renda_id: int = Form(None),
    descricao: str = Form(""),
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    dados = _dados_form(tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
    try:
        servico_lancamentos.atualizar(db, usuario.id, lancamento_id, **dados)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    except ErroDeNegocio as erro:
        try:
            lancamento = servico_lancamentos.obter(db, usuario.id, lancamento_id)
        except NaoEncontrado:
            lancamento = None
        return _renderizar(request, db, usuario, editando=lancamento, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.delete("/{lancamento_id}")
def excluir(request: Request, lancamento_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_lancamentos.excluir(db, usuario.id, lancamento_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/lancamentos.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Lançamentos — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/lancamentos.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/lancamentos.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-6">Lançamentos</h1>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

{% if not contas or not categorias %}
<div class="bg-amber-900/40 border border-amber-700 text-amber-200 text-sm rounded-md px-4 py-2 mb-4">
  Cadastre pelo menos uma <a href="/contas" class="underline">conta</a> e uma
  <a href="/categorias" class="underline">categoria</a> antes de lançar algo.
</div>
{% endif %}

{% set alvo = "/lancamentos/" ~ editando.id if editando else "/lancamentos" %}
{% set metodo = "hx-put" if editando else "hx-post" %}

<form {{ metodo }}="{{ alvo }}" hx-target="#pagina" hx-swap="outerHTML"
      class="bg-slate-900 border border-slate-800 rounded-md p-4 mb-6 space-y-3">
  <div class="grid grid-cols-2 gap-3">
    <select name="tipo" class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="despesa" {% if not editando or editando.tipo.value == "despesa" %}selected{% endif %}>Despesa</option>
      <option value="receita" {% if editando and editando.tipo.value == "receita" %}selected{% endif %}>Receita</option>
    </select>
    <input type="number" step="0.01" min="0.01" name="valor" placeholder="Valor"
           value="{{ editando.valor if editando else '' }}" required
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>

  <div class="grid grid-cols-2 gap-3">
    <select name="conta_id" required class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="" disabled {% if not editando %}selected{% endif %}>Conta</option>
      {% for conta in contas %}
      <option value="{{ conta.id }}" {% if editando and editando.conta_id == conta.id %}selected{% endif %}>{{ conta.nome }}</option>
      {% endfor %}
    </select>
    <select name="categoria_id" required class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="" disabled {% if not editando %}selected{% endif %}>Categoria</option>
      {% for categoria in categorias %}
      <option value="{{ categoria.id }}" {% if editando and editando.categoria_id == categoria.id %}selected{% endif %}>
        {{ categoria.nome }} ({{ categoria.tipo.value }})
      </option>
      {% endfor %}
    </select>
  </div>

  <div class="grid grid-cols-2 gap-3">
    <input type="date" name="data" value="{{ editando.data.isoformat() if editando else hoje }}" required
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    <select name="fonte_renda_id" class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="">Fonte de renda (opcional, só receita)</option>
      {% for fonte in fontes %}
      <option value="{{ fonte.id }}" {% if editando and editando.fonte_renda_id == fonte.id %}selected{% endif %}>{{ fonte.nome }}</option>
      {% endfor %}
    </select>
  </div>

  <input name="descricao" placeholder="Descrição (opcional)" maxlength="255"
         value="{{ editando.descricao or '' if editando else '' }}"
         class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">

  <div class="flex gap-2">
    <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">
      {{ "Salvar" if editando else "Lançar" }}
    </button>
    {% if editando %}
    <a hx-get="/lancamentos" hx-target="#pagina" hx-swap="outerHTML"
       class="text-slate-400 hover:text-white text-sm self-center cursor-pointer">Cancelar</a>
    {% endif %}
  </div>
</form>

<ul class="space-y-2">
  {% for l in lancamentos %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <span class="text-xs px-2 py-0.5 rounded-full {{ 'bg-rose-900 text-rose-300' if l.tipo.value == 'despesa' else 'bg-emerald-900 text-emerald-300' }}">
        {{ "Despesa" if l.tipo.value == "despesa" else "Receita" }}
      </span>
      <div>
        <div class="font-medium">{{ l.categoria.nome }} <span class="text-slate-400 font-normal">· {{ l.conta.nome }}</span></div>
        {% if l.descricao %}<div class="text-sm text-slate-400">{{ l.descricao }}</div>{% endif %}
      </div>
    </div>
    <div class="flex items-center gap-4">
      <span class="text-slate-400 text-sm">{{ l.data.strftime("%d/%m/%Y") }}</span>
      <span class="tabular-nums {{ 'text-rose-300' if l.tipo.value == 'despesa' else 'text-emerald-300' }}">
        {{ "-" if l.tipo.value == "despesa" else "+" }}R$ {{ "%.2f"|format(l.valor) }}
      </span>
      <a hx-get="/lancamentos/{{ l.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
         class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
      <a hx-delete="/lancamentos/{{ l.id }}" hx-target="#pagina" hx-swap="outerHTML"
         hx-confirm="Excluir este lançamento?"
         class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
    </div>
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhum lançamento ainda.</li>
  {% endfor %}
</ul>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_servico_lancamentos.py' << 'ARQUIVO_FIM'
"""Testes unitários das regras de negócio de lançamentos."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services.cadastros import servico_categorias, servico_contas, servico_fontes_renda
from app.services.erros import ErroDeNegocio, NaoEncontrado
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
    conta_salario = servico_contas.criar(db, usuario.id, "Salário")
    conta_vale = servico_contas.criar(db, usuario.id, "Vale")
    categoria_mercado = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    categoria_salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")
    fonte = servico_fontes_renda.criar(db, usuario.id, "Salário CLT")
    return {
        "conta_salario": conta_salario,
        "conta_vale": conta_vale,
        "categoria_mercado": categoria_mercado,
        "categoria_salario": categoria_salario,
        "fonte": fonte,
    }


def test_criar_despesa_na_conta_escolhida(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        valor="50", data=date.today().isoformat(),
    )
    assert lancamento.conta_id == cenario["conta_vale"].id
    assert lancamento.valor == 50


def test_criar_receita_com_fonte(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="receita", conta_id=cenario["conta_salario"].id, categoria_id=cenario["categoria_salario"].id,
        fonte_renda_id=cenario["fonte"].id, valor="1000", data=date.today().isoformat(),
    )
    assert lancamento.fonte_renda_id == cenario["fonte"].id


def test_fonte_de_renda_e_ignorada_em_despesa(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        fonte_renda_id=cenario["fonte"].id, valor="50", data=date.today().isoformat(),
    )
    assert lancamento.fonte_renda_id is None


def test_categoria_de_tipo_errado_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, usuario.id,
            tipo="receita", conta_id=cenario["conta_salario"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="50", data=date.today().isoformat(),
        )


def test_valor_zero_ou_negativo_e_rejeitado(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, usuario.id,
            tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="0", data=date.today().isoformat(),
        )


def test_conta_de_outro_usuario_e_rejeitada(db, usuario, cenario):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, outro.id,
            tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="50", data=date.today().isoformat(),
        )


def test_excluir_lancamento_inexistente(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_lancamentos.excluir(db, usuario.id, 999)


def test_saldo_reflete_lancamento_na_conta_certa(db, usuario, cenario):
    from app.services import saldo_service

    servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        valor="50", data=date.today().isoformat(),
    )
    assert saldo_service.saldo_conta(db, cenario["conta_vale"].id) == -50
    assert saldo_service.saldo_conta(db, cenario["conta_salario"].id) == 0

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_lancamentos_web.py' << 'ARQUIVO_FIM'
"""Teste de integração: fluxo completo de lançar uma despesa via HTTP."""

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


def test_lancar_despesa_de_ponta_a_ponta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Vale"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})

    resposta = cliente_logado.post(
        "/lancamentos",
        data={
            "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
            "valor": "50.00", "data": "2026-09-28", "descricao": "Compras da semana",
        },
    )
    assert resposta.status_code == 200
    assert "Mercado" in resposta.text
    assert "Compras da semana" in resposta.text
    assert "-R$ 50.00" in resposta.text

    saldo_contas = cliente_logado.get("/contas")
    assert "R$ -50.00" in saldo_contas.text


def test_lancamento_sem_conta_cadastrada_mostra_aviso(cliente_logado):
    resposta = cliente_logado.get("/lancamentos")
    assert "Cadastre pelo menos uma" in resposta.text

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: lançamentos de receitas e despesas com validações de negócio (Etapa 2B)"
rm -- "$0"
echo "Commit feito. Rode: git push"
