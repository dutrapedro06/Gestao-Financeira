"""Testes das agregações do dashboard (Pandas)."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Usuario
from app.services import dashboard_service as svc
from app.services.cadastros import servico_categorias, servico_contas
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
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    mercado = servico_categorias.criar(db, usuario.id, "Mercado", tipo="despesa")
    transporte = servico_categorias.criar(db, usuario.id, "Transporte", tipo="despesa")
    salario = servico_categorias.criar(db, usuario.id, "Salário", tipo="receita")

    servico_lancamentos.criar(db, usuario.id, tipo="receita", conta_id=conta.id, categoria_id=salario.id, valor="1000", data="2026-09-01")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=mercado.id, valor="200", data="2026-09-05")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=mercado.id, valor="50", data="2026-09-10")
    servico_lancamentos.criar(db, usuario.id, tipo="despesa", conta_id=conta.id, categoria_id=transporte.id, valor="80", data="2026-09-15")
    return {"conta": conta}


def test_resumo_periodo_soma_receitas_e_despesas(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30))
    assert resumo["total_receitas"] == 1000
    assert resumo["total_despesas"] == 330
    assert resumo["saldo_periodo"] == 670


def test_resumo_periodo_respeita_o_filtro_de_data(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 6))
    assert resumo["total_despesas"] == 200  # só a do dia 5, não a do dia 10 nem 15


def test_gastos_por_categoria_agrupa_e_soma(db, usuario, cenario):
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30))
    agrupado = svc.gastos_por_categoria(resumo["dataframe"])

    mercado = agrupado[agrupado["categoria"] == "Mercado"]["valor"].iloc[0]
    transporte = agrupado[agrupado["categoria"] == "Transporte"]["valor"].iloc[0]
    assert mercado == 250  # 200 + 50
    assert transporte == 80


def test_gastos_por_categoria_vazio_quando_sem_despesas(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta")
    resumo = svc.resumo_periodo(db, usuario.id, date(2026, 1, 1), date(2026, 1, 31))
    agrupado = svc.gastos_por_categoria(resumo["dataframe"])
    assert agrupado.empty


def test_saldo_geral_antes_de_ignora_o_que_vem_depois(db, usuario, cenario):
    # antes do dia 10: só a receita de 1000 e a despesa de 200 (dia 5)
    saldo = svc.saldo_geral_antes_de(db, usuario.id, date(2026, 9, 10))
    assert saldo == 800


def test_evolucao_saldo_acumula_dia_a_dia(db, usuario, cenario):
    df = svc.evolucao_saldo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 30), saldo_inicial=0)

    saldo_dia_1 = df.loc[df["data"] == "2026-09-01", "saldo"].iloc[0]
    saldo_dia_5 = df.loc[df["data"] == "2026-09-05", "saldo"].iloc[0]
    saldo_dia_15 = df.loc[df["data"] == "2026-09-15", "saldo"].iloc[0]
    saldo_dia_30 = df.loc[df["data"] == "2026-09-30", "saldo"].iloc[0]

    assert saldo_dia_1 == 1000
    assert saldo_dia_5 == 800    # 1000 - 200
    assert saldo_dia_15 == 670   # 1000 - 200 - 50 - 80
    assert saldo_dia_30 == 670   # sem mais movimentação, mantém


def test_evolucao_saldo_comeca_do_saldo_inicial_informado(db, usuario, cenario):
    df = svc.evolucao_saldo(db, usuario.id, date(2026, 9, 1), date(2026, 9, 1), saldo_inicial=500)
    assert df["saldo"].iloc[0] == 1500  # 500 de antes + 1000 do dia 1

