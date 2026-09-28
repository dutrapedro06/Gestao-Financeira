#!/usr/bin/env bash
set -e
# Rode este script na RAIZ do seu repositório (~/Gestao-financeira)
echo "Criando arquivos da Etapa 1..."

cat > 'alembic.ini' << 'ARQUIVO_FIM'
# A generic, single database configuration.

[alembic]
# path to migration scripts.
# this is typically a path given in POSIX (e.g. forward slashes)
# format, relative to the token %(here)s which refers to the location of this
# ini file
script_location = %(here)s/alembic

# template used to generate migration file names; The default value is %%(rev)s_%%(slug)s
# Uncomment the line below if you want the files to be prepended with date and time
# see https://alembic.sqlalchemy.org/en/latest/tutorial.html#editing-the-ini-file
# for all available tokens
# file_template = %%(year)d_%%(month).2d_%%(day).2d_%%(hour).2d%%(minute).2d-%%(rev)s_%%(slug)s
# Or organize into date-based subdirectories (requires recursive_version_locations = true)
# file_template = %%(year)d/%%(month).2d/%%(day).2d_%%(hour).2d%%(minute).2d_%%(second).2d_%%(rev)s_%%(slug)s

# sys.path path, will be prepended to sys.path if present.
# defaults to the current working directory.  for multiple paths, the path separator
# is defined by "path_separator" below.
prepend_sys_path = .


# timezone to use when rendering the date within the migration file
# as well as the filename.
# If specified, requires the tzdata library which can be installed by adding
# `alembic[tz]` to the pip requirements.
# string value is passed to ZoneInfo()
# leave blank for localtime
# timezone =

# max length of characters to apply to the "slug" field
# truncate_slug_length = 40

# set to 'true' to run the environment during
# the 'revision' command, regardless of autogenerate
# revision_environment = false

# set to 'true' to allow .pyc and .pyo files without
# a source .py file to be detected as revisions in the
# versions/ directory
# sourceless = false

# version location specification; This defaults
# to <script_location>/versions.  When using multiple version
# directories, initial revisions must be specified with --version-path.
# The path separator used here should be the separator specified by "path_separator"
# below.
# version_locations = %(here)s/bar:%(here)s/bat:%(here)s/alembic/versions

# path_separator; This indicates what character is used to split lists of file
# paths, including version_locations and prepend_sys_path within configparser
# files such as alembic.ini.
# The default rendered in new alembic.ini files is "os", which uses os.pathsep
# to provide os-dependent path splitting.
#
# Note that in order to support legacy alembic.ini files, this default does NOT
# take place if path_separator is not present in alembic.ini.  If this
# option is omitted entirely, fallback logic is as follows:
#
# 1. Parsing of the version_locations option falls back to using the legacy
#    "version_path_separator" key, which if absent then falls back to the legacy
#    behavior of splitting on spaces and/or commas.
# 2. Parsing of the prepend_sys_path option falls back to the legacy
#    behavior of splitting on spaces, commas, or colons.
#
# Valid values for path_separator are:
#
# path_separator = :
# path_separator = ;
# path_separator = space
# path_separator = newline
#
# Use os.pathsep. Default configuration used for new projects.
path_separator = os

# set to 'true' to search source files recursively
# in each "version_locations" directory
# new in Alembic version 1.10
# recursive_version_locations = false

# the output encoding used when revision files
# are written from script.py.mako
# output_encoding = utf-8

# database URL.  This is consumed by the user-maintained env.py script only.
# other means of configuring database URLs may be customized within the env.py
# file.
# A URL de conexão NÃO fica aqui — é lida de app.config.settings dentro
# de alembic/env.py, para reaproveitar o mesmo .env usado pela aplicação
# e evitar manter a mesma informação em dois lugares.
# sqlalchemy.url =


[post_write_hooks]
# post_write_hooks defines scripts or Python functions that are run
# on newly generated revision scripts.  See the documentation for further
# detail and examples

# format using "black" - use the console_scripts runner, against the "black" entrypoint
# hooks = black
# black.type = console_scripts
# black.entrypoint = black
# black.options = -l 79 REVISION_SCRIPT_FILENAME

# lint with attempts to fix using "ruff" - use the module runner, against the "ruff" module
# hooks = ruff
# ruff.type = module
# ruff.module = ruff
# ruff.options = check --fix REVISION_SCRIPT_FILENAME

# Alternatively, use the exec runner to execute a binary found on your PATH
# hooks = ruff
# ruff.type = exec
# ruff.executable = ruff
# ruff.options = check --fix REVISION_SCRIPT_FILENAME

