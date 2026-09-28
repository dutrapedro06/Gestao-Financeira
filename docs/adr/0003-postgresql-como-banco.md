# 0003 — PostgreSQL como banco de dados

## Contexto

O sistema precisa persistir dados financeiros de forma confiável, e a
decisão de arquitetura (ADR 0001) já prevê acesso remoto, multi-dispositivo,
e a possibilidade futura de múltiplos usuários (isolados) acessando a
mesma aplicação hospedada.

## Alternativas consideradas

- **SQLite**: simples de configurar, arquivo único, ótimo para
  desenvolvimento local isolado. Porém não é adequado para acesso
  concorrente remoto por múltiplos usuários/dispositivos, o que
  compromete tanto o uso via celular + computador simultaneamente quanto
  a evolução para múltiplos usuários.
- **PostgreSQL**: banco relacional robusto, com suporte maduro a acesso
  concorrente, amplamente utilizado em produção, com boa oferta de
  hospedagem gratuita/barata para projetos pessoais.

## Decisão

Usar **PostgreSQL**, com **SQLAlchemy** como ORM e **Alembic** para
controle de versão do schema do banco.

## Consequências

- Exige subir um serviço de banco (via Docker em desenvolvimento, e um
  provedor gerenciado em produção), em vez de um simples arquivo local.
- Ganha-se robustez para o cenário real de uso (multi-dispositivo, futuro
  multiusuário) e uma peça de portfólio mais alinhada ao que se usa em
  ambientes profissionais.
- O versionamento do schema via Alembic passa a ser parte do fluxo de
  desenvolvimento desde a primeira migração.
