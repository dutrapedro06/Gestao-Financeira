"""Testes unitários das regras de negócio de lançamentos."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services.cadastros import servico_categorias, servico_contas, servico_fontes_renda
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.lancamentos import servico_lancamentos


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    u = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def cenario(db, usuario):
    conta_salario = servico_contas.criar(db, usuario.id, "Salário")
    conta_vale = servico_contas.criar(db, usuario.id, "Vale")
    categoria_mercado = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    categoria_salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")
    fonte = servico_fontes_renda.criar(db, usuario.id, "Salário CLT")
    return {
        "conta_salario": conta_salario,
        "conta_vale": conta_vale,
        "categoria_mercado": categoria_mercado,
        "categoria_salario": categoria_salario,
        "fonte": fonte,
    }


def test_criar_despesa_na_conta_escolhida(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        valor="50", data=date.today().isoformat(),
    )
    assert lancamento.conta_id == cenario["conta_vale"].id
    assert lancamento.valor == 50


def test_criar_receita_com_fonte(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="receita", conta_id=cenario["conta_salario"].id, categoria_id=cenario["categoria_salario"].id,
        fonte_renda_id=cenario["fonte"].id, valor="1000", data=date.today().isoformat(),
    )
    assert lancamento.fonte_renda_id == cenario["fonte"].id


def test_fonte_de_renda_e_ignorada_em_despesa(db, usuario, cenario):
    lancamento = servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        fonte_renda_id=cenario["fonte"].id, valor="50", data=date.today().isoformat(),
    )
    assert lancamento.fonte_renda_id is None


def test_categoria_de_tipo_errado_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, usuario.id,
            tipo="receita", conta_id=cenario["conta_salario"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="50", data=date.today().isoformat(),
        )


def test_valor_zero_ou_negativo_e_rejeitado(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, usuario.id,
            tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="0", data=date.today().isoformat(),
        )


def test_conta_de_outro_usuario_e_rejeitada(db, usuario, cenario):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_lancamentos.criar(
            db, outro.id,
            tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
            valor="50", data=date.today().isoformat(),
        )


def test_excluir_lancamento_inexistente(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_lancamentos.excluir(db, usuario.id, 999)


def test_saldo_reflete_lancamento_na_conta_certa(db, usuario, cenario):
    from app.services import saldo_service

    servico_lancamentos.criar(
        db, usuario.id,
        tipo="despesa", conta_id=cenario["conta_vale"].id, categoria_id=cenario["categoria_mercado"].id,
        valor="50", data=date.today().isoformat(),
    )
    assert saldo_service.saldo_conta(db, cenario["conta_vale"].id) == -50
    assert saldo_service.saldo_conta(db, cenario["conta_salario"].id) == 0

