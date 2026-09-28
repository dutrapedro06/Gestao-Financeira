"""
FonteDeRenda: origem das receitas (ex: "Salário CLT", "Freelance").
Usada para a visão por fonte no dashboard. Só faz sentido em lançamentos
de receita — é opcional em Lancamento.
"""

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class FonteDeRenda(Base):
    __tablename__ = "fontes_renda"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(80), nullable=False)

    usuario: Mapped["Usuario"] = relationship(back_populates="fontes_renda")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="fonte_renda")

