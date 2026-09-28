"""
Ponto de entrada da aplicação.

Nesta Etapa 0, o objetivo é só validar a fundação: a aplicação sobe,
consegue falar com o banco de dados, e temos um endpoint simples para
confirmar isso (/health). Os models e as rotas de verdade (contas,
lançamentos, dashboard) entram nas próximas etapas.
"""

from fastapi import Depends, FastAPI
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db

app = FastAPI(
    title="Gestão Financeira Pessoal",
    description="Sistema web para controle financeiro pessoal.",
    version="0.1.0",
)


@app.get("/")
def raiz() -> dict:
    return {
        "app": "Gestão Financeira Pessoal",
        "ambiente": settings.environment,
        "status": "no ar",
    }


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict:
    """
    Confirma que a aplicação consegue de fato executar uma query no
    Postgres — não só que a variável DATABASE_URL existe, mas que a
    conexão funciona de ponta a ponta. Útil tanto agora, para você
    validar o setup local, quanto depois, em produção, para health
    checks automáticos da hospedagem.
    """
    db.execute(text("SELECT 1"))
    return {"banco_de_dados": "conectado"}
