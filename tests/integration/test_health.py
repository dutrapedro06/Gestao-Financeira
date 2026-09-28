"""
Testes de integração.

test_raiz_redireciona_sem_login: não depende do banco, roda sempre.
test_health_confirma_conexao_com_banco: precisa do Postgres do
docker-compose no ar e do .env configurado (SELECT 1 de verdade).
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_raiz_redireciona_para_login_sem_sessao():
    resposta = client.get("/", follow_redirects=False)
    assert resposta.status_code == 307
    assert resposta.headers["location"] == "/login"


def test_pagina_de_login_carrega():
    resposta = client.get("/login")
    assert resposta.status_code == 200
    assert "E-mail" in resposta.text


def test_health_confirma_conexao_com_banco():
    resposta = client.get("/health")
    assert resposta.status_code == 200
    assert resposta.json() == {"banco_de_dados": "conectado"}

