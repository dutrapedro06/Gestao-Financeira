"""Testes da projeção de saldo futuro (ADR 0005)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services import projecao_service as svc
from app.services.cadastros import servico_categorias, servico_contas
from app.services.lancamentos import servico_lancamentos
from app.services.regras_recorrencia import servico_recorrencias


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
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    aluguel = servico_categorias.criar(db, usuario.id, "Aluguel", tipo="despesa")
    salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")
    return {"conta": conta, "aluguel": aluguel, "salario": salario}


def test_saldo_atual_reflete_so_o_que_ja_aconteceu(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="1000", data=date(2026, 9, 1).isoformat(),
    )
    saldo = svc.saldo_atual(db, usuario.id, referencia=date(2026, 9, 15))
    assert saldo == 1000


def test_projecao_sem_recorrencia_mantem_saldo_constante(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="1000", data=date(2026, 9, 1).isoformat(),
    )
    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 9, 20), hoje=date(2026, 9, 15))
    assert (df["saldo"] == 1000).all()


def test_projecao_incorpora_despesa_recorrente_futura(db, usuario, cenario):
    servico_lancamentos.criar(
        db, usuario.id, tipo="receita", conta_id=cenario["conta"].id,
        categoria_id=cenario["salario"].id, valor="3000", data=date(2026, 9, 1).isoformat(),
    )
    servico_recorrencias.criar(
        db, usuario.id, tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["aluguel"].id,
        valor="1200", frequencia="mensal", dia_referencia="10", data_inicio=date(2026, 9, 10).isoformat(),
    )

    # Hoje é dia 15/09 — o aluguel do dia 10/09 já passou (já deveria ter sido
    # materializado como lançamento real), só o de outubro é projeção de verdade.
    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 10, 15), hoje=date(2026, 9, 15))

    saldo_antes_do_aluguel_de_outubro = df.loc[df["data"] == "2026-10-09", "saldo"].iloc[0]
    saldo_depois_do_aluguel_de_outubro = df.loc[df["data"] == "2026-10-10", "saldo"].iloc[0]

    assert saldo_antes_do_aluguel_de_outubro == 3000
    assert saldo_depois_do_aluguel_de_outubro == 1800  # 3000 - 1200


def test_regra_inativa_nao_entra_na_projecao(db, usuario, cenario):
    regra = servico_recorrencias.criar(
        db, usuario.id, tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["aluguel"].id,
        valor="1200", frequencia="mensal", dia_referencia="10", data_inicio=date(2026, 9, 10).isoformat(),
    )
    servico_recorrencias.alternar_ativa(db, usuario.id, regra.id)

    df = svc.projecao_futura(db, usuario.id, ate=date(2026, 10, 15), hoje=date(2026, 9, 15))
    assert (df["saldo"] == 0).all()

