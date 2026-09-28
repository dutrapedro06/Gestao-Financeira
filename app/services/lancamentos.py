"""Regras de negócio dos lançamentos (receitas e despesas)."""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda, Lancamento
from app.models.enums import TipoLancamento
from app.repositories.lancamentos import lancamentos as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_DESCRICAO = 255


def _tipo(valor: str | None) -> TipoLancamento:
    try:
        return TipoLancamento(valor)
    except ValueError:
        raise ErroDeNegocio("Tipo inválido.") from None


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


def _categoria_do_usuario(db: Session, usuario_id: int, categoria_id: int, tipo: TipoLancamento) -> Categoria:
    categoria = (
        db.query(Categoria).filter(Categoria.id == categoria_id, Categoria.usuario_id == usuario_id).first()
    )
    if categoria is None:
        raise ErroDeNegocio("Categoria inválida.")
    if categoria.tipo != tipo:
        raise ErroDeNegocio(
            f"A categoria '{categoria.nome}' é de {categoria.tipo.value}, "
            f"não pode ser usada num lançamento de {tipo.value}."
        )
    return categoria


def _fonte_renda_do_usuario(db: Session, usuario_id: int, fonte_renda_id: int | None) -> FonteDeRenda | None:
    if not fonte_renda_id:
        return None
    fonte = (
        db.query(FonteDeRenda)
        .filter(FonteDeRenda.id == fonte_renda_id, FonteDeRenda.usuario_id == usuario_id)
        .first()
    )
    if fonte is None:
        raise ErroDeNegocio("Fonte de renda inválida.")
    return fonte


class ServicoLancamentos:
    def listar(self, db: Session, usuario_id: int) -> list[Lancamento]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, lancamento_id: int) -> Lancamento:
        lancamento = repo.obter(db, usuario_id, lancamento_id)
        if lancamento is None:
            raise NaoEncontrado("Lançamento não encontrado.")
        return lancamento

    def criar(
        self,
        db: Session,
        usuario_id: int,
        *,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None = None,
        descricao: str | None = None,
    ) -> Lancamento:
        lancamento = Lancamento(
            **self._validar(db, usuario_id, tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
        )
        return repo.adicionar(db, lancamento)

    def atualizar(
        self,
        db: Session,
        usuario_id: int,
        lancamento_id: int,
        *,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None = None,
        descricao: str | None = None,
    ) -> Lancamento:
        lancamento = self.obter(db, usuario_id, lancamento_id)
        dados = self._validar(db, usuario_id, tipo, conta_id, categoria_id, valor, data, fonte_renda_id, descricao)
        for campo, valor_campo in dados.items():
            setattr(lancamento, campo, valor_campo)
        return repo.salvar(db, lancamento)

    def excluir(self, db: Session, usuario_id: int, lancamento_id: int) -> None:
        lancamento = self.obter(db, usuario_id, lancamento_id)
        repo.remover(db, lancamento)

    def _validar(
        self,
        db: Session,
        usuario_id: int,
        tipo: str,
        conta_id: int,
        categoria_id: int,
        valor: str,
        data: str,
        fonte_renda_id: int | None,
        descricao: str | None,
    ) -> dict:
        tipo_validado = _tipo(tipo)
        conta = _conta_do_usuario(db, usuario_id, conta_id)
        categoria = _categoria_do_usuario(db, usuario_id, categoria_id, tipo_validado)
        # Fonte de renda só faz sentido numa receita — ignorada silenciosamente numa despesa.
        fonte = (
            _fonte_renda_do_usuario(db, usuario_id, fonte_renda_id)
            if tipo_validado == TipoLancamento.RECEITA
            else None
        )
        descricao = (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None

        return {
            "tipo": tipo_validado,
            "conta_id": conta.id,
            "categoria_id": categoria.id,
            "fonte_renda_id": fonte.id if fonte else None,
            "valor": _valor_monetario(valor),
            "data": _data(data),
            "descricao": descricao,
        }


servico_lancamentos = ServicoLancamentos()

