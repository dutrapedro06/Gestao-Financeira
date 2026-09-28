# 0005 — Projeção de saldo futuro a partir de recorrências

## Contexto

Um dos objetivos do sistema é permitir antecipar a saúde financeira dos
próximos meses (ciclo de mês civil), não apenas olhar para o passado.
Já existem despesas e receitas recorrentes (`RegraRecorrencia`), usadas
para lançamento automático.

## Alternativas consideradas

- **Tratar recorrência e projeção como conceitos independentes**:
  recorrência apenas gera lançamentos automáticos; a projeção usaria outro
  cálculo (ex: média histórica de gastos). Mais simples, mas ignora
  informação já conhecida com certeza (ex: "sei que vou receber salário
  dia 5").
- **Recorrências alimentando diretamente a projeção**: a projeção de saldo
  futuro combina o saldo atual com os lançamentos futuros já conhecidos,
  derivados das regras de recorrência ativas.

## Decisão

A projeção de saldo futuro é calculada como:

```
saldo_projetado(data_futura) =
    saldo_atual
    + soma dos lançamentos futuros conhecidos (gerados por RegraRecorrencia)
      até data_futura
```

Os lançamentos futuros são calculados sob demanda pelo `service` de
projeção (não é necessário persistir no banco todos os lançamentos de
meses futuros com antecedência) — apenas os lançamentos já realizados e as
regras de recorrência ativas precisam existir no banco.

## Consequências

- A projeção fica mais precisa no curto/médio prazo, por incorporar
  compromissos financeiros já conhecidos, não apenas médias históricas.
- Abre espaço para, no futuro, combinar esse cálculo com modelos
  estatísticos mais sofisticados (ex: série temporal sobre gastos
  não-recorrentes), sem invalidar a base já construída.
