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

