"""Exceções de negócio compartilhadas entre os services."""


class ErroDeNegocio(Exception):
    """Violação de regra de negócio; a mensagem pode ser exibida ao usuário."""


class NaoEncontrado(ErroDeNegocio):
    pass

