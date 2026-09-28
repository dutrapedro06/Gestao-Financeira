"""
Lancamento: a entidade central — cobre tanto receita quanto despesa.

Note que "conta_id" é onde o seu exemplo de uso ganha vida: ao registrar
uma despesa, você escolhe de qual conta ela sai (ex: Vale-refeição em vez
de Conta Corrente), sem precisar de nenhuma lógica especial — é só um
lançamento vinculado àquela conta.
"""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TipoLancamento


class Lancamento(Base):
    __tablename__ = "lancamentos"

    id: Mapped[int] = mapped_column(primary_key=True)
    conta_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)
    categoria_id: Mapped[int] = mapped_column(ForeignKey("categorias.id"), nullable=False, index=True)
    fonte_renda_id: Mapped[int | None] = mapped_column(ForeignKey("fontes_renda.id"), nullable=True)
    regra_recorrencia_id: Mapped[int | None] = mapped_column(ForeignKey("regras_recorrencia.id"), nullable=True)

    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)
    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    data: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    conta: Mapped["Conta"] = relationship(back_populates="lancamentos")
    categoria: Mapped["Categoria"] = relationship(back_populates="lancamentos")
    fonte_renda: Mapped["FonteDeRenda"] = relationship(back_populates="lancamentos")
    regra_recorrencia: Mapped["RegraRecorrencia"] = relationship(back_populates="lancamentos_gerados")

