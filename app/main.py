"""
Ponto de entrada da aplicação.

Nesta Etapa 0, o objetivo é só validar a fundação: a aplicação sobe,
consegue falar com o banco de dados, e temos um endpoint simples para
confirmar isso (/health). Os models e as rotas de verdade (contas,
lançamentos, dashboard) entram nas próximas etapas.
"""

from fastapi import Depends, FastAPI, Request
from fastapi.responses import RedirectResponse
from sqlalchemy import text
from sqlalchemy.orm import Session
from starlette.middleware.sessions import SessionMiddleware

from app.config import settings
from app.database import get_db
from app.web import auth as auth_web
from app.web.deps import usuario_atual_opcional

app = FastAPI(
    title="Gestão Financeira Pessoal",
    description="Sistema web para controle financeiro pessoal.",
    version="0.1.0",
)

# Sessão via cookie assinado (não é possível decodificar/alterar sem a
# secret_key). Guarda só o usuario_id — nunca dados sensíveis no cookie.
app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)

app.include_router(auth_web.router)


@app.get("/")
def raiz(request: Request, usuario=Depends(usuario_atual_opcional)):
    if usuario is None:
        return RedirectResponse(url="/login")
    return {
        "app": "Gestão Financeira Pessoal",
        "ambiente": settings.environment,
        "status": "no ar",
        "usuario_logado": usuario.nome,
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

