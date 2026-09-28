"""
Dependency que lê o usuário logado a partir da sessão (cookie assinado).

Fica em app/web/ (não em services/) porque depende diretamente do
`Request` do Starlette/FastAPI — é uma preocupação da camada de
apresentação, não uma regra de negócio.
"""

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.usuario import Usuario


def usuario_atual_opcional(request: Request, db: Session = Depends(get_db)) -> Usuario | None:
    """Retorna o Usuario logado, ou None se não houver sessão válida."""
    usuario_id = request.session.get("usuario_id")
    if usuario_id is None:
        return None
    return db.get(Usuario, usuario_id)


def exigir_usuario_logado(
    usuario: Usuario | None = Depends(usuario_atual_opcional),
) -> Usuario:
    """
    Dependency para proteger rotas que exigem login.
    Lança 401 se não houver usuário autenticado na sessão.
    """
    if usuario is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Login necessário")
    return usuario
