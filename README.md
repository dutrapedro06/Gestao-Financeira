# Gestão Financeira Pessoal

Sistema web para controle financeiro pessoal, construído em Python, pensado para ser usado no dia a dia — não apenas uma demonstração de portfólio.

## Índice

- [Sobre o projeto](#sobre-o-projeto)
- [Funcionalidades](#funcionalidades)
- [Stack tecnológica](#stack-tecnológica)
- [Arquitetura](#arquitetura)
- [Modelo de dados](#modelo-de-dados)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Como rodar localmente](#como-rodar-localmente)
- [Decisões técnicas](#decisões-técnicas)
- [Roadmap](#roadmap)
- [Licença](#licença)

## Sobre o projeto

Este projeto nasceu de uma necessidade dupla: eu precisava de uma ferramenta de verdade para organizar minhas finanças pessoais no dia a dia, e queria construir algo que demonstrasse, de forma concreta, minha capacidade de projetar e desenvolver um sistema completo — do modelo de dados à experiência do usuário.

Em vez de criar mais um projeto de portfólio genérico, o objetivo aqui foi tratar este como um produto real: algo que eu efetivamente uso, que resolve um problema concreto e que foi desenhado com as mesmas preocupações de um sistema em produção — persistência confiável, segurança dos dados, experiência de uso pensada para uso frequente, e uma arquitetura que permite evolução.

Uma decisão central de design foi priorizar a **velocidade de uso no dia a dia**: o maior risco de uma ferramenta financeira pessoal não é técnico, é comportamental — se registrar uma despesa exige fricção, o hábito não se sustenta. Por isso, o sistema foi desenhado como uma aplicação web acessível tanto do computador quanto do celular, sem exigir instalação.

## Funcionalidades

**Núcleo (MVP)**
- Registro de receitas e despesas, organizadas por categoria e por fonte
- Múltiplas contas (ex: conta corrente, vale-refeição, reserva) com saldo independente
- Transferências entre contas, sem contaminar os relatórios de gastos por categoria
- Despesas e receitas recorrentes, com lançamento automático
- Projeções de saldo futuro, considerando saldo atual + recorrências conhecidas
- Dashboard interativo com filtros por período, categoria e fonte
- Histórico completo de movimentações

**Planejadas**
- Categorização semi-automática de despesas por regras (evolutível para ML)
- Exportação de relatórios (CSV/PDF)
- Alertas de orçamento por categoria
- Cadastro público, permitindo que outras pessoas criem suas próprias contas isoladas

## Stack tecnológica

| Camada | Tecnologia | Motivo |
|---|---|---|
| Backend | [FastAPI](https://fastapi.tiangolo.com/) | Performance, tipagem forte, permite servir tanto HTML quanto API JSON |
| Validação de dados | Pydantic | Schemas tipados, reutilizados entre rotas HTML e API |
| Templates / UI | Jinja2 + [HTMX](https://htmx.org/) + Tailwind CSS | Interatividade moderna sem exigir um frontend JavaScript completo |
| Banco de dados | PostgreSQL | Robustez para acesso concorrente e hospedagem remota |
| ORM | SQLAlchemy | Mapeamento objeto-relacional, padrão do ecossistema FastAPI |
| Migrações | Alembic | Versionamento do schema do banco como código |
| Análise de dados | Pandas | Agregações (saldo, gastos por categoria, projeções) |
| Visualização | Plotly | Gráficos interativos embutidos nas páginas |
| Autenticação | bcrypt + sessão via cookie | Simples e adequado ao porte do projeto, sem exigir OAuth completo |

## Arquitetura

O projeto segue uma separação em camadas, isolando a lógica de negócio da forma como ela é exposta:

```
Rotas (web/ e api/)
        ↓
   Services (regras de negócio: saldo, recorrência, projeção)
        ↓
  Repositories (acesso ao banco de dados)
        ↓
     Models (entidades SQLAlchemy)
```

A camada de `services/` não sabe se quem a chama é uma rota HTML ou uma rota JSON — isso é o que permite, no futuro, evoluir para um frontend separado (ex: React ou um app mobile) reaproveitando toda a lógica de negócio já existente, sem reescrevê-la.

## Modelo de dados

**Entidades principais:**

- **Usuario** — cada usuário tem seus dados totalmente isolados
- **Conta** — carteiras/contas do usuário (ex: conta corrente, vale, investimento); saldo calculado a partir dos lançamentos, nunca armazenado como valor fixo
- **Categoria** — classificação de receitas e despesas
- **FonteDeRenda** — origem das receitas (ex: salário, freelance)
- **Lancamento** — receita ou despesa individual, vinculada a uma conta e categoria
- **RegraRecorrencia** — define a frequência de lançamentos automáticos (ex: mensal), usada tanto para lançar quanto para projetar saldo futuro
- **TransferenciaEntreContas** — movimentação entre contas do mesmo usuário (ex: separar parte do salário para investir), sem impacto nos relatórios de gasto por categoria

```
Usuario 1──N Conta 1──N Lancamento N──1 Categoria
Usuario 1──N Categoria         Lancamento N──1 FonteDeRenda (opcional)
Usuario 1──N FonteDeRenda      Lancamento N──1 RegraRecorrencia (opcional)
Conta 1──N TransferenciaEntreContas N──1 Conta
```

## Estrutura do repositório

```
gestao-financeira/
├── app/
│   ├── main.py            # cria a app FastAPI, registra rotas
│   ├── config.py          # leitura de variáveis de ambiente
│   ├── database.py        # engine/sessão SQLAlchemy
│   ├── models/             # entidades do banco
│   ├── schemas/            # validação/serialização (Pydantic)
│   ├── repositories/       # acesso ao banco de dados
│   ├── services/           # regras de negócio
│   ├── api/                # rotas JSON
│   ├── web/                # rotas HTML (Jinja2 + HTMX)
│   ├── templates/
│   └── static/
├── alembic/                # migrações do banco
├── tests/
│   ├── unit/                # testes de services
│   └── integration/         # testes de rotas
├── scripts/
│   └── backup_db.sh         # dump periódico do banco
├── docs/
│   └── adr/                 # registros das decisões de arquitetura
├── .env.example
├── docker-compose.yml        # Postgres local para desenvolvimento
├── requirements.txt
└── README.md
```

## Como rodar localmente

> Pré-requisitos: Python 3.11+, Docker (para o Postgres local)

```bash
# 1. Clonar o repositório
git clone https://github.com/<seu-usuario>/gestao-financeira.git
cd gestao-financeira

# 2. Criar e ativar um ambiente virtual
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 3. Instalar as dependências
pip install -r requirements.txt

# 4. Configurar variáveis de ambiente
cp .env.example .env
# edite o .env com suas configurações (string de conexão do banco, etc.)

# 5. Subir o banco de dados local
docker-compose up -d

# 6. Rodar as migrações
alembic upgrade head

# 7. Iniciar a aplicação
uvicorn app.main:app --reload
```

A aplicação estará disponível em `http://localhost:8000`.

## Decisões técnicas

As principais decisões de arquitetura — formato do produto, escolha de stack, modelagem de contas e transferências, estratégia de projeção — estão documentadas em [`docs/adr/`](docs/adr/), no formato de Architecture Decision Records, incluindo o contexto, as alternativas consideradas e as consequências de cada escolha.

## Roadmap

- [x] Definição de requisitos, arquitetura e modelo de dados
- [ ] CRUD de contas, categorias e lançamentos
- [ ] Transferências entre contas
- [ ] Recorrências automáticas
- [ ] Dashboard interativo com filtros
- [ ] Projeções de saldo futuro
- [ ] Testes automatizados e deploy em produção
- [ ] Cadastro público de novos usuários
- [ ] Categorização semi-automática e exportação de relatórios

## Licença

Este projeto está sob a licença MIT — veja o arquivo [LICENSE](LICENSE) para mais detalhes.
