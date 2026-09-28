"""Cálculo de saldo. O saldo nunca é armazenado: sempre derivado do histórico."""

from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models import Lancamento, TransferenciaEntreContas
from app.models.enums import TipoLancamento


def _soma(db: Session, coluna, *filtros) -> Decimal:
    total = db.query(func.coalesce(func.sum(coluna), 0)).filter(*filtros).scalar()
    return Decimal(str(total))


def saldo_conta(db: Session, conta_id: int) -> Decimal:
    receitas = _soma(
        db, Lancamento.valor, Lancamento.conta_id == conta_id, Lancamento.tipo == TipoLancamento.RECEITA
    )
    despesas = _soma(
        db, Lancamento.valor, Lancamento.conta_id == conta_id, Lancamento.tipo == TipoLancamento.DESPESA
    )
    recebido = _soma(
        db, TransferenciaEntreContas.valor, TransferenciaEntreContas.conta_destino_id == conta_id
    )
    enviado = _soma(
        db, TransferenciaEntreContas.valor, TransferenciaEntreContas.conta_origem_id == conta_id
    )
    return receitas - despesas + recebido - enviado


def saldos_das_contas(db: Session, contas: list) -> dict[int, Decimal]:
    return {conta.id: saldo_conta(db, conta.id) for conta in contas}


def saldo_geral(saldos: dict[int, Decimal]) -> Decimal:
    return sum(saldos.values(), Decimal("0"))

