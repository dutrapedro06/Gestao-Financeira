"""
Categoria: classificação de receitas e despesas (ex: "Mercado",
"Transporte", "Salário"). Pertence a um usuário — cada um mantém suas
próprias categorias.
"""

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TipoLancamento


class Categoria(Base):
    __tablename__ = "categorias"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(80), nullable=False)
    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)

    usuario: Mapped["Usuario"] = relationship(back_populates="categorias")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="categoria")

