# 0001 — Formato do produto: aplicação web

## Contexto

O projeto tem dois objetivos simultâneos: ser uma peça de portfólio técnico
e ser uma ferramenta de uso diário real. Dois requisitos de uso diário eram
inegociáveis: (1) registrar despesas pelo celular, na hora, em qualquer
lugar; e (2) permitir que outras pessoas eventualmente usem a ferramenta
(cada uma com seus próprios dados isolados), o que implica compartilhar
acesso via link, sem exigir instalação.

## Alternativas consideradas

- **Aplicação desktop**: sem acesso pelo celular e sem forma prática de
  compartilhar com outras pessoas sem exigir instalação local.
- **Dashboard isolado (Streamlit/Dash)**: bom para visualização de dados,
  mas com experiência de formulário pobre no celular e pouca cara de
  "produto" para outras pessoas usarem.
- **Aplicação web responsiva**: cobre acesso multi-dispositivo nativamente
  e é acessível via URL, sem instalação.

## Decisão

Construir uma **aplicação web responsiva**, acessível por navegador tanto
no computador quanto no celular.

## Consequências

- Elimina a necessidade de manter um cliente desktop ou mobile nativo.
- Exige hospedagem em produção (custo e configuração de deploy), em vez de
  rodar só localmente.
- Abre caminho natural para, no futuro, expor uma API e permitir um
  cliente separado (ex: app mobile nativo ou frontend React), desde que a
  lógica de negócio seja desacoplada da camada de apresentação (ver ADR
  0002).
