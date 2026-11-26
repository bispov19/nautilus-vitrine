"""Testes do orçamento de largura do modo Colunas (sem GTK).

    python3 tools/test_layout.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from vitrine.layout import NAME_MIN, PREVIEW_MIN, plan  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + ("" if ok else f"  ({detail})"))


base = dict(column_width=230, max_visible=3, preview_width=320)

p = plan(width=2000, columns=3, preview_on=True, **base)
check("janela grande: tudo aparece", p.strip_columns == 3 and p.preview_width == 320
      and not p.hide_secondary and p.name_width >= NAME_MIN, p)

# o caso da captura: 3 colunas + painel numa área de ~1860 px lógicos menos a barra lateral
p = plan(width=1500, columns=3, preview_on=True, **base)
check("apertado: primeiro some Tamanho/Modificado/☆", p.hide_secondary and p.strip_columns == 3
      and p.preview_width == 320 and p.name_width >= NAME_MIN, p)

p = plan(width=1250, columns=5, preview_on=True, **base)
check("5 níveis: menos colunas anteriores antes de mexer no painel",
      p.strip_columns == 2 and p.preview_width == 320 and p.name_width >= NAME_MIN, p)

p = plan(width=1150, columns=5, preview_on=True, **base)
check("mais apertado: painel estreita até o mínimo", p.strip_columns == 2
      and PREVIEW_MIN <= p.preview_width < 320 and p.name_width >= NAME_MIN, p)

p = plan(width=950, columns=5, preview_on=True, **base)
check("ainda mais: só 1 coluna anterior", p.strip_columns == 1 and p.preview_width >= PREVIEW_MIN
      and p.name_width >= NAME_MIN, p)

p = plan(width=700, columns=5, preview_on=True, **base)
check("janela pequena: painel recolhe sozinho", p.preview_width == 0 and p.preview_auto_hidden
      and p.name_width >= NAME_MIN, p)

p = plan(width=700, columns=5, preview_on=True, preview_forced=True, **base)
check("painel reaberto à mão: não recolhe de novo", p.preview_width > 0 and not p.preview_auto_hidden, p)

p = plan(width=700, columns=5, preview_on=True, auto_preview=False, **base)
check("opção de recolher desligada: painel fica", p.preview_width > 0, p)

p = plan(width=2000, columns=5, preview_on=True, **base)
check("espaço de volta: painel volta ao tamanho normal", p.preview_width == 320
      and not p.preview_auto_hidden, p)

p = plan(width=900, columns=3, preview_on=False, **base)
check("painel desligado pelo usuário continua desligado", p.preview_width == 0
      and not p.preview_auto_hidden and p.name_width >= NAME_MIN, p)

p = plan(width=900, columns=3, preview_on=True, prioritize=False, **base)
check("opção Priorizar nomes desligada: comportamento antigo", p.strip_columns == 3
      and p.preview_width == 320 and not p.hide_secondary, p)

p = plan(width=1200, columns=0, preview_on=True, **base)
check("pasta raiz (sem colunas anteriores)", p.strip_columns == 0 and p.name_width >= NAME_MIN, p)

print(f"\n{sum(results)}/{len(results)} verificações passaram")
sys.exit(0 if all(results) else 1)
