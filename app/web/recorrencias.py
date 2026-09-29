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

