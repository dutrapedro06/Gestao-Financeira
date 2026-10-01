"""
Projeção de saldo futuro (ADR 0005).

saldo_projetado(data_futura) = saldo_atual + lançamentos futuros já
conhecidos (derivados das RegraRecorrencia ativas), calculado sob
demanda — nenhum lançamento futuro é persistido no banco com
antecedência, só os já realizados.
"""

from datetime import date, timedelta
from decimal import Decimal

import pandas as pd

from app.models.enums import TipoLancamento
from app.repositories.regras_recorrencia import regras_recorrencia as repo
from app.services.dashboard_service import saldo_geral_antes_de
from app.services.ocorrencias import ocorrencias_ate


def saldo_atual(db, usuario_id: int, referencia: date | None = None) -> Decimal:
    """Saldo geral real, incluindo tudo até 'referencia' (hoje, por padrão)."""
    referencia = referencia or date.today()
    return saldo_geral_antes_de(db, usuario_id, referencia + timedelta(days=1))


def projecao_futura(db, usuario_id: int, ate: date, hoje: date | None = None) -> pd.DataFrame:
    """
    Saldo geral projetado dia a dia, de hoje até 'ate' (inclusive).

    Só considera ocorrências estritamente futuras (data > hoje) das
    regras ativas — o que já aconteceu está refletido no saldo_atual.
    """
    hoje = hoje or date.today()
    saldo_base = float(saldo_atual(db, usuario_id, hoje))

    variacao_por_dia: dict[date, float] = {}
    for regra in repo.listar_ativas(db, usuario_id):
        sinal = 1 if regra.tipo == TipoLancamento.RECEITA else -1
        for ocorrencia in ocorrencias_ate(regra, ate):
            if ocorrencia <= hoje:
                continue
            variacao_por_dia[ocorrencia] = variacao_por_dia.get(ocorrencia, 0.0) + sinal * float(regra.valor)

    dias = pd.date_range(hoje, ate, freq="D")
    saldo = saldo_base
    linhas = []
    for dia in dias:
        data_do_dia = dia.date()
        if data_do_dia > hoje:
            saldo += variacao_por_dia.get(data_do_dia, 0.0)
        linhas.append({"data": dia, "saldo": saldo})

    return pd.DataFrame(linhas)

