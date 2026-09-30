"""Rota web do dashboard."""

from datetime import date

from fastapi import APIRouter, Depends, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.services import dashboard_service as svc
from app.services.cadastros import servico_categorias, servico_fontes_renda
from app.services.graficos import grafico_evolucao_saldo, grafico_gastos_por_categoria
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/dashboard")
templates = Jinja2Templates(directory="app/templates")


@router.get("")
def exibir(
    request: Request,
    data_inicio: str | None = None,
    data_fim: str | None = None,
    categoria_id: int | None = None,
    fonte_id: int | None = None,
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    hoje = date.today()
    inicio = date.fromisoformat(data_inicio) if data_inicio else hoje.replace(day=1)
    fim = date.fromisoformat(data_fim) if data_fim else hoje
    if fim < inicio:
        inicio, fim = fim, inicio

    resumo = svc.resumo_periodo(db, usuario.id, inicio, fim, categoria_id, fonte_id)
    saldo_inicial = svc.saldo_geral_antes_de(db, usuario.id, inicio)
    df_evolucao = svc.evolucao_saldo(db, usuario.id, inicio, fim, saldo_inicial)

    contexto = {
        "usuario": usuario,
        "data_inicio": inicio.isoformat(),
        "data_fim": fim.isoformat(),
        "categoria_id": categoria_id,
        "fonte_id": fonte_id,
        "categorias": servico_categorias.listar(db, usuario.id),
        "fontes": servico_fontes_renda.listar(db, usuario.id),
        "total_receitas": resumo["total_receitas"],
        "total_despesas": resumo["total_despesas"],
        "saldo_periodo": resumo["saldo_periodo"],
        "lancamentos": sorted(resumo["lancamentos"], key=lambda l: l.data, reverse=True),
        "grafico_categorias": grafico_gastos_por_categoria(svc.gastos_por_categoria(resumo["dataframe"])),
        "grafico_saldo": grafico_evolucao_saldo(df_evolucao),
    }
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/dashboard.html" if is_htmx else "dashboard.html"
    return templates.TemplateResponse(request, nome_template, contexto)

