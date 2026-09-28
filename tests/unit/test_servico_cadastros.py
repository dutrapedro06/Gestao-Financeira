"""Testes unitários dos serviços de cadastro (contas, categorias, fontes de renda)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Conta, Lancamento, Usuario
from app.models.enums import TipoLancamento
from app.services.cadastros import ErroDeNegocio, NaoEncontrado, servico_categorias, servico_contas


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    usuario = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(usuario)
    db.commit()
    return usuario


def test_criar_conta(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    assert conta.id is not None
    assert conta.nome == "Conta Corrente"


def test_nao_permite_nome_duplicado(db, usuario):
    servico_contas.criar(db, usuario.id, "Conta Corrente")
    with pytest.raises(ErroDeNegocio):
        servico_contas.criar(db, usuario.id, "conta corrente")  # case-insensitive


def test_nao_permite_nome_vazio(db, usuario):
    with pytest.raises(ErroDeNegocio):
        servico_contas.criar(db, usuario.id, "   ")


def test_atualizar_conta_inexistente_lanca_nao_encontrado(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_contas.atualizar(db, usuario.id, 999, "Nome qualquer")


def test_excluir_conta_em_uso_e_bloqueado(db, usuario):
    categoria = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    db.add(Lancamento(
        conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
        valor=50, data=date.today(),
    ))
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_contas.excluir(db, usuario.id, conta.id)


def test_excluir_conta_sem_uso_funciona(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    servico_contas.excluir(db, usuario.id, conta.id)
    assert servico_contas.listar(db, usuario.id) == []


def test_isolamento_entre_usuarios(db, usuario):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    servico_contas.criar(db, usuario.id, "Conta do Pedro")
    assert servico_contas.listar(db, outro.id) == []


def test_categoria_nao_pode_trocar_tipo_se_ja_usada(db, usuario):
    categoria = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    db.add(Lancamento(
        conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
        valor=50, data=date.today(),
    ))
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_categorias.atualizar(db, usuario.id, categoria.id, "Mercado", tipo="receita")

