"""Testes unitários das regras de negócio de transferências entre contas."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Lancamento, Usuario
from app.models.enums import TipoLancamento
from app.services import saldo_service
from app.services.cadastros import servico_contas
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.transferencias import servico_transferencias


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
def contas(db, usuario):
    return {
        "salario": servico_contas.criar(db, usuario.id, "Salário"),
        "investimento": servico_contas.criar(db, usuario.id, "Investimento"),
    }


def test_criar_transferencia(db, usuario, contas):
    t = servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    assert t.valor == 300


def test_nao_permite_mesma_conta_origem_e_destino(db, usuario, contas):
    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, usuario.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["salario"].id,
            valor="100", data=date.today().isoformat(),
        )


def test_valor_zero_e_rejeitado(db, usuario, contas):
    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, usuario.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
            valor="0", data=date.today().isoformat(),
        )


def test_conta_de_outro_usuario_e_rejeitada(db, usuario, contas):
    outro = Usuario(nome="Outro", email="outro@example.com", senha_hash="x")
    db.add(outro)
    db.commit()

    with pytest.raises(ErroDeNegocio):
        servico_transferencias.criar(
            db, outro.id,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
            valor="100", data=date.today().isoformat(),
        )


def test_excluir_transferencia_inexistente(db, usuario):
    with pytest.raises(NaoEncontrado):
        servico_transferencias.excluir(db, usuario.id, 999)


def test_transferencia_afeta_saldo_das_duas_contas(db, usuario, contas):
    servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    assert saldo_service.saldo_conta(db, contas["salario"].id) == -300
    assert saldo_service.saldo_conta(db, contas["investimento"].id) == 300


def test_transferencia_nao_conta_como_despesa_por_categoria(db, usuario, contas):
    # Regressão do ADR 0004: transferência não deve aparecer nos gastos por categoria.
    categoria = Categoria(usuario_id=usuario.id, nome="Mercado", tipo=TipoLancamento.DESPESA)
    db.add(categoria)
    db.commit()

    servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )

    total_despesas_por_categoria = (
        db.query(Lancamento).filter(Lancamento.categoria_id == categoria.id).count()
    )
    assert total_despesas_por_categoria == 0


def test_atualizar_transferencia(db, usuario, contas):
    t = servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    atualizada = servico_transferencias.atualizar(
        db, usuario.id, t.id,
        conta_origem_id=contas["investimento"].id, conta_destino_id=contas["salario"].id,
        valor="150", data=date.today().isoformat(), descricao="Estorno parcial",
    )
    assert atualizada.conta_origem_id == contas["investimento"].id
    assert atualizada.valor == 150


def test_atualizar_transferencia_inexistente_lanca_nao_encontrado(db, usuario, contas):
    with pytest.raises(NaoEncontrado):
        servico_transferencias.atualizar(
            db, usuario.id, 999,
            conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
            valor="100", data=date.today().isoformat(),
        )


def test_excluir_transferencia_remove_de_verdade(db, usuario, contas):
    t = servico_transferencias.criar(
        db, usuario.id,
        conta_origem_id=contas["salario"].id, conta_destino_id=contas["investimento"].id,
        valor="300", data=date.today().isoformat(),
    )
    servico_transferencias.excluir(db, usuario.id, t.id)
    assert servico_transferencias.listar(db, usuario.id) == []

