#!/usr/bin/env bash
set -e
# Rode na raiz do repositório (~/Gestao-financeira). O script se apaga ao final.
echo "Criando/atualizando arquivos da Etapa 3..."

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
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
    {% if usuario %}
    <nav class="border-b border-slate-800 px-4 py-3 flex items-center gap-4 text-sm">
        <a href="/" class="font-semibold">Gestão Financeira</a>
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
    <main class="max-w-2xl mx-auto mt-10 px-4">
        {% block conteudo %}{% endblock %}
    </main>
</body>
</html>

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/regra_recorrencia.py' << 'ARQUIVO_FIM'
"""
RegraRecorrencia: template de um lançamento que se repete (ex: aluguel
todo dia 5). Usada tanto para lançamento automático quanto para
alimentar as projeções de saldo futuro (ADR 0005) — o service de projeção
usa estes dados para calcular lançamentos futuros "sob demanda", sem
precisar persistir todos eles com antecedência.
"""

from datetime import date

from sqlalchemy import Date, Enum, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import FrequenciaRecorrencia, TipoLancamento


class RegraRecorrencia(Base):
    __tablename__ = "regras_recorrencia"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    conta_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False)
    categoria_id: Mapped[int] = mapped_column(ForeignKey("categorias.id"), nullable=False)
    fonte_renda_id: Mapped[int | None] = mapped_column(ForeignKey("fontes_renda.id"), nullable=True)

    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)
    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    frequencia: Mapped[FrequenciaRecorrencia] = mapped_column(Enum(FrequenciaRecorrencia), nullable=False)
    # Para frequência mensal: dia do mês (1-28, evitando ambiguidade em
    # meses curtos). Para semanal: dia da semana (0=segunda ... 6=domingo).
    dia_referencia: Mapped[int] = mapped_column(nullable=False)

    data_inicio: Mapped[date] = mapped_column(Date, nullable=False)
    data_fim: Mapped[date | None] = mapped_column(Date, nullable=True)
    ativa: Mapped[bool] = mapped_column(default=True, server_default="true")

    usuario: Mapped["Usuario"] = relationship(back_populates="regras_recorrencia")
    conta: Mapped["Conta"] = relationship()
    categoria: Mapped["Categoria"] = relationship()
    fonte_renda: Mapped["FonteDeRenda"] = relationship()
    lancamentos_gerados: Mapped[list["Lancamento"]] = relationship(back_populates="regra_recorrencia")

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
        <div class="font-medium">
          {{ l.categoria.nome }} <span class="text-slate-400 font-normal">· {{ l.conta.nome }}</span>
          {% if l.regra_recorrencia_id %}<span class="text-xs text-slate-500">(automático)</span>{% endif %}
        </div>
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
from app.services.regras_recorrencia import gerar_lancamentos_pendentes
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
    gerar_lancamentos_pendentes(db, usuario.id)
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

mkdir -p 'app/repositories'
cat > 'app/repositories/regras_recorrencia.py' << 'ARQUIVO_FIM'
"""Repositório de RegraRecorrencia."""

from sqlalchemy.orm import Session

from app.models import RegraRecorrencia


class RepositorioRegrasRecorrencia:
    def listar(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.usuario_id == usuario_id)
            .order_by(RegraRecorrencia.ativa.desc(), RegraRecorrencia.data_inicio.desc())
            .all()
        )

    def listar_ativas(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.usuario_id == usuario_id, RegraRecorrencia.ativa.is_(True))
            .all()
        )

    def obter(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia | None:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.id == regra_id, RegraRecorrencia.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, regra: RegraRecorrencia) -> RegraRecorrencia:
        db.add(regra)
        db.commit()
        db.refresh(regra)
        return regra

    def salvar(self, db: Session, regra: RegraRecorrencia) -> RegraRecorrencia:
        db.commit()
        db.refresh(regra)
        return regra

    def remover(self, db: Session, regra: RegraRecorrencia) -> None:
        db.delete(regra)
        db.commit()


regras_recorrencia = RepositorioRegrasRecorrencia()

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/ocorrencias.py' << 'ARQUIVO_FIM'
"""
Cálculo de datas de ocorrência de uma RegraRecorrencia.

Isolado num módulo próprio (sem depender de banco de dados) para poder
ser testado como lógica pura de calendário — a parte mais fácil de
acertar errado num cálculo de recorrência.
"""

