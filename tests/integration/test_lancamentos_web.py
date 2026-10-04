"""Teste de integração: fluxo completo de lançar uma despesa via HTTP."""

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


def test_lancar_despesa_de_ponta_a_ponta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Vale"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})

    resposta = cliente_logado.post(
        "/lancamentos",
        data={
            "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
            "valor": "50.00", "data": "2026-09-28", "descricao": "Compras da semana",
        },
    )
    assert resposta.status_code == 200
    assert "Mercado" in resposta.text
    assert "Compras da semana" in resposta.text
    assert "-R$ 50.00" in resposta.text

    saldo_contas = cliente_logado.get("/contas")
    assert "R$ -50.00" in saldo_contas.text


def test_lancamento_sem_conta_cadastrada_mostra_aviso(cliente_logado):
    resposta = cliente_logado.get("/lancamentos")
    assert "Cadastre pelo menos uma" in resposta.text


def test_editar_lancamento_via_http(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Vale"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "50.00", "data": "2026-09-28",
    })

    resposta_edicao = cliente_logado.get("/lancamentos/1/editar")
    assert "Salvar" in resposta_edicao.text

    resposta = cliente_logado.put("/lancamentos/1", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1,
        "valor": "99.90", "data": "2026-09-28", "descricao": "Valor corrigido",
    })
    assert "-R$ 99.90" in resposta.text
    assert "Valor corrigido" in resposta.text


def test_excluir_lancamento_via_http(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Vale"})
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    cliente_logado.post("/lancamentos", data={
        "tipo": "despesa", "conta_id": 1, "categoria_id": 1, "valor": "50", "data": "2026-09-28",
    })

    resposta = cliente_logado.delete("/lancamentos/1")
    assert "Nenhum lançamento ainda." in resposta.text

