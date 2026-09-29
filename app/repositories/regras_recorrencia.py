"""Repositório de RegraRecorrencia."""

from sqlalchemy.orm import Session

from app.models import RegraRecorrencia


class RepositorioRegrasRecorrencia:
    def listar(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.usuario_id == usuario_id)
            .order_by(RegraRecorrencia.ativa.desc(), RegraRecorrencia.data_inicio.desc())
            .all()
        )

    def listar_ativas(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.usuario_id == usuario_id, RegraRecorrencia.ativa.is_(True))
            .all()
        )

    def obter(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia | None:
        return (
            db.query(RegraRecorrencia)
            .filter(RegraRecorrencia.id == regra_id, RegraRecorrencia.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, regra: RegraRecorrencia) -> RegraRecorrencia:
        db.add(regra)
        db.commit()
        db.refresh(regra)
        return regra

    def salvar(self, db: Session, regra: RegraRecorrencia) -> RegraRecorrencia:
        db.commit()
        db.refresh(regra)
        return regra

    def remover(self, db: Session, regra: RegraRecorrencia) -> None:
        db.delete(regra)
        db.commit()


regras_recorrencia = RepositorioRegrasRecorrencia()

