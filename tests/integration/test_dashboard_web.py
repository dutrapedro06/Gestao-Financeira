"""Teste de integração do dashboard: filtros, totais e presença dos gráficos no HTML."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import Usuario
from app.services.auth_service import gerar_hash_senha

engine = create_engine(
    "sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool
)
SessaoTeste = sessionmaker(bind=engine)


def _sobrescrever_db():
    db = SessaoTeste()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(autouse=True)
def banco_limpo():
    Base.metadata.create_all(engine)
    app.dependency_overrides[get_db] = _sobrescrever_db
    yield
    app.dependency_overrides.pop(get_db, None)
    Base.metadata.drop_all(engine)


@pytest.fixture()
def cliente_logado():
    db = SessaoTeste()
    db.add(Usuario(nome="Pedro", email="pedro@example.com", senha_hash=gerar_hash_senha("123456")))
    db.commit()
    db.close()

    cliente = TestClient(app)
    cliente.post("/login", data={"email": "pedro@example.com", "senha": "123456"})
    return cliente


def test_dashboard_mostra_totais_e_graficos(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})

    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1, "valor": "1000", "data": "2026-09-05",
    })
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2, "valor": "200", "data": "2026-09-10",
    })

    resposta = cliente_logado.get("/dashboard?data_inicio=2026-09-01&data_fim=2026-09-30")
    assert resposta.status_code == 200
    assert "R$ 1000.00" in resposta.text   # receitas
    assert "R$ 200.00" in resposta.text    # despesas
    assert "R$ 800.00" in resposta.text    # saldo do período
    assert "Mercado" in resposta.text      # aparece na lista e no gráfico
    assert "plotly" in resposta.text.lower()  # o gráfico foi de fato embutido


def test_dashboard_filtra_por_categoria(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    cliente_logado.post("/categorias", data={"nome": "Transporte", "tipo": "despesa"})
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1, "valor": "200", "data": "2026-09-10",
    })
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2, "valor": "80", "data": "2026-09-12",
    })

    resposta = cliente_logado.get("/dashboard?data_inicio=2026-09-01&data_fim=2026-09-30&categoria_id=1")
    assert "R$ 200.00" in resposta.text
    # "Transporte" ainda aparece no dropdown de filtro (opção disponível) — o que
    # importa é que o valor da despesa de Transporte (80) não entrou no total.
    assert "R$ 80.00" not in resposta.text


def test_dashboard_sem_lancamentos_nao_quebra(cliente_logado):
    resposta = cliente_logado.get("/dashboard")
    assert resposta.status_code == 200
    assert "Sem despesas no período" in resposta.text

