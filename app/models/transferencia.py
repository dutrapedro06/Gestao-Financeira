"""
TransferenciaEntreContas: movimentação entre duas contas do MESMO
usuário (ex: separar parte do salário para uma conta de investimento).

Deliberadamente uma entidade separada de Lancamento (ver ADR 0004): ela
afeta o saldo das duas contas envolvidas, mas nunca aparece nos
relatórios de receita/despesa por categoria — não é um gasto, é dinheiro
que continua seu, só mudou de lugar.
"""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class TransferenciaEntreContas(Base):
    __tablename__ = "transferencias_entre_contas"

    id: Mapped[int] = mapped_column(primary_key=True)
    conta_origem_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)
    conta_destino_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)

    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    data: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    conta_origem: Mapped["Conta"] = relationship(
        back_populates="transferencias_enviadas", foreign_keys=[conta_origem_id]
    )
    conta_destino: Mapped["Conta"] = relationship(
        back_populates="transferencias_recebidas", foreign_keys=[conta_destino_id]
    )

