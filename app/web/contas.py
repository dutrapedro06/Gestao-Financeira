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

