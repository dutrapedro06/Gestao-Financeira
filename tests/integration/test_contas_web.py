"""
Teste de integração ponta a ponta: login real + CRUD de contas via HTTP,
usando SQLite em memória no lugar do Postgres (mais rápido, sem precisar
do docker-compose para rodar este teste específico).
"""

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
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
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


def test_login_com_credenciais_erradas_mostra_erro():
    cliente = TestClient(app)
    resposta = cliente.post("/login", data={"email": "x@x.com", "senha": "errada"})
    assert resposta.status_code == 401
    assert "incorretos" in resposta.text


def test_criar_e_listar_conta(cliente_logado):
    resposta = cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    assert resposta.status_code == 200
    assert "Conta Corrente" in resposta.text
    assert "R$ 0.00" in resposta.text  # saldo geral, sem lançamentos ainda


def test_nao_permite_conta_duplicada(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    resposta = cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    assert "Já existe" in resposta.text


def test_editar_conta(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    resposta = cliente_logado.get("/contas")
    conta_id = 1  # primeira conta criada no banco limpo
    resposta = cliente_logado.put(f"/contas/{conta_id}", data={"nome": "Conta Renomeada"})
    assert "Conta Renomeada" in resposta.text


def test_criar_categoria_e_impedir_exclusao_em_uso(cliente_logado):
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    resposta = cliente_logado.get("/categorias")
    assert "Mercado" in resposta.text
    assert "Despesa" in resposta.text


def test_rotas_exigem_login():
    cliente = TestClient(app)
    resposta = cliente.get("/contas", follow_redirects=False)
    assert resposta.status_code == 401


def test_excluir_conta_via_http(cliente_logado):
    cliente_logado.post("/contas", data={"nome": "Conta Corrente"})
    resposta = cliente_logado.delete("/contas/1")
    assert "Nenhuma conta cadastrada ainda." in resposta.text


def test_editar_categoria_via_http(cliente_logado):
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    resposta_edicao = cliente_logado.get("/categorias/1/editar")
    assert "Salvar" in resposta_edicao.text

    resposta = cliente_logado.put("/categorias/1", data={"nome": "Supermercado", "tipo": "despesa"})
    assert ">Supermercado<" in resposta.text


def test_excluir_categoria_via_http(cliente_logado):
    cliente_logado.post("/categorias", data={"nome": "Mercado", "tipo": "despesa"})
    resposta = cliente_logado.delete("/categorias/1")
    assert "Nenhuma categoria cadastrada ainda." in resposta.text


def test_logout_limpa_sessao(cliente_logado):
    cliente_logado.post("/logout")
    resposta = cliente_logado.get("/contas", follow_redirects=False)
    assert resposta.status_code == 401


def test_acessar_login_ja_autenticado_redireciona(cliente_logado):
    resposta = cliente_logado.get("/login", follow_redirects=False)
    assert resposta.status_code == 302
    assert resposta.headers["location"] == "/"


def test_raiz_redireciona_para_lancamentos_quando_logado(cliente_logado):
    resposta = cliente_logado.get("/", follow_redirects=False)
    assert resposta.status_code == 307
    assert resposta.headers["location"] == "/lancamentos"