from calendar import monthrange
from datetime import date, timedelta

from app.models.enums import FrequenciaRecorrencia
from app.models.regra_recorrencia import RegraRecorrencia


def _ocorrencias_mensais(regra: RegraRecorrencia, ate: date) -> list[date]:
    ocorrencias = []
    ano, mes = regra.data_inicio.year, regra.data_inicio.month

    while True:
        ultimo_dia_do_mes = monthrange(ano, mes)[1]
        dia = min(regra.dia_referencia, ultimo_dia_do_mes)
        ocorrencia = date(ano, mes, dia)

        if ocorrencia > ate:
            break
        if regra.data_fim and ocorrencia > regra.data_fim:
            break
        if ocorrencia >= regra.data_inicio:
            ocorrencias.append(ocorrencia)

        mes += 1
        if mes > 12:
            mes = 1
            ano += 1

    return ocorrencias


def _ocorrencias_semanais(regra: RegraRecorrencia, ate: date) -> list[date]:
    ocorrencias = []
    dias_ate_o_dia_da_semana = (regra.dia_referencia - regra.data_inicio.weekday()) % 7
    ocorrencia = regra.data_inicio + timedelta(days=dias_ate_o_dia_da_semana)

    while ocorrencia <= ate and (not regra.data_fim or ocorrencia <= regra.data_fim):
        ocorrencias.append(ocorrencia)
        ocorrencia += timedelta(days=7)

    return ocorrencias


def ocorrencias_ate(regra: RegraRecorrencia, ate: date) -> list[date]:
    """Todas as datas em que a regra deveria ter gerado um lançamento, até 'ate' (inclusive)."""
    if regra.frequencia == FrequenciaRecorrencia.MENSAL:
        return _ocorrencias_mensais(regra, ate)
    return _ocorrencias_semanais(regra, ate)

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/regras_recorrencia.py' << 'ARQUIVO_FIM'
"""
Regras de negócio das recorrências: CRUD da regra e geração automática
dos lançamentos já vencidos (ADR 0005 — só o passado é persistido; a
projeção de datas futuras é calculada sob demanda, na Etapa 5).
"""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda, Lancamento, RegraRecorrencia
from app.models.enums import FrequenciaRecorrencia, TipoLancamento
from app.repositories.regras_recorrencia import regras_recorrencia as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.ocorrencias import ocorrencias_ate

TAMANHO_MAXIMO_DESCRICAO = 255

LIMITES_DIA_REFERENCIA = {
    FrequenciaRecorrencia.MENSAL: (1, 28),
    FrequenciaRecorrencia.SEMANAL: (0, 6),
}


def _tipo(valor: str | None) -> TipoLancamento:
    try:
        return TipoLancamento(valor)
    except ValueError:
        raise ErroDeNegocio("Tipo inválido.") from None


def _frequencia(valor: str | None) -> FrequenciaRecorrencia:
    try:
        return FrequenciaRecorrencia(valor)
    except ValueError:
        raise ErroDeNegocio("Frequência inválida.") from None


def _valor_monetario(valor: str | None) -> Decimal:
    try:
        numero = Decimal(str(valor).replace(",", "."))
    except (InvalidOperation, AttributeError):
        raise ErroDeNegocio("Valor inválido.") from None
    if numero <= 0:
        raise ErroDeNegocio("O valor deve ser maior que zero.")
    return numero