# Logging configuration.  This is also consumed by the user-maintained
# env.py script only.
[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARNING
handlers = console
qualname =

[logger_sqlalchemy]
level = WARNING
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S

ARQUIVO_FIM

mkdir -p 'alembic'
cat > 'alembic/env.py' << 'ARQUIVO_FIM'
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

ARQUIVO_FIM

mkdir -p 'alembic'
cat > 'alembic/script.py.mako' << 'ARQUIVO_FIM'
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

# revision identifiers, used by Alembic.
revision: str = ${repr(up_revision)}
down_revision: Union[str, Sequence[str], None] = ${repr(down_revision)}
branch_labels: Union[str, Sequence[str], None] = ${repr(branch_labels)}
depends_on: Union[str, Sequence[str], None] = ${repr(depends_on)}


def upgrade() -> None:
    """Upgrade schema."""
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    """Downgrade schema."""
    ${downgrades if downgrades else "pass"}

ARQUIVO_FIM

mkdir -p 'app'
cat > 'app/main.py' << 'ARQUIVO_FIM'
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

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/__init__.py' << 'ARQUIVO_FIM'
"""
Importar todos os models aqui é o que permite ao Alembic "enxergar"
todas as tabelas na hora de gerar uma migração automática
(`alembic revision --autogenerate`). Sem isso, o Base.metadata ficaria
incompleto e a migração sairia vazia ou incompleta.
"""

from app.models.categoria import Categoria
from app.models.conta import Conta
from app.models.fonte_renda import FonteDeRenda
from app.models.lancamento import Lancamento
from app.models.regra_recorrencia import RegraRecorrencia
from app.models.transferencia import TransferenciaEntreContas
from app.models.usuario import Usuario

__all__ = [
    "Categoria",
    "Conta",
    "FonteDeRenda",
    "Lancamento",
    "RegraRecorrencia",
    "TransferenciaEntreContas",
    "Usuario",
]

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/categoria.py' << 'ARQUIVO_FIM'
"""
Categoria: classificação de receitas e despesas (ex: "Mercado",
"Transporte", "Salário"). Pertence a um usuário — cada um mantém suas
próprias categorias.
"""

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TipoLancamento


class Categoria(Base):
    __tablename__ = "categorias"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(80), nullable=False)
    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)

    usuario: Mapped["Usuario"] = relationship(back_populates="categorias")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="categoria")

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/conta.py' << 'ARQUIVO_FIM'
"""
Conta: carteira/conta do usuário (ex: conta corrente, vale-refeição,
investimento).

O saldo NUNCA é armazenado como coluna fixa — ele é sempre calculado a
partir do histórico de Lancamento e TransferenciaEntreContas associados a
esta conta (ver ADR 0004). Isso evita que o saldo exibido fique
dessincronizado do histórico real de movimentações. O cálculo em si fica
em app/services (Etapa 2), não aqui no model.
"""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Conta(Base):
    __tablename__ = "contas"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(120), nullable=False)

    # Preparado para multi-moeda no futuro (ADR: só BRL por enquanto),
    # sem exigir migração de schema quando isso for necessário.
    moeda: Mapped[str] = mapped_column(String(3), nullable=False, default="BRL", server_default="BRL")

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    usuario: Mapped["Usuario"] = relationship(back_populates="contas")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="conta", cascade="all, delete-orphan")
    transferencias_enviadas: Mapped[list["TransferenciaEntreContas"]] = relationship(
        back_populates="conta_origem",
        foreign_keys="TransferenciaEntreContas.conta_origem_id",
    )
    transferencias_recebidas: Mapped[list["TransferenciaEntreContas"]] = relationship(
        back_populates="conta_destino",
        foreign_keys="TransferenciaEntreContas.conta_destino_id",
    )

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/enums.py' << 'ARQUIVO_FIM'
"""
Enums compartilhados entre models — ficam em um módulo próprio para
evitar import circular entre, por exemplo, categoria.py e lancamento.py.
"""

import enum


class TipoLancamento(str, enum.Enum):
    RECEITA = "receita"
    DESPESA = "despesa"


