"""
Geração dos gráficos do dashboard como HTML (Plotly), prontos para
serem embutidos direto no template Jinja2 (sem precisar de um frontend
JS separado — mesma filosofia da Rota A definida no ADR 0002).
"""

import pandas as pd
import plotly.graph_objects as go

_LAYOUT_PADRAO = dict(
    template="plotly_dark",
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    margin=dict(l=10, r=10, t=10, b=10),
    height=300,
    font=dict(color="#cbd5e1"),
)


def grafico_gastos_por_categoria(df: pd.DataFrame) -> str:
    if df.empty:
        return ""
    figura = go.Figure(go.Bar(x=df["categoria"], y=df["valor"], marker_color="#fb7185"))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$")
    return figura.to_html(include_plotlyjs=False, full_html=False)


def grafico_evolucao_saldo(df: pd.DataFrame) -> str:
    if df.empty:
        return ""
    figura = go.Figure(go.Scatter(x=df["data"], y=df["saldo"], mode="lines", line=dict(color="#34d399", width=2)))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$")
    return figura.to_html(include_plotlyjs=False, full_html=False)


def grafico_projecao(df_historico: pd.DataFrame, df_projecao: pd.DataFrame) -> str:
    figura = go.Figure()
    if not df_historico.empty:
        figura.add_trace(go.Scatter(
            x=df_historico["data"], y=df_historico["saldo"], mode="lines",
            name="Histórico", line=dict(color="#34d399", width=2),
        ))
    if not df_projecao.empty:
        figura.add_trace(go.Scatter(
            x=df_projecao["data"], y=df_projecao["saldo"], mode="lines",
            name="Projeção", line=dict(color="#facc15", width=2, dash="dash"),
        ))
    figura.update_layout(**_LAYOUT_PADRAO, yaxis_title="R$", showlegend=True)
    return figura.to_html(include_plotlyjs=False, full_html=False)

