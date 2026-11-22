"""Histórico de Voltar/Avançar que inclui o Meu computador.

O Meu computador é uma página que a Vitrine põe *por cima* da lista do Nautilus, então
o histórico nativo não sabe que ela existe. Este módulo guarda, para cada aba, um
histórico no estilo de um navegador em que o Meu computador é uma entrada como outra
qualquer, e diz o que fazer em cada Voltar/Avançar:

    entradas: [Pasta pessoal@0, Meu computador@0, Documentos@1]

O número depois do @ é a *profundidade* no histórico do Nautilus: quantos Voltar
nativos existem até aquele ponto. Uma entrada do Meu computador guarda a profundidade
da pasta que estava por baixo dela. Guardamos a profundidade (e não só a URI) porque a
mesma pasta pode aparecer várias vezes, e às vezes o Nautilus nem navegou (ex.: abrir a
pasta que já estava por baixo da página).

Regras:
  * Voltar/Avançar para o Meu computador: só mostra a página; o Nautilus fica parado.
  * Voltar/Avançar para uma pasta: diferença = profundidade_alvo - profundidade_atual.
    0 → só esconde a página; -n → n vezes `slot.back`; +n → n vezes `slot.forward`.
  * Qualquer outra mudança de local é navegação nova: apaga o "futuro" e acrescenta.

Python puro (sem GTK) para ser testado fora do Nautilus: tools/test_history.py.
"""

from __future__ import annotations

from dataclasses import dataclass

FOLDER = "folder"
COMPUTER = "computer"


@dataclass
class Entry:
    kind: str           # FOLDER ou COMPUTER
    uri: str | None     # pasta (None para o Meu computador)
    depth: int          # posição no histórico nativo do Nautilus

    def __repr__(self) -> str:  # facilita ler os testes e o log
        name = "MC" if self.kind == COMPUTER else (self.uri or "?").rstrip("/").rsplit("/", 1)[-1]
        return f"{name}@{self.depth}"


@dataclass
class Step:
    """O que o controlador da janela deve fazer depois de um Voltar/Avançar."""
    show_computer: bool   # mostrar (True) ou esconder (False) a página Meu computador
    native: int = 0       # passos nativos: negativo = slot.back, positivo = slot.forward


class History:
    def __init__(self) -> None:
        self.entries: list[Entry] = []
        self.idx = -1
        self.depth = 0            # profundidade atual do Nautilus (nossa cópia)
        self.pending = 0          # passos nativos que pedimos e ainda não chegaram
        self._undo_new = None     # estado antes da última "navegação nova" (plano B)

    # ── consultas ──
    def current(self) -> Entry | None:
        return self.entries[self.idx] if 0 <= self.idx < len(self.entries) else None

    def on_computer(self) -> bool:
        cur = self.current()
        return cur is not None and cur.kind == COMPUTER

    def busy(self) -> bool:
        return self.pending != 0

    def can_back(self) -> bool:
        return not self.busy() and self.idx > 0

    def can_forward(self) -> bool:
        return not self.busy() and self.idx < len(self.entries) - 1

    # ── eventos ──
    def _push(self, entry: Entry) -> None:
        del self.entries[self.idx + 1:]
        self.entries.append(entry)
        self.idx = len(self.entries) - 1

    def on_location(self, uri: str) -> str:
        """O Nautilus mudou de local (`notify::location`). Retorna o que aconteceu:

        "step"   – um passo nativo que nós pedimos (ainda faltam outros)
        "done"   – o último passo nativo que pedimos chegou
        "reload" – mesma pasta de novo (recarregar): nada muda
        "new"    – navegação nova (barra lateral, caminho, busca, clique numa pasta…)
        """
        self._undo_new = None
        if self.pending:
            self.depth += 1 if self.pending > 0 else -1
            self.pending += -1 if self.pending > 0 else 1
            if self.pending:
                return "step"
            cur = self.current()
            if cur is not None and cur.kind == FOLDER and cur.uri == uri:
                return "done"
            # Chegou num lugar inesperado: registra como navegação nova.
        cur = self.current()
        if cur is not None and cur.kind == FOLDER and cur.uri == uri:
            return "reload"
        self._undo_new = ([*self.entries], self.idx, self.depth)
        if cur is not None:
            self.depth += 1
        self._push(Entry(FOLDER, uri, self.depth))
        return "new"

    def open_computer(self) -> bool:
        """Abriu o Meu computador (barra lateral, Ctrl+Shift+C, menu). False se já estava."""
        if self.on_computer() or self.busy():
            return False
        self._undo_new = None
        self._push(Entry(COMPUTER, None, self.depth))
        return True

    def start_on_computer(self) -> None:
        """Janela aberta direto no Meu computador: ele é o primeiro lugar (Voltar desativado)."""
        self.entries = [Entry(COMPUTER, None, self.depth)]
        self.idx = 0
        self._undo_new = None

    def leave_computer_in_place(self, uri: str) -> None:
        """Saiu do Meu computador para a pasta que já estava por baixo (o Nautilus não
        navega, então não haverá `notify::location`)."""
        if not self.on_computer():
            return
        self._undo_new = None
        self._push(Entry(FOLDER, uri, self.depth))

    def back(self) -> Step | None:
        return self._go(-1)

    def forward(self) -> Step | None:
        return self._go(+1)

    def _go(self, delta: int) -> Step | None:
        if not (self.can_back() if delta < 0 else self.can_forward()):
            return None
        self.idx += delta
        target = self.entries[self.idx]
        self._undo_new = None
        if target.kind == COMPUTER:
            return Step(show_computer=True)
        self.pending = target.depth - self.depth
        return Step(show_computer=False, native=self.pending)

    def cancel_pending(self) -> None:
        """O Nautilus não respondeu a um passo pedido (ex.: pasta inacessível)."""
        self.pending = 0

    def native_went_back(self, uri: str) -> bool:
        """Plano B: a última "navegação nova" era na verdade um Voltar do próprio Nautilus
        que não passou por nós (ex.: menu de histórico do botão ←). Sabemos disso porque,
        depois de uma navegação nova, o Avançar nativo fica sempre desativado.

        Desfaz o acréscimo e realinha com a entrada anterior de mesma URI."""
        if self._undo_new is None:
            return False
        entries, idx, _depth = self._undo_new
        self._undo_new = None
        for j in range(idx - 1, -1, -1):
            e = entries[j]
            if e.kind == FOLDER and e.uri == uri:
                self.entries, self.idx, self.depth = entries, j, e.depth
                return True
        return False
