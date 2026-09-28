"""
RegraRecorrencia: template de um lançamento que se repete (ex: aluguel
todo dia 5). Usada tanto para lançamento automático quanto para
alimentar as projeções de saldo futuro (ADR 0005) — o service de projeção
usa estes dados para calcular lançamentos futuros "sob demanda", sem
precisar persistir todos eles com antecedência.
"""

from datetime import date

from sqlalchemy import Date, Enum, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import FrequenciaRecorrencia, TipoLancamento


class RegraRecorrencia(Base):
    __tablename__ = "regras_recorrencia"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    conta_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False)
    categoria_id: Mapped[int] = mapped_column(ForeignKey("categorias.id"), nullable=False)
    fonte_renda_id: Mapped[int | None] = mapped_column(ForeignKey("fontes_renda.id"), nullable=True)

    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)
    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    frequencia: Mapped[FrequenciaRecorrencia] = mapped_column(Enum(FrequenciaRecorrencia), nullable=False)
    # Para frequência mensal: dia do mês (1-28, evitando ambiguidade em
    # meses curtos). Para semanal: dia da semana (0=segunda ... 6=domingo).
    dia_referencia: Mapped[int] = mapped_column(nullable=False)

    data_inicio: Mapped[date] = mapped_column(Date, nullable=False)
    data_fim: Mapped[date | None] = mapped_column(Date, nullable=True)
    ativa: Mapped[bool] = mapped_column(default=True, server_default="true")

    usuario: Mapped["Usuario"] = relationship(back_populates="regras_recorrencia")
    lancamentos_gerados: Mapped[list["Lancamento"]] = relationship(back_populates="regra_recorrencia")

