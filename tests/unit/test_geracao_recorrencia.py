"""Testes do CRUD de recorrências e da geração automática de lançamentos."""

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models import Lancamento, Usuario
from app.services.cadastros import servico_categorias, servico_contas
from app.services.erros import ErroDeNegocio
from app.services.regras_recorrencia import gerar_lancamentos_pendentes, servico_recorrencias


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    sessao = sessionmaker(bind=engine)()
    yield sessao
    sessao.close()


@pytest.fixture()
def usuario(db):
    u = Usuario(nome="Teste", email="teste@example.com", senha_hash="x")
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def cenario(db, usuario):
    conta = servico_contas.criar(db, usuario.id, "Conta Corrente")
    categoria = servico_categorias.criar(db, usuario.id, "Aluguel", tipo="despesa")
    return {"conta": conta, "categoria": categoria}


def _criar_regra_aluguel(db, usuario_id, cenario, **override):
    campos = dict(
        tipo="despesa", conta_id=cenario["conta"].id, categoria_id=cenario["categoria"].id,
        valor="1200", frequencia="mensal", dia_referencia="5",
        data_inicio=date(2026, 1, 5).isoformat(),
    )
    campos.update(override)
    return servico_recorrencias.criar(db, usuario_id, **campos)


def test_categoria_de_tipo_errado_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(db, usuario.id, cenario, tipo="receita")


def test_dia_referencia_fora_do_intervalo_mensal_e_rejeitado(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(db, usuario.id, cenario, dia_referencia="31")


def test_data_fim_antes_do_inicio_e_rejeitada(db, usuario, cenario):
    with pytest.raises(ErroDeNegocio):
        _criar_regra_aluguel(
            db, usuario.id, cenario,
            data_inicio=date(2026, 3, 1).isoformat(), data_fim=date(2026, 1, 1).isoformat(),
        )


def test_gera_lancamentos_pendentes_ate_hoje(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    criados = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados == 4  # jan, fev, mar, abr

    lancamentos = db.query(Lancamento).order_by(Lancamento.data).all()
    assert [l.data for l in lancamentos] == [
        date(2026, 1, 5), date(2026, 2, 5), date(2026, 3, 5), date(2026, 4, 5),
    ]
    assert all(l.valor == 1200 for l in lancamentos)
    assert all(l.regra_recorrencia_id is not None for l in lancamentos)


def test_gerar_duas_vezes_nao_duplica(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 3, 5))
    criados_na_segunda_vez = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 3, 5))

    assert criados_na_segunda_vez == 0
    assert db.query(Lancamento).count() == 3


def test_gerar_avancando_o_tempo_so_cria_o_que_falta(db, usuario, cenario):
    _criar_regra_aluguel(db, usuario.id, cenario)

    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 2, 5))
    assert db.query(Lancamento).count() == 2

    criados_depois = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados_depois == 2  # só março e abril, que ainda não existiam
    assert db.query(Lancamento).count() == 4


def test_regra_inativa_nao_gera_lancamentos(db, usuario, cenario):
    regra = _criar_regra_aluguel(db, usuario.id, cenario)
    servico_recorrencias.alternar_ativa(db, usuario.id, regra.id)  # desativa

    criados = gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 4, 5))
    assert criados == 0


def test_excluir_regra_preserva_lancamentos_ja_gerados(db, usuario, cenario):
    regra = _criar_regra_aluguel(db, usuario.id, cenario)
    gerar_lancamentos_pendentes(db, usuario.id, ate=date(2026, 2, 5))

    servico_recorrencias.excluir(db, usuario.id, regra.id)

    lancamentos = db.query(Lancamento).all()
    assert len(lancamentos) == 2
    assert all(l.regra_recorrencia_id is None for l in lancamentos)

