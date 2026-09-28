"""
Cria um usuário diretamente no banco.

Necessário porque, nesta etapa, não existe tela pública de cadastro
(planejado para a Etapa 7) — o próprio dono do sistema (e, futuramente,
cada nova pessoa que for usar) precisa ser inserido assim, uma vez.

Uso:
    python scripts/criar_usuario.py
"""

import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import SessionLocal
from app.models.usuario import Usuario
from app.services.auth_service import gerar_hash_senha


def main() -> None:
    nome = input("Nome: ").strip()
    email = input("E-mail: ").strip().lower()
    senha = getpass.getpass("Senha: ")
    confirmacao = getpass.getpass("Confirme a senha: ")

    if senha != confirmacao:
        print("As senhas não conferem. Nada foi criado.")
        return

    db = SessionLocal()
    try:
        if db.query(Usuario).filter(Usuario.email == email).first():
            print(f"Já existe um usuário com o e-mail {email}.")
            return

        usuario = Usuario(nome=nome, email=email, senha_hash=gerar_hash_senha(senha))
        db.add(usuario)
        db.commit()
        print(f"Usuário '{nome}' criado com sucesso (id={usuario.id}).")
    finally:
        db.close()


if __name__ == "__main__":
    main()

