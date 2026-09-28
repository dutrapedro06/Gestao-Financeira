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

