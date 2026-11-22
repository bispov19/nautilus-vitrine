"""Testes do histórico de Voltar/Avançar com o Meu computador (sem GTK, sem Nautilus).

    python3 tools/test_history.py

`FakeSlot` imita o histórico nativo de uma aba do Nautilus: lista de voltar, lista de
avançar, e nenhum `notify::location` quando se abre a pasta que já está aberta.
`Tab` faz o mesmo papel do WindowController (window.py): liga os dois.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from vitrine.history import History  # noqa: E402

H = "file:///home/u"
IMG = H + "/Imagens"
DOC = H + "/Documentos"
FER = IMG + "/Ferias"


class FakeSlot:
    def __init__(self, start: str, on_location) -> None:
        self.location = start
        self.back_list: list[str] = []
        self.fwd_list: list[str] = []
        self.on_location = on_location

    def open(self, uri: str) -> None:
        if uri == self.location:
            return  # o Nautilus não navega
        self.back_list.append(self.location)
        self.fwd_list.clear()
        self._set(uri)

    def back(self) -> None:
        assert self.back_list, "Voltar nativo sem histórico"
        self.fwd_list.append(self.location)
        self._set(self.back_list.pop())

    def forward(self) -> None:
        assert self.fwd_list, "Avançar nativo sem histórico"
        self.back_list.append(self.location)
        self._set(self.fwd_list.pop())

    def _set(self, uri: str) -> None:
        self.location = uri
        self.on_location(uri)


class Tab:
    """Mesma cola que window.py faz entre History e o slot."""

    def __init__(self, start: str = H, start_on_computer: bool = False) -> None:
        self.h = History()
        self.computer = False
        self.slot = FakeSlot(start, self._on_location)
        self._on_location(start)
        if start_on_computer:
            self.h.start_on_computer()
            self.computer = True

    def _native(self, sign: int) -> None:
        self.slot.back() if sign < 0 else self.slot.forward()

    def _on_location(self, uri: str) -> None:
        result = self.h.on_location(uri)
        if result == "step":
            self._native(self.h.pending)
            return
        self.computer = False
        if result == "new" and self.slot.fwd_list:  # plano B (window.py checa o botão →)
            self.h.native_went_back(uri)

    # ações do usuário
    def sidebar_computer(self):
        if self.h.open_computer():
            self.computer = True

    def open(self, uri: str):
        """Abrir uma pasta (barra lateral, item da página, duplo clique…)."""
        if self.computer and uri == self.slot.location:
            self.h.leave_computer_in_place(uri)
            self.computer = False
        else:
            self.slot.open(uri)

    def back(self):
        self._go(self.h.back())

    def forward(self):
        self._go(self.h.forward())

    def _go(self, step):
        assert step is not None, "botão deveria estar desativado"
        self.computer = step.show_computer
        if step.native:
            self._native(step.native)

    def where(self) -> str:
        return "MC" if self.computer else self.slot.location


def check(name, got, want):
    ok = got == want
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + ("" if ok else f"  (veio {got!r}, esperado {want!r})"))
    return ok


def run() -> bool:
    results = []

    # 1. Abre no MC → Imagens → Voltar → MC ; Avançar → Imagens
    t = Tab(start_on_computer=True)
    results.append(check("começa no MC com Voltar desativado", (t.where(), t.h.can_back()), ("MC", False)))
    t.open(IMG)
    t.back()
    results.append(check("MC → Imagens → Voltar = MC", t.where(), "MC"))
    results.append(check("…e o Voltar fica desativado de novo", t.h.can_back(), False))
    results.append(check("…com a lista nativa ainda em Imagens", t.slot.location, IMG))
    t.forward()
    results.append(check("…Avançar = Imagens", t.where(), IMG))

    # 2. Pasta pessoal → MC → Documentos → Voltar → MC → Voltar → Pasta pessoal
    t = Tab()
    t.sidebar_computer()
    t.open(DOC)
    t.back()
    results.append(check("PP → MC → Doc → Voltar = MC", t.where(), "MC"))
    t.back()
    results.append(check("…Voltar = Pasta pessoal", t.where(), H))
    results.append(check("…e não há mais para onde voltar", t.h.can_back(), False))
    t.forward()
    t.forward()
    results.append(check("…Avançar, Avançar = MC, Documentos", t.where(), DOC))

    # 3. MC → Imagens → Férias → Voltar → Imagens → Voltar → MC
    t = Tab(start_on_computer=True)
    t.open(IMG)
    t.open(FER)
    t.back()
    results.append(check("MC → Img → Férias → Voltar = Imagens", t.where(), IMG))
    t.back()
    results.append(check("…Voltar = MC", t.where(), "MC"))

    # 4. A mesma pasta que estava por baixo (o Nautilus não navega)
    t = Tab()
    t.sidebar_computer()
    t.open(H)                 # clica na Pasta pessoal dentro do MC
    t.back()
    results.append(check("PP → MC → PP (sem navegar) → Voltar = MC", t.where(), "MC"))
    t.back()
    results.append(check("…Voltar = PP, sem Voltar nativo", (t.where(), t.slot.back_list), (H, [])))

    # 5. Diferença de mais de um passo: PP → MC → Doc, Voltar (MC), clica Imagens
    t = Tab()
    t.sidebar_computer()
    t.open(DOC)
    t.back()                  # MC por cima de Documentos
    t.open(IMG)               # navegação nova a partir de Documentos
    t.back()
    results.append(check("…Voltar = MC", t.where(), "MC"))
    t.back()                  # PP está 2 passos nativos atrás (Img → Doc → PP)
    results.append(check("…Voltar = PP (2 passos nativos encadeados)", t.where(), H))

    # 6. Abas independentes
    a, b = Tab(), Tab()
    a.sidebar_computer()
    results.append(check("MC numa aba não afeta a outra", (a.where(), b.where(), b.h.can_back()),
                         ("MC", H, False)))

    # 7. Recarregar não cria entrada
    t = Tab()
    t.open(DOC)
    t._on_location(DOC)
    results.append(check("recarregar não cria entrada", len(t.h.entries), 2))

    # 8. Plano B: o Nautilus voltou sem passar por nós (menu de histórico do ←)
    t = Tab(start_on_computer=True)
    t.open(IMG)
    t.open(FER)
    t.slot.back()             # Voltar nativo "escondido"
    results.append(check("plano B: realinha em Imagens", (t.where(), t.h.idx), (IMG, 1)))
    t.back()
    results.append(check("…e o Voltar seguinte ainda cai no MC", t.where(), "MC"))

    # 9. Navegar para outro lugar fecha o MC e apaga o futuro
    t = Tab()
    t.sidebar_computer()
    t.open(DOC)
    t.back()
    t.back()                  # PP; futuro = [MC, Doc]
    t.open(IMG)
    results.append(check("navegação nova apaga o Avançar", t.h.can_forward(), False))

    print(f"\n{sum(results)}/{len(results)} verificações passaram")
    return all(results)


if __name__ == "__main__":
    sys.exit(0 if run() else 1)
