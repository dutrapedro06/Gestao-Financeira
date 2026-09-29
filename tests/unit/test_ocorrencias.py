"""
Testes unitários do cálculo de ocorrências — lógica pura de calendário,
sem tocar banco de dados.
"""

from datetime import date

from app.models.enums import FrequenciaRecorrencia, TipoLancamento
from app.models.regra_recorrencia import RegraRecorrencia
from app.services.ocorrencias import ocorrencias_ate


def _regra(**kwargs) -> RegraRecorrencia:
    base = dict(
        usuario_id=1, conta_id=1, categoria_id=1, tipo=TipoLancamento.DESPESA,
        valor=100, frequencia=FrequenciaRecorrencia.MENSAL, dia_referencia=5,
        data_inicio=date(2026, 1, 5), data_fim=None,
    )
    base.update(kwargs)
    return RegraRecorrencia(**base)


def test_mensal_gera_uma_ocorrencia_por_mes():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 4, 5))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5), date(2026, 4, 5)]


def test_mensal_nao_gera_antes_da_data_de_inicio():
    regra = _regra(data_inicio=date(2026, 3, 15), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 5, 1))
    # dia 5 de março já passou quando a regra começa dia 15 — primeira ocorrência é em abril
    assert datas == [date(2026, 4, 5)]


def test_mensal_respeita_data_fim():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5, data_fim=date(2026, 2, 28))
    datas = ocorrencias_ate(regra, ate=date(2026, 6, 1))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5)]


def test_mensal_nao_gera_alem_de_hoje():
    regra = _regra(data_inicio=date(2026, 1, 5), dia_referencia=5)
    datas = ocorrencias_ate(regra, ate=date(2026, 2, 20))
    assert datas == [date(2026, 1, 5), date(2026, 2, 5)]


def test_mensal_com_dia_28_funciona_em_fevereiro():
    regra = _regra(data_inicio=date(2026, 1, 28), dia_referencia=28)
    datas = ocorrencias_ate(regra, ate=date(2026, 3, 1))
    assert datas == [date(2026, 1, 28), date(2026, 2, 28)]


def test_semanal_gera_no_dia_da_semana_correto():
    # 2026-01-05 é uma segunda-feira (weekday 0)
    regra = _regra(
        frequencia=FrequenciaRecorrencia.SEMANAL, dia_referencia=0,
        data_inicio=date(2026, 1, 7),  # quarta-feira
    )
    datas = ocorrencias_ate(regra, ate=date(2026, 1, 31))
    assert all(d.weekday() == 0 for d in datas)
    assert datas[0] == date(2026, 1, 12)  # primeira segunda a partir de 07/01


def test_semanal_gera_semana_a_semana():
    regra = _regra(frequencia=FrequenciaRecorrencia.SEMANAL, dia_referencia=4, data_inicio=date(2026, 1, 2))
    datas = ocorrencias_ate(regra, ate=date(2026, 1, 31))
    assert datas == [date(2026, 1, 2), date(2026, 1, 9), date(2026, 1, 16), date(2026, 1, 23), date(2026, 1, 30)]

