"""
Enums compartilhados entre models — ficam em um módulo próprio para
evitar import circular entre, por exemplo, categoria.py e lancamento.py.
"""

import enum


class TipoLancamento(str, enum.Enum):
    RECEITA = "receita"
    DESPESA = "despesa"


class FrequenciaRecorrencia(str, enum.Enum):
    MENSAL = "mensal"
    SEMANAL = "semanal"

