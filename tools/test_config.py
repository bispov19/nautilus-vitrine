"""Testes das preferências em GSettings (sem tocar nas suas preferências reais).

    python3 tools/test_config.py

Usa o backend de memória do GSettings e um settings.json falso numa pasta temporária.
"""

import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gio  # noqa: E402

from vitrine import config  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + (f"  ({detail})" if not ok and detail else ""))


def memory_settings(schema_dir):
    source = Gio.SettingsSchemaSource.new_from_directory(
        schema_dir, Gio.SettingsSchemaSource.get_default(), False)
    schema = source.lookup(config.SCHEMA_ID, False)
    return Gio.Settings.new_full(schema, Gio.memory_settings_backend_new(), None)


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="vitrine-config-")
    schema_dir = os.path.join(tmp, "schemas")
    os.makedirs(schema_dir)
    subprocess.run(["glib-compile-schemas", "--strict", "--targetdir", schema_dir,
                    config.SCHEMA_DIR], check=True)
    # Arquivos falsos no lugar dos de verdade.
    config.CONFIG_DIR = tmp
    config.SETTINGS_PATH = os.path.join(tmp, "settings.json")
    config.FOLDERS_PATH = os.path.join(tmp, "folders.json")
    with open(config.SETTINGS_PATH, "w", encoding="utf-8") as fh:
        json.dump({"preview_visible": False, "computer_hidden": ["trash:///"],
                   "computer_sections": {"network": False}, "auto_media_ratio": 0.7,
                   "default_mode": "grid", "chave_desconhecida": 1}, fh)

    gs = memory_settings(schema_dir)
    cfg = config.Config(gs)
    check("backend é GSettings", cfg.backend == "gsettings")
    check("estilo padrão de fábrica é Finder", cfg.get("window_style") == "finder")
    check("settings.json importado (bool, lista, dicionário, número, texto)",
          cfg.get("preview_visible") is False and cfg.get("computer_hidden") == ["trash:///"]
          and cfg.get("computer_sections") == {"network": False}
          and abs(cfg.get("auto_media_ratio") - 0.7) < 1e-9 and cfg.get("default_mode") == "grid",
          str(cfg.settings))
    check("settings.json antigo guardado como .importado",
          not os.path.exists(config.SETTINGS_PATH)
          and os.path.exists(config.SETTINGS_PATH + ".importado"))
    check("importação acontece uma vez só", gs.get_boolean("json-migrated"))

    seen = []
    cfg.on_change(seen.append)
    cfg.set("window_style", "nautilus")
    cfg._flush()
    check("set() grava no GSettings e avisa", gs.get_string("window-style") == "nautilus"
          and seen == ["window_style"], f"{gs.get_string('window-style')} {seen}")

    seen.clear()
    gs.set_string("window-style", "finder")  # como `gsettings set` no terminal
    check("mudança feita fora da Vitrine vale na hora", cfg.get("window_style") == "finder"
          and seen == ["window_style"], str(seen))

    cfg.set("default_mode", None)
    cfg._flush()
    check("None vira texto vazio e volta como None",
          gs.get_string("default-mode") == "" and config.Config(gs).get("default_mode") is not None)

    cfg2 = config.Config(use_gsettings=False)
    check("sem schema: cai no JSON", cfg2.backend == "json")

    print(f"\n{sum(results)}/{len(results)} verificações passaram")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
