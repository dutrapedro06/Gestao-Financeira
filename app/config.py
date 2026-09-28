"""
Configuração centralizada da aplicação.

Usamos pydantic-settings para ler as variáveis de ambiente de forma tipada,
com validação automática (ex: se DATABASE_URL não existir, a aplicação
falha ao subir com uma mensagem clara, em vez de quebrar de forma
inesperada em algum ponto no meio do código).
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Conexão com o banco de dados PostgreSQL
    database_url: str

    # Chave usada para assinar o cookie de sessão (autenticação)
    secret_key: str

    # Ambiente de execução: "development" ou "production"
    environment: str = "development"


# Instância única, importada pelo resto da aplicação.
# Criar aqui (e não a cada chamada) evita reler o .env repetidamente.
settings = Settings()