def _data(valor: str | None, campo: str = "Data") -> date:
    try:
        return date.fromisoformat(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio(f"{campo} inválida.") from None


def _dia_referencia(valor: str | None, frequencia: FrequenciaRecorrencia) -> int:
    try:
        numero = int(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio("Dia de referência inválido.") from None
    minimo, maximo = LIMITES_DIA_REFERENCIA[frequencia]
    if not (minimo <= numero <= maximo):
        raise ErroDeNegocio(f"Para essa frequência, o dia de referência deve estar entre {minimo} e {maximo}.")
    return numero


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
            f"não pode ser usada numa recorrência de {tipo.value}."
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


class ServicoRecorrencias:
    def listar(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia:
        regra = repo.obter(db, usuario_id, regra_id)
        if regra is None:
            raise NaoEncontrado("Recorrência não encontrada.")
        return regra

    def criar(self, db: Session, usuario_id: int, **campos) -> RegraRecorrencia:
        dados = self._validar(db, usuario_id, **campos)
        return repo.adicionar(db, RegraRecorrencia(usuario_id=usuario_id, **dados))

    def atualizar(self, db: Session, usuario_id: int, regra_id: int, **campos) -> RegraRecorrencia:
        regra = self.obter(db, usuario_id, regra_id)
        dados = self._validar(db, usuario_id, **campos)
        for campo, valor in dados.items():
            setattr(regra, campo, valor)
        return repo.salvar(db, regra)

    def alternar_ativa(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia:
        regra = self.obter(db, usuario_id, regra_id)
        regra.ativa = not regra.ativa
        return repo.salvar(db, regra)

    def excluir(self, db: Session, usuario_id: int, regra_id: int) -> None:
        regra = self.obter(db, usuario_id, regra_id)
        # Os lançamentos já gerados continuam no histórico — só perdem o
        # vínculo com a regra (que deixou de existir), nunca são apagados.
        db.query(Lancamento).filter(Lancamento.regra_recorrencia_id == regra.id).update(
            {"regra_recorrencia_id": None}
        )
        repo.remover(db, regra)

    def _validar(
        self, db: Session, usuario_id: int, *,
        tipo: str, conta_id: int, categoria_id: int, valor: str,
        frequencia: str, dia_referencia: str, data_inicio: str,
        fonte_renda_id: int | None = None, data_fim: str | None = None, descricao: str | None = None,
    ) -> dict:
        tipo_validado = _tipo(tipo)
        frequencia_validada = _frequencia(frequencia)
        conta = _conta_do_usuario(db, usuario_id, conta_id)
        categoria = _categoria_do_usuario(db, usuario_id, categoria_id, tipo_validado)
        fonte = (
            _fonte_renda_do_usuario(db, usuario_id, fonte_renda_id)
            if tipo_validado == TipoLancamento.RECEITA
            else None
        )
        data_inicio_validada = _data(data_inicio, "Data de início")
        data_fim_validada = _data(data_fim, "Data de fim") if data_fim else None
        if data_fim_validada and data_fim_validada < data_inicio_validada:
            raise ErroDeNegocio("A data de fim não pode ser anterior à data de início.")

        return {
            "tipo": tipo_validado,
            "conta_id": conta.id,
            "categoria_id": categoria.id,
            "fonte_renda_id": fonte.id if fonte else None,
            "valor": _valor_monetario(valor),
            "frequencia": frequencia_validada,
            "dia_referencia": _dia_referencia(dia_referencia, frequencia_validada),
            "data_inicio": data_inicio_validada,
            "data_fim": data_fim_validada,
            "descricao": (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None,
        }


def gerar_lancamentos_pendentes(db: Session, usuario_id: int, ate: date | None = None) -> int:
    """
    Materializa, como Lancamento de verdade, toda ocorrência vencida das
    regras ativas do usuário que ainda não tenha sido gerada. Chamado
    automaticamente ao abrir a tela de lançamentos — sem exigir nenhuma
    ação manual nem um agendador externo.
    """
    ate = ate or date.today()
    total_criados = 0

    for regra in repo.listar_ativas(db, usuario_id):
        datas_pendentes = ocorrencias_ate(regra, ate)
        if not datas_pendentes:
            continue

        datas_ja_geradas = {
            linha[0]
            for linha in db.query(Lancamento.data).filter(Lancamento.regra_recorrencia_id == regra.id).all()
        }

        for data_ocorrencia in datas_pendentes:
            if data_ocorrencia in datas_ja_geradas:
                continue
            db.add(Lancamento(
                conta_id=regra.conta_id,
                categoria_id=regra.categoria_id,
                fonte_renda_id=regra.fonte_renda_id,
                regra_recorrencia_id=regra.id,
                tipo=regra.tipo,
                valor=regra.valor,
                data=data_ocorrencia,
                descricao=regra.descricao,
            ))
            total_criados += 1

    if total_criados:
        db.commit()
    return total_criados


servico_recorrencias = ServicoRecorrencias()

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/recorrencias.py' << 'ARQUIVO_FIM'
"""Rotas web de regras de recorrência."""

from datetime import date

from fastapi import APIRouter, Depends, Form, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario
from app.services.cadastros import servico_categorias, servico_contas, servico_fontes_renda
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.regras_recorrencia import servico_recorrencias
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/recorrencias")
templates = Jinja2Templates(directory="app/templates")


def _contexto(db: Session, usuario: Usuario, editando: object | None = None, erro: str | None = None) -> dict:
    return {
        "usuario": usuario,
        "regras": servico_recorrencias.listar(db, usuario.id),
        "contas": servico_contas.listar(db, usuario.id),
        "categorias": servico_categorias.listar(db, usuario.id),
        "fontes": servico_fontes_renda.listar(db, usuario.id),
        "hoje": date.today().isoformat(),
        "editando": editando,
        "erro": erro,
    }


def _renderizar(request: Request, db, usuario, **kwargs):
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/recorrencias.html" if is_htmx else "recorrencias.html"
    return templates.TemplateResponse(request, nome_template, _contexto(db, usuario, **kwargs))


def _campos_form(
    tipo, conta_id, categoria_id, valor, frequencia, dia_referencia, data_inicio, fonte_renda_id, data_fim, descricao
) -> dict:
    return {
        "tipo": tipo, "conta_id": conta_id, "categoria_id": categoria_id, "valor": valor,
        "frequencia": frequencia, "dia_referencia": dia_referencia, "data_inicio": data_inicio,
        "fonte_renda_id": fonte_renda_id or None, "data_fim": data_fim or None, "descricao": descricao,
    }


@router.get("")
def listar(request: Request, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    return _renderizar(request, db, usuario)


@router.get("/{regra_id}/editar")
def editar(request: Request, regra_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        regra = servico_recorrencias.obter(db, usuario.id, regra_id)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario, editando=regra)


@router.post("")
def criar(
    request: Request,
    tipo: str = Form(...), conta_id: int = Form(...), categoria_id: int = Form(...),
    valor: str = Form(...), frequencia: str = Form(...), dia_referencia: str = Form(...),
    data_inicio: str = Form(...), fonte_renda_id: int = Form(None), data_fim: str = Form(""),
    descricao: str = Form(""),
    db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado),
):
    dados = _campos_form(tipo, conta_id, categoria_id, valor, frequencia, dia_referencia, data_inicio, fonte_renda_id, data_fim, descricao)
    try:
        servico_recorrencias.criar(db, usuario.id, **dados)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.put("/{regra_id}")
def atualizar(
    request: Request, regra_id: int,
    tipo: str = Form(...), conta_id: int = Form(...), categoria_id: int = Form(...),
    valor: str = Form(...), frequencia: str = Form(...), dia_referencia: str = Form(...),
    data_inicio: str = Form(...), fonte_renda_id: int = Form(None), data_fim: str = Form(""),
    descricao: str = Form(""),
    db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado),
):
    dados = _campos_form(tipo, conta_id, categoria_id, valor, frequencia, dia_referencia, data_inicio, fonte_renda_id, data_fim, descricao)
    try:
        servico_recorrencias.atualizar(db, usuario.id, regra_id, **dados)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    except ErroDeNegocio as erro:
        try:
            regra = servico_recorrencias.obter(db, usuario.id, regra_id)
        except NaoEncontrado:
            regra = None
        return _renderizar(request, db, usuario, editando=regra, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.post("/{regra_id}/alternar")
def alternar(request: Request, regra_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_recorrencias.alternar_ativa(db, usuario.id, regra_id)
    except NaoEncontrado as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)


@router.delete("/{regra_id}")
def excluir(request: Request, regra_id: int, db: Session = Depends(get_db), usuario=Depends(exigir_usuario_logado)):
    try:
        servico_recorrencias.excluir(db, usuario.id, regra_id)
    except ErroDeNegocio as erro:
        return _renderizar(request, db, usuario, erro=str(erro))
    return _renderizar(request, db, usuario)

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/recorrencias.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}
{% block titulo %}Recorrências — Gestão Financeira{% endblock %}
{% block conteudo %}{% include "partials/recorrencias.html" %}{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/templates/partials'
cat > 'app/templates/partials/recorrencias.html' << 'ARQUIVO_FIM'
<div id="pagina">
<h1 class="text-2xl font-semibold mb-1">Recorrências</h1>
<p class="text-slate-400 text-sm mb-6">Lançamentos que se repetem automaticamente (ex: aluguel, salário fixo).</p>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">{{ erro }}</div>
{% endif %}

{% if not contas or not categorias %}
<div class="bg-amber-900/40 border border-amber-700 text-amber-200 text-sm rounded-md px-4 py-2 mb-4">
  Cadastre pelo menos uma <a href="/contas" class="underline">conta</a> e uma
  <a href="/categorias" class="underline">categoria</a> antes de criar uma recorrência.
</div>
{% endif %}

{% set alvo = "/recorrencias/" ~ editando.id if editando else "/recorrencias" %}
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

  <select name="fonte_renda_id" class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    <option value="">Fonte de renda (opcional, só receita)</option>
    {% for fonte in fontes %}
    <option value="{{ fonte.id }}" {% if editando and editando.fonte_renda_id == fonte.id %}selected{% endif %}>{{ fonte.nome }}</option>
    {% endfor %}
  </select>

  <div class="grid grid-cols-2 gap-3">
    <select name="frequencia" class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
      <option value="mensal" {% if not editando or editando.frequencia.value == "mensal" %}selected{% endif %}>Mensal</option>
      <option value="semanal" {% if editando and editando.frequencia.value == "semanal" %}selected{% endif %}>Semanal</option>
    </select>
    <input type="number" name="dia_referencia" placeholder="Dia (mês: 1-28, semana: 0=seg..6=dom)"
           value="{{ editando.dia_referencia if editando else '' }}" required
           class="rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
  </div>

  <div class="grid grid-cols-2 gap-3">
    <div>
      <label class="text-xs text-slate-400">Início</label>
      <input type="date" name="data_inicio" value="{{ editando.data_inicio.isoformat() if editando else hoje }}" required
             class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    </div>
    <div>
      <label class="text-xs text-slate-400">Fim (opcional)</label>
      <input type="date" name="data_fim" value="{{ editando.data_fim.isoformat() if editando and editando.data_fim else '' }}"
             class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">
    </div>
  </div>

  <input name="descricao" placeholder="Descrição (opcional)" maxlength="255"
         value="{{ editando.descricao or '' if editando else '' }}"
         class="w-full rounded-md bg-slate-800 border border-slate-700 px-3 py-2">

  <div class="flex gap-2">
    <button class="rounded-md bg-emerald-600 hover:bg-emerald-500 px-4 py-2 font-medium">
      {{ "Salvar" if editando else "Criar recorrência" }}
    </button>
    {% if editando %}
    <a hx-get="/recorrencias" hx-target="#pagina" hx-swap="outerHTML"
       class="text-slate-400 hover:text-white text-sm self-center cursor-pointer">Cancelar</a>
    {% endif %}
  </div>
</form>

<ul class="space-y-2">
  {% for r in regras %}
  <li class="bg-slate-900 border border-slate-800 rounded-md px-4 py-3 flex items-center justify-between {{ 'opacity-50' if not r.ativa }}">
    <div class="flex items-center gap-3">
      <span class="text-xs px-2 py-0.5 rounded-full {{ 'bg-rose-900 text-rose-300' if r.tipo.value == 'despesa' else 'bg-emerald-900 text-emerald-300' }}">
        {{ "Despesa" if r.tipo.value == "despesa" else "Receita" }}
      </span>
      <div>
        <div class="font-medium">{{ r.categoria.nome }} <span class="text-slate-400 font-normal">· {{ r.conta.nome }}</span></div>
        <div class="text-sm text-slate-400">
          {{ "Mensal, dia" if r.frequencia.value == "mensal" else "Semanal, " }} {{ r.dia_referencia }}
          · desde {{ r.data_inicio.strftime("%d/%m/%Y") }}
          {% if r.data_fim %}até {{ r.data_fim.strftime("%d/%m/%Y") }}{% endif %}
          {% if not r.ativa %}· <span class="text-amber-400">pausada</span>{% endif %}
        </div>
      </div>
    </div>
    <div class="flex items-center gap-4">
      <span class="tabular-nums">R$ {{ "%.2f"|format(r.valor) }}</span>
      <a hx-post="/recorrencias/{{ r.id }}/alternar" hx-target="#pagina" hx-swap="outerHTML"
         class="text-slate-400 hover:text-white text-sm cursor-pointer">{{ "pausar" if r.ativa else "reativar" }}</a>
      <a hx-get="/recorrencias/{{ r.id }}/editar" hx-target="#pagina" hx-swap="outerHTML"
         class="text-slate-400 hover:text-white text-sm cursor-pointer">editar</a>
      <a hx-delete="/recorrencias/{{ r.id }}" hx-target="#pagina" hx-swap="outerHTML"
         hx-confirm="Excluir esta recorrência? Os lançamentos já gerados continuam no histórico."
         class="text-red-400 hover:text-red-300 text-sm cursor-pointer">excluir</a>
    </div>
  </li>
  {% else %}
  <li class="text-slate-500 text-sm">Nenhuma recorrência cadastrada ainda.</li>
  {% endfor %}
</ul>
</div>

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_ocorrencias.py' << 'ARQUIVO_FIM'
"""
Testes unitários do cálculo de ocorrências — lógica pura de calendário,
sem tocar banco de dados.
"""

from datetime import date

from app.models.enums import FrequenciaRecorrencia, TipoLancamento
from app.models.regra_recorrencia import RegraRecorrencia
from app.services.ocorrencias import ocorrencias_ate


def _regra(**kwargs) -> RegraRecorrencia:
    base = dict(
        usuario_id=1, conta_id=1, categoria_id=1, tipo=TipoLancamento.DESPESA,
        valor=100, frequencia=FrequenciaRecorrencia.MENSAL, dia_referencia=5,
        data_inicio=date(2026, 1, 5), data_fim=None,
    )
    base.update(kwargs)
    return RegraRecorrencia(**base)


def test_mensal_gera_uma_ocorrencia_por_mes():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 4, 5))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5), date(2026, 4, 5)]


def test_mensal_nao_gera_antes_da_data_de_inicio():
    regra = _regra(data_inicio=date(2026, 3, 15), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 5, 1))
    # dia 5 de março já passou quando a regra começa dia 15 — primeira ocorrência é em abril
    assert datas == [date(2026, 4, 5)]


