# 0002 — Stack web: FastAPI + Jinja2 + HTMX

## Contexto

Definido o formato (ADR 0001), era preciso escolher como implementar a
camada web em Python. O maior risco identificado para o projeto não era
técnico, e sim comportamental: se o MVP demorar demais para ficar
utilizável no dia a dia, o hábito de uso não se forma.

## Alternativas consideradas

- **Rota A — Stack enxuta**: FastAPI (API) + Jinja2 (templates) + HTMX
  (interatividade parcial de tela) + Tailwind CSS. Um único repositório
  Python, sem frontend JavaScript separado.
- **Rota B — Full stack separado**: FastAPI expondo apenas uma API JSON,
  consumida por um frontend React (ou React Native/Expo) independente.
  Mais próximo do padrão de mercado "backend + frontend separados", e
  abre caminho direto para um PWA instalável.

Ambas as rotas usam FastAPI no backend e PostgreSQL como banco — a
diferença está inteiramente na camada de apresentação.

## Decisão

Seguir com a **Rota A** (FastAPI + Jinja2 + HTMX + Tailwind) para entregar
o MVP mais rápido, com a lógica de negócio desacoplada da apresentação
(camada `services/`, ver ADR sobre arquitetura em camadas), de modo que uma
eventual migração futura para um frontend React possa reaproveitar toda a
regra de negócio já implementada, adicionando apenas uma nova camada
`api/` mais completa.

## Consequências

- MVP mais rápido de entregar: uma linguagem de fato (Python), sem
  duplicar validação entre backend e frontend.
- Menor "vitrine" de tecnologias frontend no portfólio hoje — mitigado
  pelo fato de a API já ser desenhada pensando em expor JSON no futuro.
- Se a experiência mobile precisar evoluir para algo mais rico (PWA
  instalável, notificações), será necessária uma migração de frontend
  mais adiante — decisão consciente, não um acidente de arquitetura.
