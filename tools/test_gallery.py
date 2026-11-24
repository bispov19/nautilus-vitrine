"""Testes dos grupos da Galeria (sem Nautilus).

    python3 tools/test_gallery.py
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import GLib  # noqa: E402

from vitrine.gallery import date_bucket  # noqa: E402

results = []


def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + ("" if ok else f"  (veio {got!r}, esperado {want!r})"))


def at(y, m, d, h=12):
    return GLib.DateTime.new_local(y, m, d, h, 0, 0).to_unix()


now = at(2026, 11, 24, 15)
check("hoje", date_bucket(at(2026, 11, 24, 0) + 60, now)[1], "Hoje")
check("ontem (mesmo perto da meia-noite)", date_bucket(at(2026, 11, 23, 23), now)[1], "Ontem")
check("últimos 7 dias", date_bucket(at(2026, 11, 19), now)[1], "Últimos 7 dias")
check("últimos 30 dias", date_bucket(at(2026, 11, 2), now)[1], "Últimos 30 dias")
check("mês do ano atual", date_bucket(at(2026, 3, 10), now)[1], "Março")
check("ano anterior", date_bucket(at(2024, 12, 31), now)[1], "2024")
order = [date_bucket(t, now)[0] for t in (now, at(2026, 11, 23), at(2026, 11, 19), at(2026, 11, 2),
                                          at(2026, 9, 1), at(2026, 3, 1), at(2025, 6, 1), at(2023, 1, 1))]
check("grupos do mais novo para o mais antigo", order, sorted(order))
print(f"\n{sum(results)}/{len(results)} verificações passaram")
sys.exit(0 if all(results) else 1)
