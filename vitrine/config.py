"""Preferências (GSettings) e regras de visualização por pasta (JSON).

Preferências: schema io.github.bispov19.NautilusVitrine, que vem dentro da extensão
(vitrine/schemas) e é carregado com SettingsSchemaSource.new_from_directory, sem root.
Na primeira vez, o antigo settings.json é importado (e guardado como .importado).
Se o schema não puder ser carregado, cai no JSON de antes e registra no log.

Regras por pasta: ~/.config/nautilus-vitrine/folders.json (são dados, não preferências).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess

from gi.repository import Gio, GLib

from .util import debug, log

CONFIG_DIR = os.path.join(GLib.get_user_config_dir(), "nautilus-vitrine")
SETTINGS_PATH = os.path.join(CONFIG_DIR, "settings.json")
FOLDERS_PATH = os.path.join(CONFIG_DIR, "folders.json")

MODES = ("list", "grid", "columns", "gallery")
GRID_ZOOMS = ("small", "small-plus", "medium", "large", "extra-large")

SCHEMA_ID = "io.github.bispov19.NautilusVitrine"
SCHEMA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schemas")
WINDOW_STYLES = ("finder", "nautilus")

DEFAULT_SETTINGS = {
    # Estilo da janela: "finder" (visual do Finder do macOS) ou "nautilus" (padrão).
    "window_style": "finder",
    # Etiquetas: (nome, cor). Os nomes ficam gravados nos arquivos (user.xdg.tags).
    "tags": [("Vermelho", "red"), ("Laranja", "orange"), ("Amarelo", "yellow"),
             ("Verde", "green"), ("Azul", "blue"), ("Roxo", "purple")],
    "tags_in_sidebar": True,
    "tags_section_expanded": True,
    "image_dimensions": True,
    # Galeria: agrupar a faixa de miniaturas (none, date, type, size, tags).
    "gallery_group_by": "date",
    # Estilo Finder: barra de caminho e barra de status embaixo.
    "path_bar": False,
    "status_bar": False,
    # Painel de pré-visualização à direita (Ctrl+Shift+P).
    "preview_visible": True,
    "preview_width": 320,
    # Largura de cada coluna no modo Colunas.
    "column_width": 230,
    # Quantas colunas anteriores aparecem antes de começar a rolar.
    "max_visible_columns": 3,
    # Ao trocar a visualização numa pasta, guardar a escolha para aquela pasta.
    "remember_per_folder": True,
    # Pastas cheias de fotos/vídeos abrem em ícones grandes automaticamente.
    "auto_media_grid": True,
    "auto_media_zoom": "extra-large",
    "auto_media_ratio": 0.6,
    # Descoberta automática de pastas: mídia → ícones extra grandes, documentos → lista,
    # mistas/vazias → padrão. Desligada = comportamento de sempre (auto_media_grid acima).
    "folder_discovery": False,
    # Abrir o Nautilus já na página "Meu computador" (quando abre na pasta pessoal,
    # que é o que acontece pelo menu de aplicativos ou numa janela nova).
    "start_on_computer": False,
    # Entrada "Meu computador" no topo da barra lateral.
    "computer_in_sidebar": True,
    # Seções desligadas: {"places": false, "devices": ..., "network": ...}
    "computer_sections": {},
    # Itens ocultos (URIs de locais/marcadores ou chaves de dispositivos).
    "computer_hidden": [],
    # Avisar (com botão "Abrir") quando um pen drive/HD externo/cartão for conectado.
    "notify_new_devices": True,
    # Visualização para pastas sem regra. None = capturar do Nautilus na 1ª execução.
    "default_mode": None,
    "default_grid_zoom": None,
}


def _load_json(path: str, fallback):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return fallback
    except (OSError, ValueError) as err:
        log(f"config: {path} ilegível ({err}); usando padrão")
        return fallback


# Tipo GVariant de cada chave (o nome no GSettings troca "_" por "-").
_GS_TYPES = {
    "window_style": "enum",
    "preview_visible": "b", "preview_width": "i", "column_width": "i",
    "max_visible_columns": "i", "remember_per_folder": "b", "auto_media_grid": "b",
    "auto_media_zoom": "s", "auto_media_ratio": "d", "folder_discovery": "b",
    "start_on_computer": "b", "computer_in_sidebar": "b", "computer_sections": "a{sb}",
    "computer_hidden": "as", "notify_new_devices": "b",
    "default_mode": "s?", "default_grid_zoom": "s?",  # "" no GSettings = None aqui
    "tags": "a(ss)", "tags_in_sidebar": "b", "tags_section_expanded": "b",
    "image_dimensions": "b", "gallery_group_by": "s", "path_bar": "b", "status_bar": "b",
}


def _gs_key(key: str) -> str:
    return key.replace("_", "-")


def _schema_source() -> Gio.SettingsSchemaSource | None:
    """Fonte com o schema da Vitrine: o compilado que vem com a extensão; se faltar
    (ex.: cópia feita sem o install.sh), compila agora em ~/.cache."""
    default = Gio.SettingsSchemaSource.get_default()
    candidates = [SCHEMA_DIR]
    if not os.path.exists(os.path.join(SCHEMA_DIR, "gschemas.compiled")):
        cache = os.path.join(GLib.get_user_cache_dir(), "nautilus-vitrine", "schemas")
        tool = shutil.which("glib-compile-schemas")
        if tool:
            try:
                os.makedirs(cache, exist_ok=True)
                subprocess.run([tool, "--targetdir", cache, SCHEMA_DIR], check=True,
                               capture_output=True, timeout=10)
                candidates = [cache]
            except (OSError, subprocess.SubprocessError) as err:
                log(f"config: não foi possível compilar o schema ({err})")
    for path in candidates:
        try:
            return Gio.SettingsSchemaSource.new_from_directory(path, default, False)
        except GLib.Error as err:
            log(f"config: schema em {path} ilegível ({err.message})")
    return None


def open_gsettings() -> Gio.Settings | None:
    try:
        source = _schema_source()
        schema = source.lookup(SCHEMA_ID, False) if source is not None else None
        if schema is None:
            log("config: schema da Vitrine não encontrado; usando settings.json")
            return None
        return Gio.Settings.new_full(schema, None, None)
    except Exception as err:  # noqa: BLE001
        log(f"config: GSettings indisponível ({err}); usando settings.json")
        return None


def _gs_read(gs: Gio.Settings, key: str):
    kind = _GS_TYPES[key]
    if kind == "enum":
        return gs.get_string(_gs_key(key))
    value = gs.get_value(_gs_key(key)).unpack()
    if kind == "s?":
        return value or None
    return value


def _gs_write(gs: Gio.Settings, key: str, value) -> None:
    kind = _GS_TYPES[key]
    if kind == "enum":
        gs.set_string(_gs_key(key), str(value))
    elif kind == "s?":
        gs.set_value(_gs_key(key), GLib.Variant("s", value or ""))
    elif kind == "a{sb}":
        gs.set_value(_gs_key(key), GLib.Variant(kind, {str(k): bool(v)
                                                      for k, v in (value or {}).items()}))
    elif kind == "as":
        gs.set_value(_gs_key(key), GLib.Variant(kind, [str(v) for v in (value or [])]))
    elif kind == "a(ss)":
        gs.set_value(_gs_key(key), GLib.Variant(kind, [(str(n), str(c)) for n, c in (value or [])]))
    elif kind == "d":
        gs.set_value(_gs_key(key), GLib.Variant(kind, float(value)))
    elif kind == "i":
        gs.set_value(_gs_key(key), GLib.Variant(kind, int(value)))
    else:
        gs.set_value(_gs_key(key), GLib.Variant(kind, value))


def _norm(uri: str) -> str:
    return Gio.File.new_for_uri(uri).get_uri()


class Config:
    def __init__(self, gsettings: Gio.Settings | None = None, *, use_gsettings: bool = True) -> None:
        self.settings = dict(DEFAULT_SETTINGS)
        self._listeners: list = []
        self.gs = gsettings if gsettings is not None else (open_gsettings() if use_gsettings else None)
        if self.gs is not None:
            self._import_json_once()
            for key in _GS_TYPES:
                self.settings[key] = _gs_read(self.gs, key)
            # Mudanças vindas de fora (gsettings no terminal, outra cópia) valem na hora.
            self.gs.connect("changed", self._on_gs_changed)
        else:
            self.settings.update(_load_json(SETTINGS_PATH, {}))
        raw = _load_json(FOLDERS_PATH, {})
        self.folders: dict[str, dict] = {k: v for k, v in raw.items() if isinstance(v, dict)}
        self._save_id = 0
        self._seed_defaults()

    @property
    def backend(self) -> str:
        return "gsettings" if self.gs is not None else "json"

    def _import_json_once(self) -> None:
        gs = self.gs
        if gs.get_boolean("json-migrated"):
            return
        old = _load_json(SETTINGS_PATH, None)
        if isinstance(old, dict):
            imported = []
            for key, value in old.items():
                if key in _GS_TYPES and value is not None:
                    try:
                        _gs_write(gs, key, value)
                        imported.append(key)
                    except (TypeError, ValueError) as err:
                        log(f"config: não importei {key}={value!r} ({err})")
            try:
                os.replace(SETTINGS_PATH, SETTINGS_PATH + ".importado")
            except OSError:
                pass
            log(f"config: settings.json importado para o GSettings ({len(imported)} chaves)")
        gs.set_boolean("json-migrated", True)

    # ── avisos de mudança ──
    def on_change(self, callback) -> None:
        """callback(chave) quando uma preferência muda (aqui ou fora do Nautilus)."""
        self._listeners.append(callback)

    def _notify(self, key: str) -> None:
        for cb in list(self._listeners):
            try:
                cb(key)
            except Exception as err:  # noqa: BLE001
                log(f"config: ouvinte de {key}: {err}")

    def _on_gs_changed(self, gs, gs_key: str) -> None:
        key = gs_key.replace("-", "_")
        if key not in _GS_TYPES:
            return
        value = _gs_read(gs, key)
        if self.settings.get(key) != value:
            debug(f"config: {key} mudou fora da Vitrine -> {value!r}")
            self.settings[key] = value
            self._notify(key)

    def _seed_defaults(self) -> None:
        changed = False
        if self.settings.get("default_mode") not in MODES:
            try:
                viewer = Gio.Settings.new("org.gnome.nautilus.preferences").get_string(
                    "default-folder-viewer"
                )
            except Exception:  # noqa: BLE001
                viewer = "list-view"
            self.settings["default_mode"] = "grid" if viewer == "icon-view" else "list"
            changed = True
        if self.settings.get("default_grid_zoom") not in GRID_ZOOMS:
            try:
                zoom = Gio.Settings.new("org.gnome.nautilus.icon-view").get_string(
                    "default-zoom-level"
                )
            except Exception:  # noqa: BLE001
                zoom = "medium"
            self.settings["default_grid_zoom"] = zoom if zoom in GRID_ZOOMS else "medium"
            changed = True
        if not self.folders:
            self._seed_pictures_rule()
            changed = True
        if changed:
            self.save()

    def _seed_pictures_rule(self) -> None:
        """Na primeira execução: a pasta Imagens (XDG) começa em ícones grandes."""
        for special in (GLib.UserDirectory.DIRECTORY_PICTURES, GLib.UserDirectory.DIRECTORY_VIDEOS):
            path = GLib.get_user_special_dir(special)
            if path and os.path.isdir(path) and os.path.realpath(path) != os.path.expanduser("~"):
                uri = Gio.File.new_for_path(path).get_uri()
                self.folders[uri] = {"mode": "grid", "zoom": "extra-large", "recursive": True}

    # ── leitura ──
    def get(self, key: str):
        return self.settings.get(key, DEFAULT_SETTINGS.get(key))

    def set(self, key: str, value) -> None:
        changed = self.settings.get(key) != value
        self.settings[key] = value
        self.save()
        if changed:
            self._notify(key)

    def rule_for(self, uri: str) -> tuple[dict | None, bool]:
        """Regra que vale para `uri`: (regra, é_exata). Sobe pelas pastas-pai
        procurando uma regra marcada como "aplicar às subpastas"."""
        uri = _norm(uri)
        rule = self.folders.get(uri)
        if rule:
            return rule, True
        f = Gio.File.new_for_uri(uri).get_parent()
        while f is not None:
            r = self.folders.get(f.get_uri())
            if r and r.get("recursive"):
                return r, False
            f = f.get_parent()
        return None, False

    # ── escrita ──
    def set_rule(self, uri: str, *, mode: str | None = None, zoom: str | None = None,
                 recursive: bool | None = None) -> dict:
        uri = _norm(uri)
        rule = dict(self.folders.get(uri) or {})
        if mode is not None:
            rule["mode"] = mode
        if zoom is not None:
            rule["zoom"] = zoom
        if recursive is not None:
            rule["recursive"] = recursive
        rule.setdefault("mode", self.get("default_mode"))
        self.folders[uri] = rule
        self.save()
        log(f"regra salva: {uri} -> {rule}")
        return rule

    def forget(self, uri: str) -> None:
        if self.folders.pop(_norm(uri), None) is not None:
            self.save()
            log(f"regra removida: {uri}")

    def save(self) -> None:
        """Grava em disco de forma agrupada (no máximo 1x a cada 400 ms)."""
        if self._save_id:
            return
        self._save_id = GLib.timeout_add(400, self._flush)

    def _flush(self) -> bool:
        self._save_id = 0
        files = [(FOLDERS_PATH, self.folders)]
        if self.gs is not None:
            for key in _GS_TYPES:
                try:
                    if _gs_read(self.gs, key) != self.settings.get(key):
                        _gs_write(self.gs, key, self.settings.get(key))
                except (TypeError, ValueError) as err:
                    log(f"config: valor inválido para {key}: {self.settings.get(key)!r} ({err})")
        else:
            files.insert(0, (SETTINGS_PATH, self.settings))
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            for path, data in files:
                tmp = path + ".tmp"
                with open(tmp, "w", encoding="utf-8") as fh:
                    json.dump(data, fh, indent=2, ensure_ascii=False)
                os.replace(tmp, path)
        except OSError as err:
            log(f"config: falha ao salvar ({err})")
        return GLib.SOURCE_REMOVE
