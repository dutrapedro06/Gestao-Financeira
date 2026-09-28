# 0004 — Saldos por conta e transferências entre contas

## Contexto

O uso real esperado envolve múltiplas fontes de dinheiro com propósitos
diferentes (ex: conta corrente do salário, vale-refeição, conta de
investimento), com necessidade de mover valores entre elas (ex: separar
parte do salário para investir) sem que isso seja contabilizado como uma
despesa nos relatórios por categoria.

## Alternativas consideradas

- **Modelar a movimentação como um Lançamento comum** (despesa na conta de
  origem, receita na conta de destino): mais simples de implementar, mas
  contamina os relatórios de gasto por categoria com valores que não são,
  de fato, gastos.
- **Criar uma entidade dedicada `TransferenciaEntreContas`**, separada de
  `Lancamento`, explicitamente excluída dos relatórios de receita/despesa
  por categoria.

## Decisão

Criar a entidade **TransferenciaEntreContas** (conta de origem, conta de
destino, valor, data, descrição opcional), afetando o saldo de ambas as
contas envolvidas, mas nunca aparecendo nos relatórios de gasto/receita
por categoria.

O saldo de cada `Conta` não é armazenado como um valor fixo — é sempre
calculado a partir do histórico de `Lancamento` e `TransferenciaEntreContas`
associados a ela, para evitar que o saldo exibido fique dessincronizado do
histórico real de movimentações.

## Consequências

- Relatórios por categoria continuam representando fielmente gastos e
  receitas reais, sem ruído de movimentações internas.
- O cálculo de saldo de uma conta precisa considerar duas fontes
  (lançamentos e transferências), o que é resolvido na camada `services/`,
  mantendo essa complexidade fora das rotas e dos templates.
