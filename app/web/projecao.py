"""Rota web de projeção de saldo futuro."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Request
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.services import dashboard_service, projecao_service
from app.services.graficos import grafico_projecao
from app.web.deps import exigir_usuario_logado

router = APIRouter(prefix="/projecao")
templates = Jinja2Templates(directory="app/templates")

HORIZONTE_PADRAO_DIAS = 90
HISTORICO_PADRAO_DIAS = 30


@router.get("")
def exibir(
    request: Request,
    ate: str | None = None,
    db: Session = Depends(get_db),
    usuario=Depends(exigir_usuario_logado),
):
    hoje = date.today()
    data_ate = date.fromisoformat(ate) if ate else hoje + timedelta(days=HORIZONTE_PADRAO_DIAS)
    if data_ate <= hoje:
        data_ate = hoje + timedelta(days=1)

    inicio_historico = hoje - timedelta(days=HISTORICO_PADRAO_DIAS)
    saldo_inicial_historico = dashboard_service.saldo_geral_antes_de(db, usuario.id, inicio_historico)
    df_historico = dashboard_service.evolucao_saldo(db, usuario.id, inicio_historico, hoje, saldo_inicial_historico)

    df_projecao = projecao_service.projecao_futura(db, usuario.id, data_ate, hoje)

    saldo_atual = projecao_service.saldo_atual(db, usuario.id, hoje)
    saldo_final_projetado = df_projecao["saldo"].iloc[-1] if not df_projecao.empty else float(saldo_atual)

    contexto = {
        "usuario": usuario,
        "ate": data_ate.isoformat(),
        "saldo_atual": saldo_atual,
        "saldo_projetado": saldo_final_projetado,
        "data_projecao": data_ate,
        "grafico": grafico_projecao(df_historico, df_projecao),
    }
    is_htmx = request.headers.get("HX-Request") == "true"
    nome_template = "partials/projecao.html" if is_htmx else "projecao.html"
    return templates.TemplateResponse(request, nome_template, contexto)

