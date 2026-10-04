"""
Agregações para o dashboard, usando Pandas.

Ponto importante sobre "saldo geral": transferências entre contas do
mesmo usuário se cancelam (saem de uma, entram em outra), então o saldo
geral só depende de receitas e despesas — não precisa considerar
TransferenciaEntreContas aqui (diferente do saldo POR conta, calculado
em saldo_service.py).
"""

from datetime import date, timedelta
from decimal import Decimal

import pandas as pd
from sqlalchemy.orm import Session

from app.models import Conta, Lancamento
from app.models.enums import TipoLancamento


def _query_lancamentos(
    db: Session,
    usuario_id: int,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    categoria_id: int | None = None,
    fonte_id: int | None = None,
) -> list[Lancamento]:
    query = (
        db.query(Lancamento)
        .join(Conta, Lancamento.conta_id == Conta.id)
        .filter(Conta.usuario_id == usuario_id)
    )
    if data_inicio:
        query = query.filter(Lancamento.data >= data_inicio)
    if data_fim:
        query = query.filter(Lancamento.data <= data_fim)
    if categoria_id:
        query = query.filter(Lancamento.categoria_id == categoria_id)
    if fonte_id:
        query = query.filter(Lancamento.fonte_renda_id == fonte_id)
    return query.all()


def _para_dataframe(lancamentos: list[Lancamento]) -> pd.DataFrame:
    if not lancamentos:
        return pd.DataFrame(columns=["data", "tipo", "valor", "categoria"])
    return pd.DataFrame(
        [
            {
                "data": l.data,
                "tipo": l.tipo.value,
                "valor": float(l.valor),
                "categoria": l.categoria.nome,
            }
            for l in lancamentos
        ]
    )


def resumo_periodo(
    db: Session, usuario_id: int, data_inicio: date, data_fim: date,
    categoria_id: int | None = None, fonte_id: int | None = None,
) -> dict:
    lancamentos = _query_lancamentos(db, usuario_id, data_inicio, data_fim, categoria_id, fonte_id)
    df = _para_dataframe(lancamentos)

    total_receitas = float(df.loc[df["tipo"] == "receita", "valor"].sum()) if not df.empty else 0.0
    total_despesas = float(df.loc[df["tipo"] == "despesa", "valor"].sum()) if not df.empty else 0.0

    return {
        "lancamentos": lancamentos,
        "dataframe": df,
        "total_receitas": total_receitas,
        "total_despesas": total_despesas,
        "saldo_periodo": total_receitas - total_despesas,
    }


def gastos_por_categoria(df: pd.DataFrame) -> pd.DataFrame:
    despesas = df[df["tipo"] == "despesa"]
    if despesas.empty:
        return pd.DataFrame(columns=["categoria", "valor"])
    return (
        despesas.groupby("categoria", as_index=False)["valor"]
        .sum()
        .sort_values("valor", ascending=False)
    )


def saldo_geral_antes_de(db: Session, usuario_id: int, data: date) -> Decimal:
    """Saldo geral acumulado de tudo que aconteceu ANTES de 'data' (exclusive)."""
    lancamentos = _query_lancamentos(db, usuario_id, data_fim=data - timedelta(days=1))
    total = Decimal("0")
    for l in lancamentos:
        total += l.valor if l.tipo == TipoLancamento.RECEITA else -l.valor
    return total


def evolucao_saldo(
    db: Session, usuario_id: int, data_inicio: date, data_fim: date, saldo_inicial: Decimal
) -> pd.DataFrame:
    """Saldo geral acumulado dia a dia, começando de saldo_inicial."""
    lancamentos = _query_lancamentos(db, usuario_id, data_inicio, data_fim)
    df = _para_dataframe(lancamentos)

    dias = pd.date_range(data_inicio, data_fim, freq="D")
    if df.empty:
        variacao_diaria = pd.Series([0.0] * len(dias), index=dias)
    else:
        df["sinal"] = df["valor"] * df["tipo"].map({"receita": 1, "despesa": -1})
        diario = df.groupby("data")["sinal"].sum()
        diario.index = pd.to_datetime(diario.index)
        variacao_diaria = diario.reindex(dias, fill_value=0.0)

    saldo_acumulado = variacao_diaria.cumsum() + float(saldo_inicial)
    return pd.DataFrame({"data": dias, "saldo": saldo_acumulado.values})

