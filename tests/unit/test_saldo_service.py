"""
Testes unitários do cálculo de saldo. Usa SQLite em memória (não o
Postgres de produção) — o service não depende de nada específico do
dialeto do banco, então isso valida a lógica de forma rápida e isolada.
"""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Categoria, Conta, Lancamento, TransferenciaEntreContas, Usuario
from app.models.enums import TipoLancamento
from app.services import saldo_service


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


def test_saldo_conta_sem_movimentacao_e_zero(db, usuario):
    conta = Conta(usuario_id=usuario.id, nome="Conta Corrente")
    db.add(conta)
    db.commit()

    assert saldo_service.saldo_conta(db, conta.id) == 0


def test_saldo_conta_soma_receita_e_subtrai_despesa(db, usuario):
    conta = Conta(usuario_id=usuario.id, nome="Conta Corrente")
    categoria = Categoria(usuario_id=usuario.id, nome="Salário", tipo=TipoLancamento.RECEITA)
    db.add_all([conta, categoria])
    db.commit()

    db.add_all([
        Lancamento(
            conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.RECEITA,
            valor=1000, data=date.today(),
        ),
        Lancamento(
            conta_id=conta.id, categoria_id=categoria.id, tipo=TipoLancamento.DESPESA,
            valor=300, data=date.today(),
        ),
    ])
    db.commit()

    assert saldo_service.saldo_conta(db, conta.id) == 700


def test_transferencia_afeta_as_duas_contas_sem_contar_como_gasto(db, usuario):
    origem = Conta(usuario_id=usuario.id, nome="Salário")
    destino = Conta(usuario_id=usuario.id, nome="Investimento")
    db.add_all([origem, destino])
    db.commit()

    db.add(TransferenciaEntreContas(
        conta_origem_id=origem.id, conta_destino_id=destino.id,
        valor=300, data=date.today(),
    ))
    db.commit()

    assert saldo_service.saldo_conta(db, origem.id) == -300
    assert saldo_service.saldo_conta(db, destino.id) == 300


def test_saldo_geral_soma_todas_as_contas(db, usuario):
    a = Conta(usuario_id=usuario.id, nome="A")
    b = Conta(usuario_id=usuario.id, nome="B")
    db.add_all([a, b])
    db.commit()

    saldos = {a.id: 100, b.id: 50}
    assert saldo_service.saldo_geral(saldos) == 150

