"""
Repositório de Lancamento.

Diferente de Conta/Categoria/FonteDeRenda, Lancamento não tem usuario_id
direto — o isolamento por usuário é garantido via join com Conta.
"""

from sqlalchemy.orm import Session

from app.models import Conta, Lancamento


class RepositorioLancamentos:
    def listar(self, db: Session, usuario_id: int, limite: int = 200) -> list[Lancamento]:
        return (
            db.query(Lancamento)
            .join(Conta, Lancamento.conta_id == Conta.id)
            .filter(Conta.usuario_id == usuario_id)
            .order_by(Lancamento.data.desc(), Lancamento.id.desc())
            .limit(limite)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, lancamento_id: int) -> Lancamento | None:
        return (
            db.query(Lancamento)
            .join(Conta, Lancamento.conta_id == Conta.id)
            .filter(Lancamento.id == lancamento_id, Conta.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, lancamento: Lancamento) -> Lancamento:
        db.add(lancamento)
        db.commit()
        db.refresh(lancamento)
        return lancamento

    def salvar(self, db: Session, lancamento: Lancamento) -> Lancamento:
        db.commit()
        db.refresh(lancamento)
        return lancamento

    def remover(self, db: Session, lancamento: Lancamento) -> None:
        db.delete(lancamento)
        db.commit()


lancamentos = RepositorioLancamentos()

