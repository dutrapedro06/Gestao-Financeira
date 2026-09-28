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

