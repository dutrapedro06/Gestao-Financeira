"""
Regras de autenticação. Mantidas em services/ (e não direto na rota) para
poder ser reaproveitadas por outras rotas/testes sem duplicar lógica —
o mesmo princípio de separação usado no resto do projeto.
"""

import bcrypt
from sqlalchemy.orm import Session

from app.models.usuario import Usuario


def gerar_hash_senha(senha: str) -> str:
    """Gera o hash bcrypt de uma senha em texto plano. Nunca armazenamos
    a senha em si, só este hash."""
    return bcrypt.hashpw(senha.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verificar_senha(senha: str, senha_hash: str) -> bool:
    """Confere se a senha em texto plano bate com o hash armazenado."""
    return bcrypt.checkpw(senha.encode("utf-8"), senha_hash.encode("utf-8"))


def autenticar_usuario(db: Session, email: str, senha: str) -> Usuario | None:
    """
    Retorna o Usuario se e-mail e senha conferem, ou None caso contrário.

    Nunca revelamos qual dos dois campos está errado (e-mail inexistente
    vs. senha incorreta) — a mensagem de erro na rota é sempre genérica,
    para não dar pistas a quem estiver tentando adivinhar credenciais.
    """
    usuario = db.query(Usuario).filter(Usuario.email == email).first()
    if usuario is None:
        return None
    if not verificar_senha(senha, usuario.senha_hash):
        return None
    return usuario