class FrequenciaRecorrencia(str, enum.Enum):
    MENSAL = "mensal"
    SEMANAL = "semanal"

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/fonte_renda.py' << 'ARQUIVO_FIM'
"""
FonteDeRenda: origem das receitas (ex: "Salário CLT", "Freelance").
Usada para a visão por fonte no dashboard. Só faz sentido em lançamentos
de receita — é opcional em Lancamento.
"""

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class FonteDeRenda(Base):
    __tablename__ = "fontes_renda"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    nome: Mapped[str] = mapped_column(String(80), nullable=False)

    usuario: Mapped["Usuario"] = relationship(back_populates="fontes_renda")
    lancamentos: Mapped[list["Lancamento"]] = relationship(back_populates="fonte_renda")

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/lancamento.py' << 'ARQUIVO_FIM'
"""
Lancamento: a entidade central — cobre tanto receita quanto despesa.

Note que "conta_id" é onde o seu exemplo de uso ganha vida: ao registrar
uma despesa, você escolhe de qual conta ela sai (ex: Vale-refeição em vez
de Conta Corrente), sem precisar de nenhuma lógica especial — é só um
lançamento vinculado àquela conta.
"""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import TipoLancamento


class Lancamento(Base):
    __tablename__ = "lancamentos"

    id: Mapped[int] = mapped_column(primary_key=True)
    conta_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)
    categoria_id: Mapped[int] = mapped_column(ForeignKey("categorias.id"), nullable=False, index=True)
    fonte_renda_id: Mapped[int | None] = mapped_column(ForeignKey("fontes_renda.id"), nullable=True)
    regra_recorrencia_id: Mapped[int | None] = mapped_column(ForeignKey("regras_recorrencia.id"), nullable=True)

    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)
    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    data: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    conta: Mapped["Conta"] = relationship(back_populates="lancamentos")
    categoria: Mapped["Categoria"] = relationship(back_populates="lancamentos")
    fonte_renda: Mapped["FonteDeRenda"] = relationship(back_populates="lancamentos")
    regra_recorrencia: Mapped["RegraRecorrencia"] = relationship(back_populates="lancamentos_gerados")

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/regra_recorrencia.py' << 'ARQUIVO_FIM'
"""
RegraRecorrencia: template de um lançamento que se repete (ex: aluguel
todo dia 5). Usada tanto para lançamento automático quanto para
alimentar as projeções de saldo futuro (ADR 0005) — o service de projeção
usa estes dados para calcular lançamentos futuros "sob demanda", sem
precisar persistir todos eles com antecedência.
"""

from datetime import date

from sqlalchemy import Date, Enum, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import FrequenciaRecorrencia, TipoLancamento


class RegraRecorrencia(Base):
    __tablename__ = "regras_recorrencia"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), nullable=False, index=True)
    conta_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False)
    categoria_id: Mapped[int] = mapped_column(ForeignKey("categorias.id"), nullable=False)
    fonte_renda_id: Mapped[int | None] = mapped_column(ForeignKey("fontes_renda.id"), nullable=True)

    tipo: Mapped[TipoLancamento] = mapped_column(Enum(TipoLancamento), nullable=False)
    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    frequencia: Mapped[FrequenciaRecorrencia] = mapped_column(Enum(FrequenciaRecorrencia), nullable=False)
    # Para frequência mensal: dia do mês (1-28, evitando ambiguidade em
    # meses curtos). Para semanal: dia da semana (0=segunda ... 6=domingo).
    dia_referencia: Mapped[int] = mapped_column(nullable=False)

    data_inicio: Mapped[date] = mapped_column(Date, nullable=False)
    data_fim: Mapped[date | None] = mapped_column(Date, nullable=True)
    ativa: Mapped[bool] = mapped_column(default=True, server_default="true")

    usuario: Mapped["Usuario"] = relationship(back_populates="regras_recorrencia")
    lancamentos_gerados: Mapped[list["Lancamento"]] = relationship(back_populates="regra_recorrencia")

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/transferencia.py' << 'ARQUIVO_FIM'
"""
TransferenciaEntreContas: movimentação entre duas contas do MESMO
usuário (ex: separar parte do salário para uma conta de investimento).

Deliberadamente uma entidade separada de Lancamento (ver ADR 0004): ela
afeta o saldo das duas contas envolvidas, mas nunca aparece nos
relatórios de receita/despesa por categoria — não é um gasto, é dinheiro
que continua seu, só mudou de lugar.
"""

from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class TransferenciaEntreContas(Base):
    __tablename__ = "transferencias_entre_contas"

    id: Mapped[int] = mapped_column(primary_key=True)
    conta_origem_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)
    conta_destino_id: Mapped[int] = mapped_column(ForeignKey("contas.id"), nullable=False, index=True)

    valor: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    data: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    descricao: Mapped[str | None] = mapped_column(String(255), nullable=True)

    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    conta_origem: Mapped["Conta"] = relationship(
        back_populates="transferencias_enviadas", foreign_keys=[conta_origem_id]
    )
    conta_destino: Mapped["Conta"] = relationship(
        back_populates="transferencias_recebidas", foreign_keys=[conta_destino_id]
    )

