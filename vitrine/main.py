"""Ponto central: descobre as janelas do Nautilus e oferece o menu "Visualização desta pasta"."""

from __future__ import annotations

import os
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Nautilus", "4.1")
from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Nautilus  # noqa: E402

from . import __version__, discovery, imageload, native  # noqa: E402
from .computer import DeviceHub  # noqa: E402
from .config import GRID_ZOOMS, Config  # noqa: E402
from .tags import PALETTE, TagError, TagStore, read_tags, uri_to_path  # noqa: E402
from .util import ASSETS, guarded, log  # noqa: E402
from .window import WindowController  # noqa: E402

VERSION = __version__

CSS = b"""
.vitrine-strip { background-color: var(--view-bg-color); }
.vitrine-column listview.vitrine-list { background: transparent; }
.vitrine-column listview.vitrine-list > row { margin: 1px 4px; padding: 4px 6px; }
.vitrine-preview { background-color: var(--sidebar-bg-color); }
.vitrine-picture { border-radius: 10px; }
.vitrine-sidebar { background: transparent; padding-bottom: 0; }
.vitrine-computer { background-color: var(--view-bg-color); }
.vitrine-computer flowboxchild { padding: 0; border-radius: 12px; }
.vitrine-tile { padding: 12px 8px; min-width: 96px; border-radius: 12px; }
.vitrine-folders > flowboxchild { transition: background-color 150ms ease-out; }
.vitrine-folders > flowboxchild:hover {
  background-color: color-mix(in srgb, currentColor 5%, transparent); }
.vitrine-folders > flowboxchild:active {
  background-color: color-mix(in srgb, currentColor 9%, transparent); }
.vitrine-folders > flowboxchild:selected {
  background-color: color-mix(in srgb, var(--accent-bg-color) 18%, transparent); }
.vitrine-folders > flowboxchild:selected:hover {
  background-color: color-mix(in srgb, var(--accent-bg-color) 24%, transparent); }
.vitrine-card { padding: 12px 14px; }
.vitrine-computer flowboxchild:selected > .vitrine-card,
.vitrine-card.vitrine-new { box-shadow: inset 0 0 0 2px var(--accent-bg-color); }
levelbar.vitrine-usage trough { min-height: 6px; }
levelbar.vitrine-usage block.vitrine-ok { background-color: var(--accent-bg-color); }
levelbar.vitrine-usage block.vitrine-warn { background-color: var(--warning-bg-color); }
levelbar.vitrine-usage block.vitrine-full { background-color: var(--error-bg-color); }
.vitrine-gallery { background-color: var(--view-bg-color); }
.vitrine-gallery-stage { padding: 24px 24px 8px 24px; }
.vitrine-gallery-picture { border-radius: 12px; }
.vitrine-gallery-strip { padding: 8px 14px 12px 14px; }
.vitrine-gallery-item { padding: 4px; border-radius: 10px; min-width: 0; min-height: 0; }
.vitrine-gallery-item.selected {
  background-color: color-mix(in srgb, var(--accent-bg-color) 28%, transparent); }
.vitrine-gallery-thumb { border-radius: 8px; }
.vitrine-gallery-group { font-weight: bold; font-size: smaller; margin: 0 6px 0 14px;
  color: color-mix(in srgb, currentColor 55%, transparent); }
.vitrine-gallery-info { padding: 20px 18px;
  border-left: 1px solid color-mix(in srgb, currentColor 10%, transparent); }
.vitrine-badge { font-size: smaller; font-weight: bold; color: var(--accent-fg-color);
  background-color: var(--accent-bg-color); border-radius: 99px; padding: 0 7px; }
"""


_ACTIVE_INSTANCE = None


