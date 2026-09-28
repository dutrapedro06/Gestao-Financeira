"""
Configuração da conexão com o banco de dados.

Este módulo cria o "engine" (a conexão de fato com o Postgres) e uma
fábrica de sessões (SessionLocal). Cada requisição HTTP vai usar sua
própria sessão, aberta e fechada automaticamente através da função
`get_db` abaixo — isso evita vazamento de conexões e é o padrão
recomendado pelo próprio FastAPI para uso com SQLAlchemy.
"""

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """
    Classe base para todos os models SQLAlchemy (Etapa 1 em diante).
    Mantida aqui, e não em app/models/, para evitar import circular
    entre database.py e os arquivos de model.
    """

    pass


def get_db() -> Generator[Session, None, None]:
    """
    Dependency do FastAPI: abre uma sessão de banco por requisição
    e garante que ela seja fechada ao final, mesmo se ocorrer um erro.

    Uso em uma rota:
        def minha_rota(db: Session = Depends(get_db)):
            ...
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