ARQUIVO_FIM

mkdir -p 'app/models'
cat > 'app/models/usuario.py' << 'ARQUIVO_FIM'
"""
Usuario: cada usuário tem seus dados totalmente isolados (contas,
categorias, lançamentos, etc. sempre referenciam um usuario_id).

Como definido, não há cadastro público ainda (Etapa 7) — o(s) primeiro(s)
usuário(s) são criados via script (scripts/criar_usuario.py).
"""

from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[int] = mapped_column(primary_key=True)
    nome: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    senha_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    contas: Mapped[list["Conta"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    categorias: Mapped[list["Categoria"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    fontes_renda: Mapped[list["FonteDeRenda"]] = relationship(back_populates="usuario", cascade="all, delete-orphan")
    regras_recorrencia: Mapped[list["RegraRecorrencia"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )

ARQUIVO_FIM

mkdir -p 'app/services'
cat > 'app/services/auth_service.py' << 'ARQUIVO_FIM'
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

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/base.html' << 'ARQUIVO_FIM'
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{% block titulo %}Gestão Financeira{% endblock %}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/htmx.org@2.0.4"></script>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
    <main class="max-w-md mx-auto mt-16 px-4">
        {% block conteudo %}{% endblock %}
    </main>
</body>
</html>

ARQUIVO_FIM

mkdir -p 'app/templates'
cat > 'app/templates/login.html' << 'ARQUIVO_FIM'
{% extends "base.html" %}

{% block titulo %}Entrar — Gestão Financeira{% endblock %}

{% block conteudo %}
<h1 class="text-2xl font-semibold mb-6">Gestão Financeira Pessoal</h1>

{% if erro %}
<div class="bg-red-900/40 border border-red-700 text-red-200 text-sm rounded-md px-4 py-2 mb-4">
    {{ erro }}
</div>
{% endif %}

<form method="post" action="/login" class="space-y-4">
    <div>
        <label class="block text-sm mb-1" for="email">E-mail</label>
        <input class="w-full rounded-md bg-slate-900 border border-slate-700 px-3 py-2"
               type="email" name="email" id="email" required autofocus>
    </div>
    <div>
        <label class="block text-sm mb-1" for="senha">Senha</label>
        <input class="w-full rounded-md bg-slate-900 border border-slate-700 px-3 py-2"
               type="password" name="senha" id="senha" required>
    </div>
    <button type="submit"
            class="w-full rounded-md bg-emerald-600 hover:bg-emerald-500 transition-colors py-2 font-medium">
        Entrar
    </button>
</form>
{% endblock %}

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/auth.py' << 'ARQUIVO_FIM'
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

ARQUIVO_FIM

mkdir -p 'app/web'
cat > 'app/web/deps.py' << 'ARQUIVO_FIM'
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
    Dependency para proteger rotas que exigem login (Etapa 2 em diante).
    Lança 401 se não houver usuário autenticado na sessão.
    """
    if usuario is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Login necessário")
    return usuario

ARQUIVO_FIM

mkdir -p 'scripts'
cat > 'scripts/criar_usuario.py' << 'ARQUIVO_FIM'
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

ARQUIVO_FIM

mkdir -p 'tests/integration'
cat > 'tests/integration/test_health.py' << 'ARQUIVO_FIM'
"""
Testes de integração.

test_raiz_redireciona_sem_login: não depende do banco, roda sempre.
test_health_confirma_conexao_com_banco: precisa do Postgres do
docker-compose no ar e do .env configurado (SELECT 1 de verdade).
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_raiz_redireciona_para_login_sem_sessao():
    resposta = client.get("/", follow_redirects=False)
    assert resposta.status_code == 307
    assert resposta.headers["location"] == "/login"


def test_pagina_de_login_carrega():
    resposta = client.get("/login")
    assert resposta.status_code == 200
    assert "E-mail" in resposta.text


def test_health_confirma_conexao_com_banco():
    resposta = client.get("/health")
    assert resposta.status_code == 200
    assert resposta.json() == {"banco_de_dados": "conectado"}

ARQUIVO_FIM

echo "Arquivos criados. Fazendo commit..."
git add .
git commit -m "feat: adiciona models, Alembic e login (Etapa 1)"
echo "Commit feito. Rode: git push  (quando quiser enviar ao GitHub)"