def test_mensal_respeita_data_fim():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5, data_fim=date(2026, 2, 28))
    datas = ocorrencias_ate(regra, ate=date(2026, 6, 1))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5)]


def test_mensal_nao_gera_alem_de_hoje():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 2, 20))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5)]


def test_mensal_com_dia_28_funciona_em_fevereiro():
    regra = _regra(data_inicio=date(2026, 1, 28), dia_referencia=28)
    datas = ocorrencias_ate(regra, ate=date(2026, 3, 1))
    assert datas == [date(2026, 1, 28), date(2026, 2, 28)]


def test_semanal_gera_no_dia_da_semana_correto():
    # 2026-01-05 é uma segunda-feira (weekday 0)
    regra = _regra(
        frequencia=FrequenciaRecorrencia.SEMANAL, dia_referencia=0,
        data_inicio=date(2026, 1, 7),  # quarta-feira
    )
    datas = ocorrencias_ate(regra, ate=date(2026, 1, 31))
    assert all(d.weekday() == 0 for d in datas)
    assert datas[0] == date(2026, 1, 12)  # primeira segunda a partir de 07/01


def test_semanal_gera_semana_a_semana():
    regra = _regra(frequencia=FrequenciaRecorrencia.SEMANAL, dia_referencia=4, data_inicio=date(2026, 1, 2))
    datas = ocorrencias_ate(regra, ate=date(2026, 1, 31))
    assert datas == [date(2026, 1, 2), date(2026, 1, 9), date(2026, 1, 16), date(2026, 1, 23), date(2026, 1, 30)]

