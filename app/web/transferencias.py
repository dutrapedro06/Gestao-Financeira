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

