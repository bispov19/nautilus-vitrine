"""Orçamento de largura do modo Colunas: o NOME tem prioridade.

No modo Colunas a largura da janela é dividida em três partes:

    [colunas anteriores da Vitrine] [lista nativa: Nome | Tamanho | Modificado | ☆] ‖ [pré-visualização]

Antes, as colunas anteriores e o painel tinham largura fixa e a lista nativa ficava com
a sobra; dentro dela, Tamanho/Modificado/☆ também têm largura própria e o Nome recebia o
resto (às vezes só "…"). Aqui decidimos, a cada mudança de tamanho ou de pasta, quanto
cada parte recebe, cedendo espaço ao Nome nesta ordem:

  1. esconder as colunas secundárias da lista (Tamanho, Modificado, ☆);
  2. mostrar menos colunas anteriores (até 2; as outras continuam acessíveis rolando);
  3. estreitar o painel de pré-visualização até o mínimo;
  4. mostrar só 1 coluna anterior;
  5. recolher o painel (temporariamente: a preferência do usuário não muda).

Python puro (sem GTK): testado em tools/test_layout.py.
"""

from __future__ import annotations

from dataclasses import dataclass

NAME_MIN = 400          # lista nativa: margens (24+24) + ícone (~40) + ~310 px de texto
PREVIEW_MIN = 240       # menor largura útil do painel de pré-visualização
SECONDARY_DEFAULT = 300  # Tamanho + Modificado + ☆, quando não dá para medir
SEPARATOR = 1


@dataclass
class Plan:
    strip_columns: int       # quantas colunas anteriores ficam visíveis
    preview_width: int       # largura do painel (0 = recolhido)
    preview_auto_hidden: bool
    hide_secondary: bool
    name_width: int          # largura que sobra para a lista nativa (para o log/testes)


def plan(*, width: int, columns: int, column_width: int, max_visible: int,
         preview_on: bool, preview_width: int, secondary_width: int = SECONDARY_DEFAULT,
         prioritize: bool = True, auto_preview: bool = True,
         preview_forced: bool = False) -> Plan:
    """`width`: largura total de [colunas | lista ‖ painel].
    `preview_forced`: o usuário reabriu o painel à mão enquanto faltava espaço."""
    k = min(columns, max(1, max_visible)) if columns > 0 else 0
    pw = preview_width if preview_on else 0

    def strip(n):
        return n * (column_width + SEPARATOR) + (SEPARATOR if n else 0)

    def free(n, p):
        return width - strip(n) - p

    if not prioritize:
        return Plan(k, pw, False, False, free(k, pw))

    # 0. Cabe tudo, com as colunas secundárias?
    if free(k, pw) >= NAME_MIN + secondary_width:
        return Plan(k, pw, False, False, free(k, pw) - secondary_width)

    # 1. Esconde Tamanho/Modificado/☆.
    if free(k, pw) >= NAME_MIN:
        return Plan(k, pw, False, True, free(k, pw))

    # 2. Menos colunas anteriores (até 2).
    while k > 2 and free(k, pw) < NAME_MIN:
        k -= 1
    if free(k, pw) >= NAME_MIN:
        return Plan(k, pw, False, True, free(k, pw))

    # 3. Painel mais estreito (até o mínimo).
    if pw:
        need = NAME_MIN - free(k, pw)
        pw = max(min(PREVIEW_MIN, preview_width), pw - need)
        if free(k, pw) >= NAME_MIN:
            return Plan(k, pw, False, True, free(k, pw))

    # 4. Só 1 coluna anterior.
    while k > 1 and free(k, pw) < NAME_MIN:
        k -= 1
    if free(k, pw) >= NAME_MIN:
        return Plan(k, pw, False, True, free(k, pw))

    # 5. Recolhe o painel (se o usuário não o reabriu à mão).
    if pw and auto_preview and not preview_forced:
        return Plan(k, 0, True, True, free(k, 0))
    return Plan(k, pw, False, True, free(k, pw))
