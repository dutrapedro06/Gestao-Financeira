"""
Rotas de autenticação (HTML). Como definido, não há cadastro público
ainda — só login para usuários já criados via script.
"""

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.auth_service import autenticar_usuario
from app.web.deps import usuario_atual_opcional

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")


@router.get("/login")
def pagina_login(request: Request, usuario=Depends(usuario_atual_opcional)):
    if usuario is not None:
        return RedirectResponse(url="/", status_code=status.HTTP_302_FOUND)
    return templates.TemplateResponse(request, "login.html", {"erro": None})


@router.post("/login")
def processar_login(
    request: Request,
    email: str = Form(...),
    senha: str = Form(...),
    db: Session = Depends(get_db),
):
    usuario = autenticar_usuario(db, email, senha)
    if usuario is None:
        return templates.TemplateResponse(
            request,
            "login.html",
            {"erro": "E-mail ou senha incorretos."},
            status_code=status.HTTP_401_UNAUTHORIZED,
        )

    request.session["usuario_id"] = usuario.id
    return RedirectResponse(url="/", status_code=status.HTTP_302_FOUND)


@router.post("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)

