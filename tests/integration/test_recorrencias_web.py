"""Teste de integração: criar uma recorrência e ver os lançamentos gerados automaticamente."""

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


def test_recorrencia_gera_lancamentos_automaticos_ao_abrir_a_tela(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})

    resposta_criacao = cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "1200", "frequencia": "mensal", "dia_referencia": "5",
        "data_inicio": "2026-01-05",
    })
    assert "Aluguel" in resposta_criacao.text
    assert "Mensal" in resposta_criacao.text

    # A geração automática dispara ao abrir /lancamentos, sem nenhuma ação manual.
    resposta_lancamentos = cliente_logado.get("/lancamentos")
    assert "Aluguel" in resposta_lancamentos.text
    assert "(automático)" in resposta_lancamentos.text
    assert "-R$ 1200.00" in resposta_lancamentos.text

    # Abrir de novo não deve duplicar.
    primeira_contagem = resposta_lancamentos.text.count("Aluguel")
    resposta_de_novo = cliente_logado.get("/lancamentos")
    assert resposta_de_novo.text.count("Aluguel") == primeira_contagem


def test_pausar_recorrencia_impede_novos_lancamentos(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    cliente_logado.post("/categorias", data={"nome": "Aluguel", "tipo": "despesa"})
    cliente_logado.post("/recorrencias", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "1200", "frequencia": "mensal", "dia_referencia": "5",
        "data_inicio": "2026-01-05",
    })

    resposta = cliente_logado.post("/recorrencias/1/alternar")
    assert "pausada" in resposta.text

    cliente_logado.get("/lancamentos")  # tentaria gerar, mas a regra está pausada
    lancamentos = cliente_logado.get("/lancamentos")
    assert "Nenhum lançamento ainda." in lancamentos.text

