"""Teste de integração da projeção de saldo via HTTP."""

from datetime import date, timedelta

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


def test_projecao_combina_saldo_atual_com_recorrencia_futura(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})

    hoje = date.today()
    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1,
        "valor": "3000", "data": hoje.isoformat(),
    })
    # Semanal, começando daqui a 3 dias: numa janela de 6 dias cabe exatamente
    # UMA ocorrência futura (a próxima, 7 dias depois, fica de fora) —
    # determinístico independente de qual seja a data real de hoje.
    dia_da_semana_em_3_dias = (hoje.weekday() + 3) % 7
    cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 2,
        "valor": "1200", "frequencia": "semanal", "dia_referencia": str(dia_da_semana_em_3_dias),
        "data_inicio": hoje.isoformat(),
    })

    daqui_6_dias = (hoje + timedelta(days=6)).isoformat()
    resposta = cliente_logado.get(f"/projecao?ate={daqui_6_dias}")

    assert resposta.status_code == 200
    assert "R$ 3000.00" in resposta.text  # saldo atual
    assert "plotly" in resposta.text.lower()
    # A única ocorrência da recorrência dentro da janela já deveria ter sido descontada.
    assert "R$ 1800.00" in resposta.text


def test_projecao_sem_dados_nao_quebra(cliente_logado):
    resposta = cliente_logado.get("/projecao")
    assert resposta.status_code == 200
    assert "R$ 0.00" in resposta.text

