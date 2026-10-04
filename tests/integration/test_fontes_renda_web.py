"""Teste de integração de fontes de renda via HTTP (nenhum teste cobria isso ainda)."""

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


def test_criar_listar_editar_e_excluir_fonte_de_renda(cliente_logado):
    resposta = cliente_logado.post("/fontes-renda", data={"nome": "Salário CLT"})
    assert "Salário CLT" in resposta.text

    resposta_editar = cliente_logado.get("/fontes-renda/1/editar")
    assert "value=\"Salário CLT\"" in resposta_editar.text

    resposta_atualizada = cliente_logado.put("/fontes-renda/1", data={"nome": "Salário PJ"})
    assert ">Salário PJ<" in resposta_atualizada.text
    assert ">Salário CLT<" not in resposta_atualizada.text  # só o item da lista, não o placeholder do form

    resposta_excluida = cliente_logado.delete("/fontes-renda/1")
    assert "Nenhuma fonte de renda cadastrada ainda." in resposta_excluida.text


def test_nao_permite_fonte_de_renda_duplicada(cliente_logado):
    cliente_logado.post("/fontes-renda", data={"nome": "Freelance"})
    resposta = cliente_logado.post("/fontes-renda", data={"nome": "Freelance"})
    assert "Já existe" in resposta.text

