"""Teste de integração: separar parte do salário para investimento via transferência."""

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


def test_separar_parte_do_salario_para_investimento(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    cliente_logado.post("/contas", data={"nome": "Investimento"})
    cliente_logado.post("/categorias", data={"nome": "Salário", "tipo": "receita"})

    # Recebe 1000 de salário
    cliente_logado.post("/lancamentos", data={
        "tipo": "receita", "conta_id": 1, "categoria_id": 1,
        "valor": "1000", "data": "2026-09-28",
    })
    # Separa 300 para investir
    resposta = cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 2,
        "valor": "300", "data": "2026-09-28", "descricao": "Aporte mensal",
    })
    assert "Salário" in resposta.text
    assert "Investimento" in resposta.text
    assert "Aporte mensal" in resposta.text

    saldos = cliente_logado.get("/contas")
    assert "R$ 700.00" in saldos.text   # 1000 - 300, na conta Salário
    assert "R$ 300.00" in saldos.text   # recebido na conta Investimento
    assert "R$ 1000.00" in saldos.text  # saldo geral continua o mesmo


def test_nao_permite_transferir_para_a_mesma_conta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    resposta = cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 1,
        "valor": "100", "data": "2026-09-28",
    })
    assert "não podem ser a mesma" in resposta.text


def test_editar_transferencia_via_http(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    cliente_logado.post("/contas", data={"nome": "Investimento"})
    cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 2, "valor": "300", "data": "2026-09-28",
    })

    resposta_edicao = cliente_logado.get("/transferencias/1/editar")
    assert "Salvar" in resposta_edicao.text

    resposta = cliente_logado.put("/transferencias/1", data={
        "conta_origem_id": 1, "conta_destino_id": 2, "valor": "500", "data": "2026-09-28",
        "descricao": "Aporte maior",
    })
    assert "R$ 500.00" in resposta.text
    assert "Aporte maior" in resposta.text


def test_excluir_transferencia_via_http(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Salário"})
    cliente_logado.post("/contas", data={"nome": "Investimento"})
    cliente_logado.post("/transferencias", data={
        "conta_origem_id": 1, "conta_destino_id": 2, "valor": "300", "data": "2026-09-28",
    })
    resposta = cliente_logado.delete("/transferencias/1")
    assert "Nenhuma transferência ainda." in resposta.text

