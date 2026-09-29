"""
Regras de negócio das recorrências: CRUD da regra e geração automática
dos lançamentos já vencidos (ADR 0005 — só o passado é persistido; a
projeção de datas futuras é calculada sob demanda, na Etapa 5).
"""

from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models import Categoria, Conta, FonteDeRenda, Lancamento, RegraRecorrencia
from app.models.enums import FrequenciaRecorrencia, TipoLancamento
from app.repositories.regras_recorrencia import regras_recorrencia as repo
from app.services.erros import ErroDeNegocio, NaoEncontrado
from app.services.ocorrencias import ocorrencias_ate

TAMANHO_MAXIMO_DESCRICAO = 255

LIMITES_DIA_REFERENCIA = {
    FrequenciaRecorrencia.MENSAL: (1, 28),
    FrequenciaRecorrencia.SEMANAL: (0, 6),
}


def _tipo(valor: str | None) -> TipoLancamento:
    try:
        return TipoLancamento(valor)
    except ValueError:
        raise ErroDeNegocio("Tipo inválido.") from None


def _frequencia(valor: str | None) -> FrequenciaRecorrencia:
    try:
        return FrequenciaRecorrencia(valor)
    except ValueError:
        raise ErroDeNegocio("Frequência inválida.") from None


def _valor_monetario(valor: str | None) -> Decimal:
    try:
        numero = Decimal(str(valor).replace(",", "."))
    except (InvalidOperation, AttributeError):
        raise ErroDeNegocio("Valor inválido.") from None
    if numero <= 0:
        raise ErroDeNegocio("O valor deve ser maior que zero.")
    return numero


