"""
Importar todos os models aqui é o que permite ao Alembic "enxergar"
todas as tabelas na hora de gerar uma migração automática
(`alembic revision --autogenerate`). Sem isso, o Base.metadata ficaria
incompleto e a migração sairia vazia ou incompleta.
"""

from app.models.categoria import Categoria
from app.models.conta import Conta
from app.models.fonte_renda import FonteDeRenda
from app.models.lancamento import Lancamento
from app.models.regra_recorrencia import RegraRecorrencia
from app.models.transferencia import TransferenciaEntreContas
from app.models.usuario import Usuario

__all__ = [
    "Categoria",
    "Conta",
    "FonteDeRenda",
    "Lancamento",
    "RegraRecorrencia",
    "TransferenciaEntreContas",
    "Usuario",
]

