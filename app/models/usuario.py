"""
Usuario: cada usuário tem seus dados totalmente isolados (contas,
categorias, lançamentos, etc. sempre referenciam um usuario_id).

Como definido, não há cadastro público ainda (Etapa 7) — o(s) primeiro(s)
usuário(s) são criados via script (scripts/criar_usuario.py).
"""

from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[int] = mapped_column(primary_key=True)
    nome: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    senha_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    contas: Mapped[list["Conta"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    categorias: Mapped[list["Categoria"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    fontes_renda: Mapped[list["FonteDeRenda"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    regras_recorrencia: Mapped[list["RegraRecorrencia"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )

