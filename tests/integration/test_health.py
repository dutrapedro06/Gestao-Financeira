"""
Teste de integração da Etapa 0: valida que a aplicação sobe e que o
endpoint /health consegue de fato conversar com o banco de dados.

Para rodar: pytest (com o Postgres do docker-compose no ar e o .env
configurado).
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_raiz_responde():
    resposta = client.get("/")
    assert resposta.status_code == 200
    assert resposta.json()["app"] == "Gestão Financeira Pessoal"


def test_health_confirma_conexao_com_banco():
    resposta = client.get("/health")
    assert resposta.status_code == 200
    assert resposta.json() == {"banco_de_dados": "conectado"}
