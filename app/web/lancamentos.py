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

