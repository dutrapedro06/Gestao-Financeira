"""
Repositório de TransferenciaEntreContas.

Assim como Lancamento, não tem usuario_id direto — o isolamento é via
join com Conta (a conta de origem é suficiente, já que origem e destino
sempre pertencem ao mesmo usuário nesta modelagem).
"""

from sqlalchemy.orm import Session

from app.models import Conta, TransferenciaEntreContas


class RepositorioTransferencias:
    def listar(self, db: Session, usuario_id: int, limite: int = 200) -> list[TransferenciaEntreContas]:
        return (
            db.query(TransferenciaEntreContas)
            .join(Conta, TransferenciaEntreContas.conta_origem_id == Conta.id)
            .filter(Conta.usuario_id == usuario_id)
            .order_by(TransferenciaEntreContas.data.desc(), TransferenciaEntreContas.id.desc())
            .limit(limite)
            .all()
        )

    def obter(self, db: Session, usuario_id: int, transferencia_id: int) -> TransferenciaEntreContas | None:
        return (
            db.query(TransferenciaEntreContas)
            .join(Conta, TransferenciaEntreContas.conta_origem_id == Conta.id)
            .filter(TransferenciaEntreContas.id == transferencia_id, Conta.usuario_id == usuario_id)
            .first()
        )

    def adicionar(self, db: Session, transferencia: TransferenciaEntreContas) -> TransferenciaEntreContas:
        db.add(transferencia)
        db.commit()
        db.refresh(transferencia)
        return transferencia

    def salvar(self, db: Session, transferencia: TransferenciaEntreContas) -> TransferenciaEntreContas:
        db.commit()
        db.refresh(transferencia)
        return transferencia

    def remover(self, db: Session, transferencia: TransferenciaEntreContas) -> None:
        db.delete(transferencia)
        db.commit()


transferencias = RepositorioTransferencias()

