"""
Conta: carteira/conta do usuário (ex: conta corrente, vale-refeição,
investimento).

O saldo NUNCA é armazenado como coluna fixa — ele é sempre calculado a
partir do histórico de Lancamento e TransferenciaEntreContas associados a
esta conta (ver ADR 0004). Isso evita que o saldo exibido fique
dessincronizado do histórico real de movimentações. O cálculo em si fica
em app/services, não aqui no model.
"""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Conta(Base):
    __tablename__ = "contas"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(120), nullable=False)

    # Preparado para multi-moeda no futuro (ADR: só BRL por enquanto),
    # sem exigir migração de schema quando isso for necessário.
    moeda: Mapped[str] = mapped_column(String(3), nullable=False, default="BRL", server_default="BRL")

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    usuario: Mapped["Usuario"] = relationship(back_populates="contas")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="conta", cascade="all, delete-orphan")
    transferencias_enviadas: Mapped[list["TransferenciaEntreContas"]] = relationship(
        back_populates="conta_origem",
        foreign_keys="TransferenciaEntreContas.conta_origem_id",
    )
    transferencias_recebidas: Mapped[list["TransferenciaEntreContas"]] = relationship(
        back_populates="conta_destino",
        foreign_keys="TransferenciaEntreContas.conta_destino_id",
    )