ARQUIVO_FIM

mkdir -p 'tests/unit'
cat > 'tests/unit/test_geracao_recorrencia.py' << 'ARQUIVO_FIM'
"""Testes do CRUD de recorrências e da geração automática de lançamentos."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Lancamento, Usuario
from app.services.cadastros import servico_categorias, servico_contas
from app.services.erros import ErroDeNegocio
from app.services.regras_recorrencia import gerar_lancamentos_pendentes, servico_recorrencias


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
    categoria = servico_categorias.criar(db, usuario.id, "Aluguel", tipo="despesa")
    return {"conta": conta, "categoria": categoria}


def _criar_regra_aluguel(db, usuario_id, cenario, **override):
    campos = dict(
        tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["categoria"].id,
        valor="1200", frequencia="mensal", dia_referencia="5",
        data_inicio=date(2026, 1, 5).isoformat(),
    )
    campos.update(override)
    return servico_recorrencias.criar(db, usuario_id, **campos)


def test_categoria_de_tipo_errado_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(db, usuario.id, cenario, tipo="receita")


def test_dia_referencia_fora_do_intervalo_mensal_e_rejeitado(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(db, usuario.id, cenario, dia_referencia="31")


def test_data_fim_antes_do_inicio_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(
            db, usuario.id, cenario,
            data_inicio=date(2026, 3, 1).isoformat(), data_fim=date(2026, 1, 1).isoformat(),
        )


def test_gera_lancamentos_pendentes_ate_hoje(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    criados = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados == 4  # jan, fev, mar, abr

    lancamentos = db.query(Lancamento).order_by(Lancamento.data).all()
    assert [l.data for l in lancamentos] == [
        date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5), date(2026, 4, 5),
    ]
    assert all(l.valor == 1200 for l in lancamentos)
    assert all(l.regra_recorrencia_id is not None for l in lancamentos)


def test_gerar_duas_vezes_nao_duplica(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 3, 5))
    criados_na_segunda_vez = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 3, 5))

    assert criados_na_segunda_vez == 0
    assert db.query(Lancamento).count() == 3


def test_gerar_avancando_o_tempo_so_cria_o_que_falta(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 2, 5))
    assert db.query(Lancamento).count() == 2

    criados_depois = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados_depois == 2  # só março e abril, que ainda não existiam
    assert db.query(Lancamento).count() == 4


def test_regra_inativa_nao_gera_lancamentos(db, usuario, cenario):
    regra = _criar_regra_aluguel(db, usuario.id, cenario)
    servico_recorrencias.alternar_ativa(db, usuario.id, regra.id)  # desativa

    criados = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados == 0


def test_excluir_regra_preserva_lancamentos_ja_gerados(db, usuario, cenario):
    regra = _criar_regra_aluguel(db, usuario.id, cenario)
    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 2, 5))

    servico_recorrencias.excluir(db, usuario.id, regra.id)

    lancamentos = db.query(Lancamento).all()
    assert len(lancamentos) == 2
    assert all(l.regra_recorrencia_id is None for l in lancamentos)

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_recorrencias_web.py' << 'ARQUIVO_FIM'
"""Teste de integração: criar uma recorrência e ver os lançamentos gerados automaticamente."""

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


def test_recorrencia_gera_lancamentos_automaticos_ao_abrir_a_tela(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})

    resposta_criacao = cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "1200", "frequencia": "mensal", "dia_referencia": "5",
        "data_inicio": "2026-01-05",
    })
    assert "Aluguel" in resposta_criacao.text
    assert "Mensal" in resposta_criacao.text

    # A geração automática dispara ao abrir /lancamentos, sem nenhuma ação manual.
    resposta_lancamentos = cliente_logado.get("/lancamentos")
    assert "Aluguel" in resposta_lancamentos.text
    assert "(automático)" in resposta_lancamentos.text
    assert "-R$ 1200.00" in resposta_lancamentos.text

    # Abrir de novo não deve duplicar.
    primeira_contagem = resposta_lancamentos.text.count("Aluguel")
    resposta_de_novo = cliente_logado.get("/lancamentos")
    assert resposta_de_novo.text.count("Aluguel") == primeira_contagem


def test_pausar_recorrencia_impede_novos_lancamentos(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})
    cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "1200", "frequencia": "mensal", "dia_referencia": "5",
        "data_inicio": "2026-01-05",
    })

    resposta = cliente_logado.post("/recorrencias/1/alternar")
    assert "pausada" in resposta.text

    cliente_logado.get("/lancamentos")  # tentaria gerar, mas a regra está pausada
    lancamentos = cliente_logado.get("/lancamentos")
    assert "Nenhum lançamento ainda." in lancamentos.text

ARQUIVO_FIM

echo "Arquivos prontos. Fazendo commit..."
git add .
git commit -m "feat: recorrencias com geracao automatica de lancamentos (Etapa 3)"
rm -- "$0"
echo "Commit feito. Rode: git push"
