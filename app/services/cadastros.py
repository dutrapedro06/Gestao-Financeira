"""Regras de negócio dos cadastros básicos: contas, categorias e fontes de renda."""

from typing import Any

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda
from app.models.enums import TipoLancamento
from app.repositories import cadastros as repos

from app.services.erros import ErroDeNegocio, NaoEncontrado

TAMANHO_MAXIMO_NOME = 80


class ServicoCadastro:
    def __init__(self, repo: Any, rotulo: str):
        self.repo = repo
        self.rotulo = rotulo

    def listar(self, db: Session, usuario_id: int) -> list:
        return self.repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, item_id: int):
        item = self.repo.obter(db, usuario_id, item_id)
        if item is None:
            raise NaoEncontrado(f"{self.rotulo} não encontrada.")
        return item

    def criar(self, db: Session, usuario_id: int, nome: str, **extra: Any):
        nome = self._validar_nome(db, usuario_id, nome)
        return self.repo.adicionar(db, self._construir(usuario_id, nome, **extra))

    def atualizar(self, db: Session, usuario_id: int, item_id: int, nome: str, **extra: Any):
        item = self.obter(db, usuario_id, item_id)
        nome = self._validar_nome(db, usuario_id, nome, ignorar_id=item.id)
        self._aplicar(db, item, nome, **extra)
        return self.repo.salvar(db, item)

    def excluir(self, db: Session, usuario_id: int, item_id: int) -> None:
        item = self.obter(db, usuario_id, item_id)
        if self.repo.em_uso(db, item.id):
            raise ErroDeNegocio(
                f"{self.rotulo} possui movimentações e não pode ser excluída."
            )
        self.repo.remover(db, item)

    def _validar_nome(
        self, db: Session, usuario_id: int, nome: str | None, ignorar_id: int | None = None
    ) -> str:
        nome = (nome or "").strip()
        if not nome:
            raise ErroDeNegocio("Informe um nome.")
        if len(nome) > TAMANHO_MAXIMO_NOME:
            raise ErroDeNegocio(f"O nome deve ter no máximo {TAMANHO_MAXIMO_NOME} caracteres.")
        existente = self.repo.obter_por_nome(db, usuario_id, nome)
        if existente is not None and existente.id != ignorar_id:
            raise ErroDeNegocio(f"Já existe {self.rotulo.lower()} com esse nome.")
        return nome

    def _construir(self, usuario_id: int, nome: str, **extra: Any):
        return self.repo.model(usuario_id=usuario_id, nome=nome)

    def _aplicar(self, db: Session, item: Any, nome: str, **extra: Any) -> None:
        item.nome = nome


class ServicoCategorias(ServicoCadastro):
    @staticmethod
    def _tipo(valor: str | None) -> TipoLancamento:
        try:
            return TipoLancamento(valor)
        except ValueError:
            raise ErroDeNegocio("Tipo inválido.") from None

    def _construir(self, usuario_id: int, nome: str, tipo: str | None = None, **extra: Any):
        return Categoria(usuario_id=usuario_id, nome=nome, tipo=self._tipo(tipo))

    def _aplicar(self, db: Session, item: Categoria, nome: str, tipo: str | None = None, **extra: Any) -> None:
        novo_tipo = self._tipo(tipo)
        if novo_tipo != item.tipo and self.repo.em_uso(db, item.id):
            raise ErroDeNegocio("Não é possível alterar o tipo de uma categoria já utilizada.")
        item.nome = nome
        item.tipo = novo_tipo


servico_contas = ServicoCadastro(repos.contas, "Conta")
servico_categorias = ServicoCategorias(repos.categorias, "Categoria")
servico_fontes_renda = ServicoCadastro(repos.fontes_renda, "Fonte de renda")

__all__ = [
    "Conta",
    "FonteDeRenda",
    "ErroDeNegocio",
    "NaoEncontrado",
    "servico_contas",
    "servico_categorias",
    "servico_fontes_renda",
]

