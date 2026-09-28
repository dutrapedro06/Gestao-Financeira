"""Acesso a dados genérico para entidades que pertencem a um usuário."""

from typing import Any, Generic, TypeVar

from sqlalchemy import func
from sqlalchemy.orm import Session

T = TypeVar("T")


class RepositorioDoUsuario(Generic[T]):
    """Toda consulta é filtrada por usuario_id, garantindo o isolamento entre usuários."""

    def __init__(self, model: type[T]):
        self.model: Any = model

    def listar(self, db: Session, usuario_id: int) -> list[T]:
        return (
            db.query(self.model)
            .filter(self.model.usuario_id == usuario_id)
            .order_by(self.model.nome)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, item_id: int) -> T | None:
        return (
            db.query(self.model)
            .filter(self.model.id == item_id, self.model.usuario_id == usuario_id)
            .first()
        )

    def obter_por_nome(self, db: Session, usuario_id: int, nome: str) -> T | None:
        return (
            db.query(self.model)
            .filter(
                self.model.usuario_id == usuario_id,
                func.lower(self.model.nome) == nome.lower(),
            )
            .first()
        )

    def adicionar(self, db: Session, item: T) -> T:
        db.add(item)
        db.commit()
        db.refresh(item)
        return item

    def salvar(self, db: Session, item: T) -> T:
        db.commit()
        db.refresh(item)
        return item

    def remover(self, db: Session, item: T) -> None:
        db.delete(item)
        db.commit()