def _data(valor: str | None, campo: str = "Data") -> date:
    try:
        return date.fromisoformat(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio(f"{campo} inválida.") from None


def _dia_referencia(valor: str | None, frequencia: FrequenciaRecorrencia) -> int:
    try:
        numero = int(valor)
    except (TypeError, ValueError):
        raise ErroDeNegocio("Dia de referência inválido.") from None
    minimo, maximo = LIMITES_DIA_REFERENCIA[frequencia]
    if not (minimo <= numero <= maximo):
        raise ErroDeNegocio(f"Para essa frequência, o dia de referência deve estar entre {minimo} e {maximo}.")
    return numero


def _conta_do_usuario(db: Session, usuario_id: int, conta_id: int) -> Conta:
    conta = db.query(Conta).filter(Conta.id == conta_id, Conta.usuario_id == usuario_id).first()
    if conta is None:
        raise ErroDeNegocio("Conta inválida.")
    return conta


def _categoria_do_usuario(db: Session, usuario_id: int, categoria_id: int, tipo: TipoLancamento) -> Categoria:
    categoria = (
        db.query(Categoria).filter(Categoria.id == categoria_id, Categoria.usuario_id == usuario_id).first()
    )
    if categoria is None:
        raise ErroDeNegocio("Categoria inválida.")
    if categoria.tipo != tipo:
        raise ErroDeNegocio(
            f"A categoria '{categoria.nome}' é de {categoria.tipo.value}, "
            f"não pode ser usada numa recorrência de {tipo.value}."
        )
    return categoria


def _fonte_renda_do_usuario(db: Session, usuario_id: int, fonte_renda_id: int | None) -> FonteDeRenda | None:
    if not fonte_renda_id:
        return None
    fonte = (
        db.query(FonteDeRenda)
        .filter(FonteDeRenda.id == fonte_renda_id, FonteDeRenda.usuario_id == usuario_id)
        .first()
    )
    if fonte is None:
        raise ErroDeNegocio("Fonte de renda inválida.")
    return fonte


class ServicoRecorrencias:
    def listar(self, db: Session, usuario_id: int) -> list[RegraRecorrencia]:
        return repo.listar(db, usuario_id)

    def obter(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia:
        regra = repo.obter(db, usuario_id, regra_id)
        if regra is None:
            raise NaoEncontrado("Recorrência não encontrada.")
        return regra

    def criar(self, db: Session, usuario_id: int, **campos) -> RegraRecorrencia:
        dados = self._validar(db, usuario_id, **campos)
        return repo.adicionar(db, RegraRecorrencia(usuario_id=usuario_id, **dados))

    def atualizar(self, db: Session, usuario_id: int, regra_id: int, **campos) -> RegraRecorrencia:
        regra = self.obter(db, usuario_id, regra_id)
        dados = self._validar(db, usuario_id, **campos)
        for campo, valor in dados.items():
            setattr(regra, campo, valor)
        return repo.salvar(db, regra)

    def alternar_ativa(self, db: Session, usuario_id: int, regra_id: int) -> RegraRecorrencia:
        regra = self.obter(db, usuario_id, regra_id)
        regra.ativa = not regra.ativa
        return repo.salvar(db, regra)

    def excluir(self, db: Session, usuario_id: int, regra_id: int) -> None:
        regra = self.obter(db, usuario_id, regra_id)
        # Os lançamentos já gerados continuam no histórico — só perdem o
        # vínculo com a regra (que deixou de existir), nunca são apagados.
        db.query(Lancamento).filter(Lancamento.regra_recorrencia_id == regra.id).update(
            {"regra_recorrencia_id": None}
        )
        repo.remover(db, regra)

    def _validar(
        self, db: Session, usuario_id: int, *,
        tipo: str, conta_id: int, categoria_id: int, valor: str,
        frequencia: str, dia_referencia: str, data_inicio: str,
        fonte_renda_id: int | None = None, data_fim: str | None = None, descricao: str | None = None,
    ) -> dict:
        tipo_validado = _tipo(tipo)
        frequencia_validada = _frequencia(frequencia)
        conta = _conta_do_usuario(db, usuario_id, conta_id)
        categoria = _categoria_do_usuario(db, usuario_id, categoria_id, tipo_validado)
        fonte = (
            _fonte_renda_do_usuario(db, usuario_id, fonte_renda_id)
            if tipo_validado == TipoLancamento.RECEITA
            else None
        )
        data_inicio_validada = _data(data_inicio, "Data de início")
        data_fim_validada = _data(data_fim, "Data de fim") if data_fim else None
        if data_fim_validada and data_fim_validada < data_inicio_validada:
            raise ErroDeNegocio("A data de fim não pode ser anterior à data de início.")

        return {
            "tipo": tipo_validado,
            "conta_id": conta.id,
            "categoria_id": categoria.id,
            "fonte_renda_id": fonte.id if fonte else None,
            "valor": _valor_monetario(valor),
            "frequencia": frequencia_validada,
            "dia_referencia": _dia_referencia(dia_referencia, frequencia_validada),
            "data_inicio": data_inicio_validada,
            "data_fim": data_fim_validada,
            "descricao": (descricao or "").strip()[:TAMANHO_MAXIMO_DESCRICAO] or None,
        }


def gerar_lancamentos_pendentes(db: Session, usuario_id: int, ate: date | None = None) -> int:
    """
    Materializa, como Lancamento de verdade, toda ocorrência vencida das
    regras ativas do usuário que ainda não tenha sido gerada. Chamado
    automaticamente ao abrir a tela de lançamentos — sem exigir nenhuma
    ação manual nem um agendador externo.
    """
    ate = ate or date.today()
    total_criados = 0

    for regra in repo.listar_ativas(db, usuario_id):
        datas_pendentes = ocorrencias_ate(regra, ate)
        if not datas_pendentes:
            continue

        datas_ja_geradas = {
            linha[0]
            for linha in db.query(Lancamento.data).filter(Lancamento.regra_recorrencia_id == regra.id).all()
        }

        for data_ocorrencia in datas_pendentes:
            if data_ocorrencia in datas_ja_geradas:
                continue
            db.add(Lancamento(
                conta_id=regra.conta_id,
                categoria_id=regra.categoria_id,
                fonte_renda_id=regra.fonte_renda_id,
                regra_recorrencia_id=regra.id,
                tipo=regra.tipo,
                valor=regra.valor,
                data=data_ocorrencia,
                descricao=regra.descricao,
            ))
            total_criados += 1

    if total_criados:
        db.commit()
    return total_criados


servico_recorrencias = ServicoRecorrencias()

