"""Repositórios de contas, categorias e fontes de renda."""

from typing import Any

from sqlalchemy.orm import Session

from app.models import (
    Categoria,
    Conta,
    FonteDeRenda,
    Lancamento,
    RegraRecorrencia,
    TransferenciaEntreContas,
)
from app.repositories.base import RepositorioDoUsuario


def _existe(db: Session, model: Any, **filtros: Any) -> bool:
    return db.query(model.id).filter_by(**filtros).first() is not None


class RepositorioContas(RepositorioDoUsuario[Conta]):
    def em_uso(self, db: Session, conta_id: int) -> bool:
        return (
            _existe(db, Lancamento, conta_id=conta_id)
            or _existe(db, RegraRecorrencia, conta_id=conta_id)
            or _existe(db, TransferenciaEntreContas, conta_origem_id=conta_id)
            or _existe(db, TransferenciaEntreContas, conta_destino_id=conta_id)
        )


class RepositorioCategorias(RepositorioDoUsuario[Categoria]):
    def em_uso(self, db: Session, categoria_id: int) -> bool:
        return _existe(db, Lancamento, categoria_id=categoria_id) or _existe(
            db, RegraRecorrencia, categoria_id=categoria_id
        )


class RepositorioFontesRenda(RepositorioDoUsuario[FonteDeRenda]):
    def em_uso(self, db: Session, fonte_id: int) -> bool:
        return _existe(db, Lancamento, fonte_renda_id=fonte_id) or _existe(
            db, RegraRecorrencia, fonte_renda_id=fonte_id
        )


contas = RepositorioContas(Conta)
categorias = RepositorioCategorias(Categoria)
fontes_renda = RepositorioFontesRenda(FonteDeRenda)

