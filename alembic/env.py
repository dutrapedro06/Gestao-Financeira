"""
env.py do Alembic — adaptado do template padrão para:

1. Ler a URL do banco de app.config.settings (o mesmo .env da aplicação),
   em vez de duplicar essa configuração no alembic.ini.
2. Importar app.models, para que o Base.metadata conheça todas as
   tabelas na hora de gerar uma migração automática
   (`alembic revision --autogenerate`).
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.config import settings
from app.database import Base

# Importa todos os models para popular Base.metadata antes do autogenerate.
import app.models  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Sobrescreve a URL do banco definida no .ini com a do nosso .env.
config.set_main_option("sqlalchemy.url", settings.database_url)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Gera o SQL das migrações sem se conectar de fato ao banco."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Conecta de fato ao banco e aplica as migrações (uso normal)."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

