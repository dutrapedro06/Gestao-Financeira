"""Regras de negócio das transferências entre contas."""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Conta, TransferenciaEntreContas
from app.repositories.transferencias import transferencias as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_DESCRICAO = 255


def _valor_monetario(valor: str | None) -> Decimal:
    try:
        numero = Decimal(str(valor).replace(",", "."))
    except (InvalidOperation, AttributeError):
        raise ErroDeNegocio("Valor inválido.") from None
    if numero <= 0:
        raise ErroDeNegocio("O valor deve ser maior que zero.")
    return numero


def _data(valor: str | None) -> date:
    try:
        return date.fromisoformat(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio("Data inválida.") from None


def _conta_do_usuario(db: Session, usuario_id: int, conta_id: int) -> Conta:
    conta = db.query(Conta).filter(Conta.id == conta_id, Conta.usuario_id == usuario_id).first()
    if conta is None:
        raise ErroDeNegocio("Conta inválida.")
    return conta


class ServicoTransferencias:
    def listar(self, db: Session, usuario_id: int) -> list[TransferenciaEntreContas]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, transferencia_id: int) -> TransferenciaEntreContas:
        transferencia = repo.obter(db, usuario_id, transferencia_id)
        if transferencia is None:
            raise NaoEncontrado("Transferência não encontrada.")
        return transferencia

    def criar(
        self, db: Session, usuario_id: int, *,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None = None,
    ) -> TransferenciaEntreContas:
        dados = self._validar(db, usuario_id, conta_origem_id, conta_destino_id, valor, data, descricao)
        return repo.adicionar(db, TransferenciaEntreContas(**dados))

    def atualizar(
        self, db: Session, usuario_id: int, transferencia_id: int, *,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None = None,
    ) -> TransferenciaEntreContas:
        transferencia = self.obter(db, usuario_id, transferencia_id)
        dados = self._validar(db, usuario_id, conta_origem_id, conta_destino_id, valor, data, descricao)
        for campo, valor_campo in dados.items():
            setattr(transferencia, campo, valor_campo)
        return repo.salvar(db, transferencia)

    def excluir(self, db: Session, usuario_id: int, transferencia_id: int) -> None:
        transferencia = self.obter(db, usuario_id, transferencia_id)
        repo.remover(db, transferencia)

    def _validar(
        self, db: Session, usuario_id: int,
        conta_origem_id: int, conta_destino_id: int, valor: str, data: str, descricao: str | None,
    ) -> dict:
        if conta_origem_id == conta_destino_id:
            raise ErroDeNegocio("A conta de origem e destino não podem ser a mesma.")

        origem = _conta_do_usuario(db, usuario_id, conta_origem_id)
        destino = _conta_do_usuario(db, usuario_id, conta_destino_id)
        descricao = (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None

        return {
            "conta_origem_id": origem.id,
            "conta_destino_id": destino.id,
            "valor": _valor_monetario(valor),
            "data": _data(data),
            "descricao": descricao,
        }


servico_transferencias = ServicoTransferencias()