class VitrineExtension(GObject.GObject, Nautilus.MenuProvider, Nautilus.InfoProvider,
                       Nautilus.ColumnProvider, Nautilus.PropertiesModelProvider):
    def __init__(self) -> None:
        global _ACTIVE_INSTANCE
        super().__init__()
        # Instalada duas vezes (RPM em /usr/share + cópia de desenvolvimento em ~/.local)?
        # O nautilus-python carrega as duas; só a primeira instância trabalha.
        self._inert = _ACTIVE_INSTANCE is not None
        if self._inert:
            log("outra cópia da Vitrine já está ativa; esta instância fica inativa")
            return
        _ACTIVE_INSTANCE = self
        self.cfg = Config()
        self.windows: dict = {}
        self._suppress_until = 0.0
        self._attempts = 0
        self._css_done = False
        self.selftest_started = False
        self.debug_dump = os.environ.get("VITRINE_DUMP", "") not in ("", "0")
        self._prefs = Gio.Settings.new("org.gnome.nautilus.preferences")
        self._icon_prefs = Gio.Settings.new("org.gnome.nautilus.icon-view")
        self._icon_prefs.connect("changed::default-zoom-level", self._on_zoom_changed)
        self.tags = TagStore(self.cfg, on_files_changed=self._invalidate_files)
        self.cfg.on_change(self._on_setting_changed)
        log(f"preferências: {self.cfg.backend}")
        self.hub = DeviceHub()
        self.hub.on_new_device(self._on_new_device)
        log(f"Vitrine {VERSION} carregada")
        GLib.timeout_add(100, self._late_init)

    # ── janelas ──
    @guarded
    def _late_init(self) -> bool:
        app = Gtk.Application.get_default()
        if app is None:
            self._attempts += 1
            return self._attempts < 100
        app.connect("window-added", lambda _a, w: self._schedule(w))
        for w in app.get_windows():
            self._schedule(w)
        return GLib.SOURCE_REMOVE

    def _install_css(self) -> None:
        if self._css_done:
            return
        display = Gdk.Display.get_default()
        if display is None:
            return
        provider = Gtk.CssProvider()
        provider.load_from_bytes(GLib.Bytes.new(CSS))
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        # Ícones da Vitrine (ex.: nautilus-vitrine-symbolic) achados pelo nome. O sufixo
        # -symbolic faz o GTK recolorir o ícone com a cor do texto (tema claro/escuro).
        Gtk.IconTheme.get_for_display(display).add_search_path(ASSETS)
        self._css_done = True

    def _schedule(self, win) -> None:
        if win in self.windows or not native.is_nautilus_window(win):
            return
        tries = [0]

        def attempt() -> bool:
            tries[0] += 1
            if win in self.windows:
                return GLib.SOURCE_REMOVE
            slot = native.active_slot(win)
            ready = slot is not None and native.slot_location(slot) is not None
            if not ready and tries[0] < 100:
                return GLib.SOURCE_CONTINUE
            # Prioridade baixa: deixa o Nautilus terminar o primeiro carregamento antes
            # de mexermos na árvore de widgets.
            GLib.idle_add(self._inject, win, priority=GLib.PRIORITY_LOW)
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(50, attempt)

    @guarded
    def _inject(self, win) -> bool:
        if win in self.windows:
            return GLib.SOURCE_REMOVE
        self._install_css()
        ctl = WindowController(self, win)
        if ctl.inject():
            self.windows[win] = ctl
        return GLib.SOURCE_REMOVE

    def forget_window(self, win) -> None:
        self.windows.pop(win, None)

    def active_controller(self) -> WindowController | None:
        app = Gtk.Application.get_default()
        win = app.get_active_window() if app is not None else None
        ctl = self.windows.get(win)
        if ctl is None and self.windows:
            ctl = next(iter(self.windows.values()))
        return ctl

    @guarded
    def _on_setting_changed(self, key: str) -> None:
        if key == "window_style":
            for ctl in list(self.windows.values()):
                ctl.apply_window_style()
        elif key in ("tags_in_sidebar", "image_dimensions", "path_bar", "status_bar"):
            # Opções da camada Finder: reaplica para valer na hora.
            for ctl in list(self.windows.values()):
                if ctl.style is not None and ctl.style.active:
                    ctl.style.remove()
                    ctl.style.apply()
        elif key in ("computer_in_sidebar", "computer_hidden", "computer_sections"):
            self.refresh_computer_pages()

    def refresh_computer_pages(self) -> None:
        for ctl in list(self.windows.values()):
            ctl.apply_computer_settings()

    def _on_new_device(self, key, name, mount, volume) -> None:
        """Avisa só na janela ativa (evita um aviso repetido por janela aberta)."""
        if not self.cfg.get("notify_new_devices"):
            return
        ctl = self.active_controller()
        if ctl is not None:
            ctl.on_new_device(key, name, mount, volume)

    # ── supressão: mudanças feitas por nós não contam como escolha do usuário ──
    def suppress(self, ms: int = 900) -> None:
        self._suppress_until = max(self._suppress_until, time.monotonic() + ms / 1000)

    def is_suppressed(self) -> bool:
        return time.monotonic() < self._suppress_until

    def current_grid_zoom(self) -> str:
        z = self._icon_prefs.get_string("default-zoom-level")
        return z if z in GRID_ZOOMS else "medium"

    def set_grid_zoom(self, zoom: str | None) -> None:
        if zoom not in GRID_ZOOMS or self.current_grid_zoom() == zoom:
            return
        self.suppress()
        self._icon_prefs.set_string("default-zoom-level", zoom)

    @guarded
    def _on_zoom_changed(self, settings, key) -> None:
        if self.is_suppressed():
            return
        ctl = self.active_controller()
        if ctl is not None:
            ctl.record_zoom(settings.get_string(key))

    # ── etiquetas e dimensões (API oficial: InfoProvider / ColumnProvider) ──
    def update_file_info(self, file):
        """Chamado pelo Nautilus para cada arquivo mostrado. Bolinhas das etiquetas como
        emblemas, texto para a coluna "Etiquetas" e dimensões das imagens."""
        if self._inert or file.get_uri_scheme() != "file":
            return Nautilus.OperationResult.COMPLETE
        try:
            uri = file.get_uri()
            path = uri_to_path(uri)
            names = read_tags(path) if path else []
            for name in names:
                file.add_emblem(f"vitrine-tag-{self.tags.color_of(name)}")
            file.add_string_attribute("vitrine_tags", ", ".join(names))
            self.tags.seen(uri, names)
            if path and self.cfg.get("image_dimensions"):
                mime = file.get_mime_type() or ""
                if mime in ("image/jpeg", "image/png"):
                    p = imageload.probe(path, mime)
                    if p.width and p.height:
                        w, h = (p.height, p.width) if p.orientation in (5, 6, 7, 8) else (p.width, p.height)
                        file.add_string_attribute("vitrine_dimensions", f"{_thousands(w)} × {_thousands(h)}")
        except Exception as err:  # noqa: BLE001
            log(f"update_file_info: {err!r}")
        return Nautilus.OperationResult.COMPLETE

    def get_columns(self):
        if self._inert:
            return []
        return [
            Nautilus.Column(name="Vitrine::tags", attribute="vitrine_tags", label="Etiquetas",
                            description="Etiquetas coloridas (user.xdg.tags)"),
            Nautilus.Column(name="Vitrine::dimensions", attribute="vitrine_dimensions",
                            label="Dimensões", description="Largura × altura das imagens"),
        ]

    def get_models(self, files):
        """Aba "Etiquetas" na janela Propriedades (Ctrl+I), pela API oficial."""
        if self._inert or not files:
            return []
        try:
            from gi.repository import Gio as _Gio
            store = _Gio.ListStore.new(Nautilus.PropertiesItem)
            for f in files:
                if f.get_uri_scheme() != "file":
                    continue
                names = read_tags(uri_to_path(f.get_uri()))
                label = f.get_name() if len(files) > 1 else "Etiquetas"
                store.append(Nautilus.PropertiesItem.new(label, ", ".join(names) if names else "Nenhuma"))
            if store.get_n_items() == 0:
                return []
            return [Nautilus.PropertiesModel.new("Etiquetas", store)]
        except Exception as err:  # noqa: BLE001
            log(f"propriedades: {err!r}")
            return []

    def _invalidate_files(self, uris) -> None:
        """Etiquetas mudaram: o Nautilus pergunta de novo (emblemas, coluna)."""
        for uri in uris:
            try:
                info = Nautilus.FileInfo.create_for_uri(uri)
                if info is not None:
                    info.invalidate_extension_info()
            except Exception as err:  # noqa: BLE001
                log(f"etiquetas: não consegui atualizar {uri}: {err!r}")

    # ── menu de contexto dos arquivos: Etiquetas ──
    @guarded
    def get_file_items(self, *args):
        files = args[-1] if args else None
        if self._inert or not files:
            return []
        uris = [f.get_uri() for f in files if f.get_uri_scheme() == "file"]
        if not uris:
            return []
        current = [set(read_tags(uri_to_path(u))) for u in uris]
        root = Nautilus.MenuItem(name="Vitrine::tags", label="Etiquetas")
        sub = Nautilus.Menu()
        root.set_submenu(sub)
        for name, color in self.tags.definitions():
            has = all(name in c for c in current)
            emoji = PALETTE.get(color, PALETTE["gray"])[1]
            item = Nautilus.MenuItem(name=f"Vitrine::tag::{name}",
                                     label=f"{emoji}  {name}{'  ✓' if has else ''}")
            item.connect("activate", lambda *_a, n=name: GLib.idle_add(
                self._tag_action, lambda: self.tags.toggle(uris, n)))
            sub.append_item(item)
        if any(current):
            clear = Nautilus.MenuItem(name="Vitrine::tag-clear", label="Remover etiquetas")
            clear.connect("activate", lambda *_a: GLib.idle_add(
                self._tag_action, lambda: self.tags.clear(uris)))
            sub.append_item(clear)
        manage = Nautilus.MenuItem(name="Vitrine::tag-manage", label="Todas as etiquetas…")
        manage.connect("activate", lambda *_a: GLib.idle_add(self._run, _open_tag_manager))
        sub.append_item(manage)
        return [root]

    def _tag_action(self, fn) -> bool:
        try:
            fn()
        except TagError as err:
            ctl = self.active_controller()
            if ctl is not None:
                ctl.toast(f"Não foi possível etiquetar: {err}")
            else:
                log(f"etiquetas: {err}")
        return GLib.SOURCE_REMOVE

    # ── menu de contexto no fundo da pasta (API oficial do Nautilus) ──

    @guarded
    def get_background_items(self, *args):
        folder = args[-1] if args else None
        if folder is None or self._inert:
            return []
        uri = folder.get_uri()
        if not native.is_regular_location(uri):
            return []
        rule, exact = self.cfg.rule_for(uri)

        root = Nautilus.MenuItem(name="Vitrine::root", label="Visualização desta pasta")
        sub = Nautilus.Menu()
        root.set_submenu(sub)

        def add(name, label, cb):
            item = Nautilus.MenuItem(name=f"Vitrine::{name}", label=label)
            item.connect("activate", lambda *_a: GLib.idle_add(self._run, cb))
            sub.append_item(item)

        add("list", "Lista", lambda c: c.user_set_mode("list"))
        add("grid", "Ícones", lambda c: c.user_set_mode("grid", "medium"))
        add("grid-large", "Ícones grandes", lambda c: c.user_set_mode("grid", "extra-large"))
        add("columns", "Colunas", lambda c: c.user_set_mode("columns"))
        add("gallery", "Galeria", lambda c: c.user_set_mode("gallery"))

        if exact and rule:
            if rule.get("recursive"):
                add("norec", "Não aplicar às subpastas",
                    lambda c: self.cfg.set_rule(uri, recursive=False))
            else:
                add("rec", "Aplicar também às subpastas",
                    lambda c: self.cfg.set_rule(uri, recursive=True))
            add("forget", "Esquecer esta pasta (usar o padrão)", lambda c: self._forget(c, uri))
        elif rule:
            add("info", "(herdando a regra de uma pasta acima)", lambda c: None)

        add("discovery", "Desligar a descoberta automática de pastas"
            if self.cfg.get("folder_discovery") else "Ligar a descoberta automática de pastas",
            self._toggle_discovery)
        add("default", "Usar a visualização atual como padrão", self._make_default)
        add("preview", "Mostrar/ocultar pré-visualização (Ctrl+Shift+P)",
            lambda c: c.set_preview_visible(not c.preview.get_visible()))

        computer = Nautilus.MenuItem(name="Vitrine::computer", label="Meu computador")
        computer.connect("activate", lambda *_a: GLib.idle_add(
            self._run, lambda c: c.show_computer(True)))
        # O Nautilus põe os itens de extensões numa seção própria, antes de
        # "Propriedades": este é o último item *da Vitrine* no menu.
        about = Nautilus.MenuItem(name="Vitrine::about", label="Sobre a Vitrine")
        about.connect("activate", lambda *_a: GLib.idle_add(
            self._run, lambda c: c.open_settings("about")))
        return [root, computer, about]

    def _run(self, cb) -> bool:
        ctl = self.active_controller()
        if ctl is not None:
            try:
                cb(ctl)
            except Exception as err:  # noqa: BLE001
                log(f"menu: {err}")
        return GLib.SOURCE_REMOVE

    def _forget(self, ctl: WindowController, uri: str) -> None:
        self.cfg.forget(uri)
        discovery.forget_manual(uri)
        slot = ctl.active_slot()
        if slot is not None:
            slot._vitrine_mode = None
            ctl._apply_rule_for_slot(slot, native.slot_uri(slot))

    def _toggle_discovery(self, ctl: WindowController) -> None:
        on = not self.cfg.get("folder_discovery")
        self.cfg.set("folder_discovery", on)
        ctl.toast("Descoberta automática de pastas ligada" if on
                  else "Descoberta automática de pastas desligada")
        slot = ctl.active_slot()
        if on and slot is not None:
            ctl._apply_rule_for_slot(slot, native.slot_uri(slot))  # já vale para a pasta atual

    def _make_default(self, ctl: WindowController) -> None:
        slot = ctl.active_slot()
        mode = getattr(slot, "_vitrine_mode", None) or native.view_mode(slot) or "list"
        self.cfg.set("default_mode", mode)
        if mode == "grid":
            self.cfg.set("default_grid_zoom", self.current_grid_zoom())
        log(f"novo padrão: {mode}")


def _thousands(n: int) -> str:
    """1066 → "1.066" (separador de milhar do português)."""
    return f"{n:,}".replace(",", ".")


def _open_tag_manager(ctl) -> None:
    from .tagui import open_manager
    open_manager(ctl)
