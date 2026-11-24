#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  criar-vitrine.sh — cria o projeto "Vitrine para Nautilus" (Fedora / GNOME)
#
#  Uso:
#     bash criar-vitrine.sh                 # cria em ~/nautilus-vitrine
#     bash criar-vitrine.sh ~/Projetos/vit  # cria na pasta indicada
#     bash criar-vitrine.sh --instalar      # cria e já instala no Nautilus
#
#  Depois:  code ~/nautilus-vitrine   (abre no VS Code; Ctrl+Shift+B instala)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TARGET="$HOME/nautilus-vitrine"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --instalar|--install) INSTALL=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) TARGET="$arg" ;;
  esac
done

if [[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
  read -r -p "A pasta $TARGET já existe e não está vazia. Sobrescrever os arquivos da Vitrine? [s/N] " ans
  [[ "${ans:-N}" =~ ^[SsYy]$ ]] || { echo "Cancelado."; exit 1; }
fi
mkdir -p "$TARGET"
cd "$TARGET"
echo "Criando arquivos em $TARGET …"

cat > 'nautilus-vitrine.py' <<'__VITRINE_ARQUIVO_0__'
"""Vitrine para Nautilus: modo Colunas, pré-visualização lateral e visualização por pasta.

Este arquivo é o que o nautilus-python carrega. O código de verdade fica no
pacote `vitrine/` ao lado dele.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from vitrine.main import VitrineExtension  # noqa: E402,F401
__VITRINE_ARQUIVO_0__
mkdir -p "vitrine"
cat > 'vitrine/__init__.py' <<'__VITRINE_ARQUIVO_1__'
"""Vitrine para Nautilus."""

# Fonte única da versão no código. O `Version:` de packaging/nautilus-vitrine.spec
# precisa ser igual (tools/smoke_test.py confere).
__version__ = "0.4.0"
__VITRINE_ARQUIVO_1__
mkdir -p "vitrine"
cat > 'vitrine/about.py' <<'__VITRINE_ARQUIVO_2__'
"""Página "Sobre" do diálogo de personalização.

Fica num módulo próprio porque não depende de nada do Meu computador (só da versão,
da logo e da URL do projeto): pode ser montada e testada numa janela fora do Nautilus
(tools/smoke_test.py) e não aumenta o computer.py, que já é grande.
"""

from __future__ import annotations

import os

from gi.repository import Adw, Gdk, Gtk

from . import __version__
from .util import ASSETS, log

REPO_URL = "https://github.com/bispov19/nautilus-vitrine"
LICENSE = "MIT"
FEATURES = ("Modo Colunas · Painel de pré-visualização · Visualização por pasta · "
            "Descoberta automática de pastas · Meu computador · Aviso de dispositivo novo")

_css_loaded = False


def _ensure_css() -> None:
    """Carrega assets/about.css uma única vez por processo."""
    global _css_loaded
    display = Gdk.Display.get_default()
    if _css_loaded or display is None:
        return
    provider = Gtk.CssProvider()
    provider.load_from_path(os.path.join(ASSETS, "about.css"))
    Gtk.StyleContext.add_provider_for_display(
        display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    _css_loaded = True


def _row(title: str, subtitle: str, icon: str) -> Adw.ActionRow:
    row = Adw.ActionRow(title=title, subtitle=subtitle, use_markup=False)
    row.set_subtitle_lines(0)  # 0 = sem limite: o texto quebra linha em vez de cortar
    row.add_prefix(Gtk.Image.new_from_icon_name(icon))
    return row


def _hero() -> Gtk.Widget:
    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, halign=Gtk.Align.FILL)
    card.add_css_class("vitrine-about-hero")

    logo = Gtk.Image.new_from_file(os.path.join(ASSETS, "nautilus-vitrine-mark.svg"))
    logo.set_pixel_size(140)
    logo.set_margin_bottom(6)
    card.append(logo)

    title = Gtk.Label(label="Vitrine para Nautilus", wrap=True,
                      justify=Gtk.Justification.CENTER)
    title.add_css_class("title-1")
    card.append(title)

    tagline = Gtk.Label(
        label="Modo Colunas, pré-visualização e Meu computador para o Nautilus, "
              "inspirados no Finder do macOS",
        wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=48)
    tagline.add_css_class("dim-label")
    card.append(tagline)

    version = Gtk.Label(label=f"Versão {__version__}  •  {LICENSE}")
    version.add_css_class("caption")
    version.add_css_class("dim-label")
    version.set_margin_top(6)
    card.append(version)
    return card


def _open_repo(row: Gtk.Widget) -> None:
    def done(launcher, result):
        try:
            launcher.launch_finish(result)
        except Exception as err:  # noqa: BLE001  (GLib.Error, inclusive "cancelado")
            log(f"não foi possível abrir {REPO_URL}: {err}")

    root = row.get_root()
    Gtk.UriLauncher(uri=REPO_URL).launch(root if isinstance(root, Gtk.Window) else None,
                                         None, done)


def build_about_page() -> Adw.PreferencesPage:
    _ensure_css()
    page = Adw.PreferencesPage(title="Sobre", icon_name="nautilus-vitrine-symbolic",
                               name="about")

    hero = Adw.PreferencesGroup()
    hero.add(_hero())
    page.add(hero)

    links = Adw.PreferencesGroup(title="Links")
    repo = _row("Repositório no GitHub", REPO_URL.removeprefix("https://"),
                "web-browser-symbolic")
    repo.set_activatable(True)
    repo.add_suffix(Gtk.Image.new_from_icon_name("adw-external-link-symbolic"))
    repo.set_tooltip_text(REPO_URL)
    repo.connect("activated", _open_repo)
    links.add(repo)
    page.add(links)

    credits = Adw.PreferencesGroup(title="Créditos")
    credits.add(_row("Vini", "Web Developer · Autor e mantenedor", "avatar-default-symbolic"))
    credits.add(_row("Recursos", FEATURES, "starred-symbolic"))
    credits.add(_row("Aviso", "A Vitrine é um projeto independente e de código aberto. "
                     "Não é afiliada ao GNOME nem à Apple.", "dialog-information-symbolic"))
    page.add(credits)
    return page
__VITRINE_ARQUIVO_2__
mkdir -p "vitrine"
cat > 'vitrine/columns.py' <<'__VITRINE_ARQUIVO_3__'
"""Modo Colunas (estilo Finder) em formato híbrido.

À esquerda ficam colunas leves com as pastas-pai do local atual. A pasta atual
continua sendo mostrada pela própria visualização em lista do Nautilus, então
menus de contexto, renomear, arrastar e soltar, scripts e extensões continuam
funcionando nela, sem nada reimplementado.
"""

from __future__ import annotations

import os

from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Pango

from . import util
from .util import guarded

ATTRS = ",".join(
    (
        "standard::name",
        "standard::display-name",
        "standard::type",
        "standard::icon",
        "standard::symbolic-icon",
        "standard::is-hidden",
        "standard::is-backup",
        "standard::content-type",
        "standard::target-uri",
    )
)


def _info_file(info: Gio.FileInfo) -> Gio.File | None:
    f = info.get_attribute_object("standard::file")
    return f if isinstance(f, Gio.File) else None


def _is_dir(info: Gio.FileInfo) -> bool:
    return info.get_file_type() in (Gio.FileType.DIRECTORY, Gio.FileType.MOUNTABLE)


def chain_for(location: Gio.File) -> list[Gio.File]:
    """Pastas-pai a mostrar como colunas: da raiz (Pasta pessoal ou /) até o pai do local atual."""
    home = Gio.File.new_for_path(os.path.expanduser("~"))
    chain = []
    f = location.get_parent()
    while f is not None:
        chain.append(f)
        if f.equal(home):
            break
        f = f.get_parent()
    chain.reverse()
    # Se o local está dentro da pasta pessoal, a primeira coluna é a pasta pessoal.
    if not (location.has_prefix(home) or location.equal(home)):
        return chain
    return [c for c in chain if c.equal(home) or c.has_prefix(home)]


class FolderColumn(Gtk.Box):
    """Uma coluna: lista o conteúdo de uma pasta e destaca o item que está no caminho."""

    __gtype_name__ = "VitrineFolderColumn"

    def __init__(self, strip: "ColumnStrip", folder: Gio.File) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.strip = strip
        self.folder = folder
        self.highlight_uri: str | None = None
        self._programmatic = False
        self._pending_nav = 0
        self.add_css_class("vitrine-column")
        self.set_size_request(strip.column_width, -1)
        self.set_hexpand(False)

        self.dirlist = Gtk.DirectoryList.new(ATTRS, folder)
        self.dirlist.set_monitored(True)
        self.filter = Gtk.CustomFilter.new(self._filter_func, None)
        filtered = Gtk.FilterListModel.new(self.dirlist, self.filter)
        self.sorter = Gtk.CustomSorter.new(self._compare, None)
        sorted_model = Gtk.SortListModel.new(filtered, self.sorter)
        self.selection = Gtk.SingleSelection.new(sorted_model)
        self.selection.set_autoselect(False)
        self.selection.set_can_unselect(True)
        self.selection.connect("selection-changed", self._on_selection_changed)
        sorted_model.connect("items-changed", self._on_items_changed)

        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", self._on_setup)
        factory.connect("bind", self._on_bind)
        self.view = Gtk.ListView.new(self.selection, factory)
        self.view.add_css_class("navigation-sidebar")
        self.view.add_css_class("vitrine-list")
        self.view.connect("activate", self._on_activate)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(self.view)
        self.append(scroller)

        # Clique no espaço vazio da coluna = abrir esta pasta (igual ao Finder).
        bg = Gtk.GestureClick.new()
        bg.set_propagation_phase(Gtk.PropagationPhase.BUBBLE)
        bg.connect("released", self._on_background_click)
        scroller.add_controller(bg)

        # Soltar arquivos no fundo da coluna = mover para esta pasta.
        self._add_drop_target(self, lambda: self.folder.get_uri())

    # ── modelo ──
    def _filter_func(self, info, *_a) -> bool:
        if self.strip.show_hidden:
            return True
        return not (info.get_is_hidden() or info.get_is_backup())

    def _compare(self, a, b, *_a) -> int:
        da, db = _is_dir(a), _is_dir(b)
        if da != db:
            return Gtk.Ordering.SMALLER if da else Gtk.Ordering.LARGER
        ka = GLib.utf8_collate_key_for_filename(a.get_display_name(), -1)
        kb = GLib.utf8_collate_key_for_filename(b.get_display_name(), -1)
        if ka < kb:
            return Gtk.Ordering.SMALLER
        if ka > kb:
            return Gtk.Ordering.LARGER
        return Gtk.Ordering.EQUAL

    def refilter(self) -> None:
        self.filter.changed(Gtk.FilterChange.DIFFERENT)

    def set_highlight(self, uri: str | None) -> None:
        self.highlight_uri = uri
        self._apply_highlight()

    @guarded
    def _on_items_changed(self, *_a) -> None:
        # A lista carrega de forma assíncrona; reaplica o destaque quando o item aparece.
        if self.highlight_uri and self.selection.get_selected_item() is None:
            self._apply_highlight()

    def _apply_highlight(self) -> None:
        model = self.selection.get_model()
        target = None
        if self.highlight_uri:
            for pos in range(model.get_n_items()):
                f = _info_file(model.get_item(pos))
                if f is not None and f.get_uri() == self.highlight_uri:
                    target = pos
                    break
        self._programmatic = True
        try:
            if target is None:
                self.selection.set_selected(Gtk.INVALID_LIST_POSITION)
            else:
                self.selection.set_selected(target)
                self.view.scroll_to(target, Gtk.ListScrollFlags.NONE, None)
        finally:
            self._programmatic = False

    # ── linhas ──
    def _on_setup(self, _factory, item: Gtk.ListItem) -> None:
        row = Gtk.Box(spacing=8)
        row.add_css_class("vitrine-row")
        icon = Gtk.Image()
        icon.set_pixel_size(16)
        label = Gtk.Label(xalign=0, hexpand=True)
        label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        arrow = Gtk.Image.new_from_icon_name("go-next-symbolic")
        arrow.add_css_class("dim-label")
        row.append(icon)
        row.append(label)
        row.append(arrow)
        item.set_child(row)

        # Clique num item que já está destacado (ex.: pasta-pai no caminho) volta para ele.
        primary = Gtk.GestureClick.new()
        primary.set_button(Gdk.BUTTON_PRIMARY)
        primary.connect("released", self._on_row_primary_release, item)
        row.add_controller(primary)

        right = Gtk.GestureClick.new()
        right.set_button(Gdk.BUTTON_SECONDARY)
        right.connect("pressed", self._on_row_right_click, item)
        row.add_controller(right)

        middle = Gtk.GestureClick.new()
        middle.set_button(Gdk.BUTTON_MIDDLE)
        middle.connect("pressed", lambda *_a, it=item: self._open_new_window(it))
        row.add_controller(middle)

        drag = Gtk.DragSource.new()
        drag.set_actions(Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        drag.connect("prepare", self._on_drag_prepare, item)
        row.add_controller(drag)

        self._add_drop_target(row, lambda it=item: self._drop_dest_for(it))

    def _on_bind(self, _factory, item: Gtk.ListItem) -> None:
        info = item.get_item()
        row = item.get_child()
        icon = row.get_first_child()
        label = icon.get_next_sibling()
        arrow = label.get_next_sibling()
        gicon = info.get_icon() or info.get_symbolic_icon()
        if gicon is not None:
            icon.set_from_gicon(gicon)
        label.set_text(info.get_display_name())
        arrow.set_visible(_is_dir(info))
        row.set_tooltip_text(info.get_display_name())

    # ── interação ──
    @guarded
    def _on_selection_changed(self, *_a) -> None:
        if self._programmatic:
            return
        info = self.selection.get_selected_item()
        if info is None:
            return
        f = _info_file(info)
        if f is None:
            return
        self.highlight_uri = f.get_uri()
        # Pequeno atraso: navegar com as setas não recarrega a cada tecla.
        if self._pending_nav:
            GLib.source_remove(self._pending_nav)
        self._pending_nav = GLib.timeout_add(140, self._commit_nav, info)

    @guarded
    def _commit_nav(self, info) -> bool:
        self._pending_nav = 0
        f = _info_file(info)
        if f is None:
            return GLib.SOURCE_REMOVE
        if _is_dir(info):
            target = info.get_attribute_string("standard::target-uri") or f.get_uri()
            self.strip.navigate(target)
        else:
            # Arquivo numa coluna anterior: abre a pasta dele e seleciona o arquivo.
            self.strip.reveal(self.folder.get_uri(), f.get_uri())
        return GLib.SOURCE_REMOVE

    @guarded
    def _on_activate(self, _view, position: int) -> None:
        info = self.selection.get_model().get_item(position)
        f = _info_file(info) if info is not None else None
        if f is not None and not _is_dir(info):
            util.open_uri(f.get_uri())

    @guarded
    def _on_background_click(self, gesture, n_press, x, y) -> None:
        host = gesture.get_widget()
        picked = host.pick(x, y, Gtk.PickFlags.DEFAULT)
        # Só reage se o clique não caiu numa linha.
        w = picked
        while w is not None and w is not host:
            if w.has_css_class("vitrine-row"):
                return
            w = w.get_parent()
        if n_press == 1:
            self.strip.navigate(self.folder.get_uri())

    @guarded
    def _on_row_primary_release(self, _gesture, n_press, _x, _y, item: Gtk.ListItem) -> None:
        if n_press != 1 or self._pending_nav:
            return
        info = item.get_item()
        if info is None:
            return
        f = _info_file(info)
        if f is not None and item.get_selected() and f.get_uri() == self.highlight_uri:
            GLib.idle_add(self._commit_nav, info)

    def _item_file(self, item: Gtk.ListItem) -> tuple[Gio.FileInfo | None, Gio.File | None]:
        info = item.get_item()
        return info, (_info_file(info) if info is not None else None)

    def _open_new_window(self, item: Gtk.ListItem) -> None:
        info, f = self._item_file(item)
        if f is not None and _is_dir(info):
            util.show_in_new_window(f.get_uri())

    @guarded
    def _on_row_right_click(self, gesture, _n, x, y, item: Gtk.ListItem) -> None:
        info, f = self._item_file(item)
        if f is None:
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        uri = f.get_uri()
        is_dir = _is_dir(info)
        row = gesture.get_widget()

        group = Gio.SimpleActionGroup()
        actions = {
            "open": lambda: self.strip.navigate(uri) if is_dir else util.open_uri(uri),
            "new-window": lambda: util.show_in_new_window(uri if is_dir else self.folder.get_uri()),
            "reveal": lambda: self.strip.reveal(self.folder.get_uri(), uri),
            "copy-path": lambda: util.copy_text_to_clipboard(row, f.get_path() or uri),
            "trash": lambda: util.trash_uris([uri]),
        }
        for name, fn in actions.items():
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", lambda *_a, fn=fn: fn())
            group.add_action(act)
        row.insert_action_group("vcol", group)

        menu = Gio.Menu()
        top = Gio.Menu()
        top.append("Abrir", "vcol.open")
        top.append("Abrir em nova janela", "vcol.new-window")
        top.append("Mostrar na lista (todas as ações do Nautilus)", "vcol.reveal")
        menu.append_section(None, top)
        mid = Gio.Menu()
        mid.append("Copiar caminho", "vcol.copy-path")
        menu.append_section(None, mid)
        end = Gio.Menu()
        end.append("Mover para a lixeira", "vcol.trash")
        menu.append_section(None, end)

        pop = Gtk.PopoverMenu.new_from_model(menu)
        pop.set_parent(row)
        pop.set_has_arrow(False)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        pop.set_pointing_to(rect)
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()

    # ── arrastar e soltar ──
    @guarded
    def _on_drag_prepare(self, _src, _x, _y, item: Gtk.ListItem):
        _info, f = self._item_file(item)
        if f is None:
            return None
        flist = Gdk.FileList.new_from_list([f])
        value = GObject.Value()
        value.init(Gdk.FileList)
        value.set_boxed(flist)
        return Gdk.ContentProvider.new_for_value(value)

    def _drop_dest_for(self, item: Gtk.ListItem) -> str | None:
        info, f = self._item_file(item)
        if f is None:
            return None
        return f.get_uri() if _is_dir(info) else self.folder.get_uri()

    def _add_drop_target(self, widget: Gtk.Widget, dest_getter) -> None:
        target = Gtk.DropTarget.new(Gdk.FileList, Gdk.DragAction.COPY | Gdk.DragAction.MOVE)

        @guarded
        def on_drop(tgt, value, _x, _y):
            dest = dest_getter()
            if not dest or value is None:
                return False
            uris = [g.get_uri() for g in value.get_files()]
            uris = [u for u in uris if Gio.File.new_for_uri(u).get_parent() is None
                    or Gio.File.new_for_uri(u).get_parent().get_uri() != dest]
            if not uris:
                return False
            drop = tgt.get_current_drop()
            action = drop.get_actions() if drop is not None else Gdk.DragAction.MOVE
            if action & Gdk.DragAction.MOVE:
                util.move_uris(uris, dest)
            else:
                util.copy_uris(uris, dest)
            return True

        target.connect("drop", on_drop)
        widget.add_controller(target)


class ColumnStrip(Gtk.Box):
    """A faixa de colunas que fica à esquerda da lista nativa."""

    __gtype_name__ = "VitrineColumnStrip"

    def __init__(self, *, column_width: int, max_visible: int, on_navigate, on_reveal) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self.add_css_class("vitrine-strip")
        self.column_width = column_width
        self.max_visible = max(1, max_visible)
        self._on_navigate = on_navigate
        self._on_reveal = on_reveal
        self.columns: list[FolderColumn] = []
        self.location: Gio.File | None = None
        self._nautilus_prefs = Gio.Settings.new("org.gnome.nautilus.preferences")
        self.show_hidden = self._nautilus_prefs.get_boolean("show-hidden-files")
        self._hidden_handler = self._nautilus_prefs.connect(
            "changed::show-hidden-files", self._on_hidden_changed)

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        self.scroller.set_hexpand(False)
        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.scroller.set_child(self.box)
        self.append(self.scroller)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))

    def teardown(self) -> None:
        if self._hidden_handler:
            self._nautilus_prefs.disconnect(self._hidden_handler)
            self._hidden_handler = 0
        self.set_location(None)

    @guarded
    def _on_hidden_changed(self, settings, key) -> None:
        self.show_hidden = settings.get_boolean(key)
        for col in self.columns:
            col.refilter()

    def navigate(self, uri: str) -> None:
        self._on_navigate(uri)

    def reveal(self, folder_uri: str, file_uri: str) -> None:
        self._on_reveal(folder_uri, file_uri)

    def set_location(self, location: Gio.File | None) -> None:
        """Reconstrói as colunas reaproveitando as que não mudaram (evita recarregar)."""
        self.location = location
        chain = chain_for(location) if location is not None else []
        keep = 0
        while (keep < len(chain) and keep < len(self.columns)
               and self.columns[keep].folder.equal(chain[keep])):
            keep += 1
        for col in self.columns[keep:]:
            self.box.remove(col)
            sep = col._vitrine_sep
            if sep is not None:
                self.box.remove(sep)
        self.columns = self.columns[:keep]
        for folder in chain[keep:]:
            col = FolderColumn(self, folder)
            sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
            col._vitrine_sep = sep
            self.box.append(col)
            self.box.append(sep)
            self.columns.append(col)
        # Destaque: em cada coluna, o próximo elemento do caminho.
        path = chain + ([location] if location is not None else [])
        for i, col in enumerate(self.columns):
            nxt = path[i + 1] if i + 1 < len(path) else None
            col.set_highlight(nxt.get_uri() if nxt is not None else None)

        n = len(self.columns)
        visible = min(n, self.max_visible)
        self.scroller.set_size_request(visible * (self.column_width + 1), -1)
        self.set_visible(n > 0)
        GLib.idle_add(self._scroll_to_end)

    def _scroll_to_end(self) -> bool:
        adj = self.scroller.get_hadjustment()
        adj.set_value(max(0.0, adj.get_upper() - adj.get_page_size()))
        return GLib.SOURCE_REMOVE
__VITRINE_ARQUIVO_3__
mkdir -p "vitrine"
cat > 'vitrine/computer.py' <<'__VITRINE_ARQUIVO_4__'
"""Página "Meu computador": pastas, discos e dispositivos (com uso de espaço) e
aviso quando um pen drive, HD externo, cartão ou celular é conectado."""

from __future__ import annotations

import os
import socket
import time

from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

from . import native, util
from .about import build_about_page
from .util import guarded, log

FS_ATTRS = "filesystem::size,filesystem::free,filesystem::type,filesystem::readonly"
USAGE_REFRESH_S = 10
ANNOUNCE_DEDUP_S = 15

# Seções da página (chave em settings.json → "computer_sections").
SECTIONS = (
    ("places", "Pastas", "Pasta pessoal, Documentos, Downloads, as pastas fixadas, Lixeira…"),
    ("devices", "Dispositivos e unidades", "Discos, pen drives, HDs externos, cartões"),
    ("network", "Rede", "Compartilhamentos montados"),
    ("disks_button", "Atalho para o app Discos", "Formatar e particionar"),
)

# Usado só se a barra lateral do Nautilus não puder ser lida.
_FALLBACK_PLACES = (
    ("file://HOME", "Pasta pessoal", "user-home-symbolic", 1),
    ("recent:///", "Recentes", "document-open-recent-symbolic", 1),
    ("starred:///", "Favoritos", "starred-symbolic", 1),
    ("x-network-view:///", "Rede", "network-computer-symbolic", 1),
    ("trash:///", "Lixeira", "user-trash-symbolic", 1),
)
_COLOR_ICON_FIX = {"user-trash-full": "user-trash-full", "user-trash": "user-trash"}

# Pastas principais do usuário, nesta ordem, logo depois da pasta pessoal.
_MAIN_USER_DIRS = (
    GLib.UserDirectory.DIRECTORY_DOCUMENTS,
    GLib.UserDirectory.DIRECTORY_DOWNLOAD,
    GLib.UserDirectory.DIRECTORY_PICTURES,
    GLib.UserDirectory.DIRECTORY_MUSIC,
    GLib.UserDirectory.DIRECTORY_VIDEOS,
)


def _uri_key(uri: str) -> str:
    return uri.rstrip("/") if uri.startswith("file://") else uri


def order_places(entries: list[dict]) -> list[dict]:
    """Um grupo único e previsível: pasta pessoal; Documentos, Downloads, Imagens,
    Músicas, Vídeos; as demais pastas em ordem alfabética; por fim os locais
    especiais (Recentes, Favoritos, Rede, Lixeira…) na ordem da barra lateral."""
    home = _uri_key(Gio.File.new_for_path(os.path.expanduser("~")).get_uri())
    rank = {home: 0}
    for i, kind in enumerate(_MAIN_USER_DIRS, 1):
        path = GLib.get_user_special_dir(kind)
        if path:
            rank.setdefault(_uri_key(Gio.File.new_for_path(path).get_uri()), i)

    def key(item):
        pos, e = item
        uri = _uri_key(e["uri"])
        if uri in rank:
            return (0, rank[uri], "", pos)
        if (GLib.Uri.peek_scheme(e["uri"]) or "") == "file":
            return (1, 0, GLib.utf8_collate_key_for_filename(e["label"], -1), pos)
        return (2, 0, "", pos)

    return [e for _pos, e in sorted(enumerate(entries), key=key)]


def _color_icon(gicon, uri: str) -> Gio.Icon:
    """Versão colorida (não simbólica) de um ícone da barra lateral, para os blocos de 48 px."""
    names = list(gicon.get_names()) if isinstance(gicon, Gio.ThemedIcon) else []
    regular = [n for n in names if not n.endswith("-symbolic")]
    regular += [n[: -len("-symbolic")] for n in names if n.endswith("-symbolic")]
    if (GLib.Uri.peek_scheme(uri) or "") == "file":
        regular.append("folder")
    if not regular:
        return gicon if gicon is not None else Gio.ThemedIcon.new("folder")
    return Gio.ThemedIcon.new_from_names(regular + names)


def _bookmarks_file() -> list[tuple[str, str]]:
    path = os.path.join(GLib.get_user_config_dir(), "gtk-3.0", "bookmarks")
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                uri, _sp, label = line.partition(" ")
                out.append((uri, label or GLib.filename_display_basename(
                    Gio.File.new_for_uri(uri).get_path() or uri)))
    except OSError:
        pass
    return out


def fallback_places() -> list[dict]:
    home = Gio.File.new_for_path(os.path.expanduser("~")).get_uri()
    out = [{"uri": u.replace("file://HOME", home), "label": label,
            "gicon": Gio.ThemedIcon.new(icon), "section": sec, "device": False}
           for u, label, icon, sec in _FALLBACK_PLACES]
    for uri, label in _bookmarks_file():
        out.append({"uri": uri, "label": label, "gicon": Gio.ThemedIcon.new("folder-symbolic"),
                    "section": 2, "device": False})
    return out


def _os_name() -> str:
    try:
        with open("/etc/os-release", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return "Linux"


class Device:
    """Uma entrada da seção de dispositivos (já montada ou não)."""

    __slots__ = ("key", "name", "gicon", "uri", "kind", "mount", "volume", "removable")

    def __init__(self, key, name, gicon, uri, kind, mount=None, volume=None, removable=False):
        self.key, self.name, self.gicon, self.uri = key, name, gicon, uri
        self.kind, self.mount, self.volume, self.removable = kind, mount, volume, removable

    @property
    def mounted(self) -> bool:
        return self.uri is not None

    def can_eject(self) -> bool:
        m = self.mount
        return m is not None and (m.can_eject() or m.can_unmount())


def _volume_key(volume: Gio.Volume) -> str:
    for kind in (Gio.VOLUME_IDENTIFIER_KIND_UUID, Gio.VOLUME_IDENTIFIER_KIND_UNIX_DEVICE):
        ident = volume.get_identifier(kind)
        if ident:
            return f"vol:{ident}"
    return f"vol:{volume.get_name()}"


def _is_removable(mount: Gio.Mount | None, volume: Gio.Volume | None) -> bool:
    drive = (volume.get_drive() if volume is not None else None) or (
        mount.get_drive() if mount is not None else None)
    if drive is not None:
        try:
            if drive.is_removable() or drive.is_media_removable():
                return True
        except AttributeError:
            pass
    return bool(mount is not None and mount.can_eject())


class DeviceHub:
    """Observa o Gio.VolumeMonitor uma vez por processo e avisa os ouvintes."""

    def __init__(self) -> None:
        self.vm = Gio.VolumeMonitor.get()
        self._listeners: list = []
        self._new_listeners: list = []
        self._pending = 0
        self._announced: dict[str, float] = {}
        self.own_mounts: set[str] = set()  # montagens que nós mesmos pedimos
        for sig in ("mount-changed", "mount-removed", "volume-changed", "volume-removed",
                    "drive-connected", "drive-disconnected", "drive-changed"):
            self.vm.connect(sig, lambda *_a: self._changed())
        self.vm.connect("volume-added", self._on_volume_added)
        self.vm.connect("mount-added", self._on_mount_added)

    def on_changed(self, cb) -> None:
        self._listeners.append(cb)

    def on_new_device(self, cb) -> None:
        self._new_listeners.append(cb)

    def _changed(self) -> None:
        if self._pending:
            return
        self._pending = GLib.timeout_add(150, self._emit)

    def _emit(self) -> bool:
        self._pending = 0
        for cb in list(self._listeners):
            try:
                cb()
            except Exception as err:  # noqa: BLE001
                log(f"DeviceHub ouvinte: {err}")
        return GLib.SOURCE_REMOVE

    # ── novos dispositivos ──
    @guarded
    def _on_volume_added(self, _vm, volume: Gio.Volume) -> None:
        self._changed()
        if _is_removable(None, volume):
            self.announce(_volume_key(volume), volume.get_name(), volume=volume)

    @guarded
    def _on_mount_added(self, _vm, mount: Gio.Mount) -> None:
        self._changed()
        volume = mount.get_volume()
        key = _volume_key(volume) if volume is not None else f"mnt:{mount.get_root().get_uri()}"
        if key in self.own_mounts:
            self.own_mounts.discard(key)
            return
        if mount.is_shadowed() or not _is_removable(mount, volume):
            return
        self.announce(key, mount.get_name(), mount=mount, volume=volume)

    def announce(self, key: str, name: str, *, mount=None, volume=None) -> None:
        now = time.monotonic()
        last = self._announced.get(key, 0)
        self._announced[key] = now
        if now - last < ANNOUNCE_DEDUP_S:
            return  # mesmo dispositivo (ex.: volume-added seguido de mount-added)
        log(f"novo dispositivo: {name} ({key})")
        for cb in list(self._new_listeners):
            try:
                cb(key, name, mount, volume)
            except Exception as err:  # noqa: BLE001
                log(f"DeviceHub novo dispositivo: {err}")

    # ── lista atual ──
    def devices(self) -> list[Device]:
        out = [Device("system:/", "Disco do sistema", Gio.ThemedIcon.new("drive-harddisk"),
                      "file:///", "system")]
        seen_volumes = set()
        for mount in self.vm.get_mounts():
            if mount.is_shadowed():
                continue
            volume = mount.get_volume()
            root = mount.get_root()
            uri = root.get_uri()
            scheme = GLib.Uri.peek_scheme(uri) or ""
            if volume is not None:
                seen_volumes.add(_volume_key(volume))
            removable = _is_removable(mount, volume)
            kind = "network" if scheme not in ("file", "") else ("removable" if removable else "internal")
            key = _volume_key(volume) if volume is not None else f"mnt:{uri}"
            out.append(Device(key, mount.get_name(), mount.get_icon(), uri, kind, mount, volume,
                              removable))
        for volume in self.vm.get_volumes():
            key = _volume_key(volume)
            if volume.get_mount() is not None or key in seen_volumes or not volume.can_mount():
                continue
            removable = _is_removable(None, volume)
            out.append(Device(key, volume.get_name(), volume.get_icon(), None,
                              "removable" if removable else "internal", None, volume, removable))
        return out


class ComputerPage(Gtk.ScrolledWindow):
    __gtype_name__ = "VitrineComputerPage"

    def __init__(self, ctl, hub: DeviceHub) -> None:
        super().__init__()
        self.ctl = ctl
        self.hub = hub
        self.add_css_class("vitrine-computer")
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._cards: dict[str, Gtk.FlowBoxChild] = {}
        self._new_keys: dict[str, float] = {}
        self._usage_source = 0
        self._dirty = True
        self._cancel = Gio.Cancellable()
        self._nautilus_prefs = Gio.Settings.new("org.gnome.nautilus.preferences")

        clamp = Adw.Clamp(maximum_size=1100, tightening_threshold=700)
        self.set_child(clamp)
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        body.set_margin_top(24)
        body.set_margin_bottom(24)
        body.set_margin_start(18)
        body.set_margin_end(18)
        clamp.set_child(body)

        title = Gtk.Label(label="Meu computador", xalign=0)
        title.add_css_class("title-1")
        subtitle = Gtk.Label(label=f"{socket.gethostname()} · {_os_name()}", xalign=0)
        subtitle.add_css_class("dim-label")
        # A personalização fica no menu ☰ da linha "Meu computador" na barra lateral.
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
        head.append(title)
        head.append(subtitle)
        body.append(head)

        # Todas as pastas da barra lateral (locais e marcadores) numa grade só.
        self.places_box = self._flowbox(max_per_line=8)
        self.places_box.set_homogeneous(True)
        self.places_box.set_column_spacing(6)
        self.places_box.set_row_spacing(6)
        self.places_box.add_css_class("vitrine-folders")
        self.devices_box = self._flowbox(max_per_line=4)
        self.network_box = self._flowbox(max_per_line=4)
        self.sections: dict[str, Gtk.Widget] = {
            "places": self._section("Pastas", self.places_box),
            "devices": self._section("Dispositivos e unidades", self.devices_box),
            "network": self._section("Rede", self.network_box),
        }
        for widget in self.sections.values():
            body.append(widget)

        self.disks_button = Gtk.Button(label="Abrir Discos (formatar, partições…)",
                                       halign=Gtk.Align.START)
        self.disks_button.add_css_class("flat")
        self.disks_button.connect("clicked", lambda *_: self._launch("gnome-disks"))
        self._has_disks_app = GLib.find_program_in_path("gnome-disks") is not None
        body.append(self.disks_button)
        # Página vazia: o único caminho garantido para a personalização (a linha da
        # barra lateral pode estar oculta e não sobra item para o clique direito).
        self.empty_label = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                                   halign=Gtk.Align.CENTER)
        empty_text = Gtk.Label(label="Tudo oculto. Escolha o que aparece aqui.")
        empty_text.add_css_class("dim-label")
        empty_btn = Gtk.Button(label="Personalizar…", halign=Gtk.Align.CENTER)
        empty_btn.add_css_class("pill")
        empty_btn.connect("clicked", lambda *_: self.ctl.open_settings("customize"))
        self.empty_label.append(empty_text)
        self.empty_label.append(empty_btn)
        body.append(self.empty_label)

        hub.on_changed(self._on_hub_changed)
        self.connect("map", lambda *_: self._on_map())
        self.connect("unmap", lambda *_: self._stop_usage_poll())

    # ── montagem da página ──
    def _section(self, title: str, child: Gtk.Widget) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        lbl = Gtk.Label(label=title, xalign=0)
        lbl.add_css_class("heading")
        box.append(lbl)
        box.append(child)
        return box

    def _flowbox(self, *, max_per_line: int) -> Gtk.FlowBox:
        fb = Gtk.FlowBox()
        fb.set_selection_mode(Gtk.SelectionMode.SINGLE)
        fb.set_max_children_per_line(max_per_line)
        fb.set_min_children_per_line(1)
        fb.set_column_spacing(10)
        fb.set_row_spacing(10)
        fb.set_homogeneous(False)
        fb.set_valign(Gtk.Align.START)
        fb.connect("child-activated", self._on_activated)
        fb.connect("selected-children-changed", self._on_selected)
        return fb

    def _on_map(self) -> None:
        single = self._nautilus_prefs.get_string("click-policy") == "single"
        for fb in self._boxes():
            fb.set_activate_on_single_click(single)
        # A barra lateral pode ter mudado (marcador novo, removido…): sempre remonta.
        self.refresh()
        self._start_usage_poll()

    def _boxes(self):
        return (self.places_box, self.devices_box, self.network_box)

    # ── preferências ──
    def _cfg(self):
        return self.ctl.cfg

    def section_enabled(self, key: str) -> bool:
        return bool((self._cfg().get("computer_sections") or {}).get(key, True))

    def hidden(self) -> set:
        return set(self._cfg().get("computer_hidden") or [])

    def places(self) -> list[dict]:
        """Locais e marcadores da barra lateral (sem os dispositivos, que têm cards
        próprios), num grupo único na ordem de `order_places`."""
        entries = [e for e in native.sidebar_places(self.ctl.win) if not e["device"]]
        if not entries:
            entries = fallback_places()
        seen, out = set(), []
        for e in entries:
            if e["uri"] in seen:
                continue
            seen.add(e["uri"])
            out.append(e)
        return order_places(out)

    def _on_hub_changed(self) -> None:
        self._dirty = True
        if self.get_mapped():
            self.refresh()

    def refresh(self) -> None:
        self._dirty = False
        self._cancel.cancel()
        self._cancel = Gio.Cancellable()
        for fb in self._boxes():
            fb.remove_all()
        self._cards.clear()
        hidden = self.hidden()
        counts = dict.fromkeys(self.sections, 0)

        for entry in self.places():
            if entry["uri"] in hidden:
                continue
            self.places_box.append(self._place_tile(entry))
            counts["places"] += 1

        for dev in self.hub.devices():
            if dev.key in hidden:
                continue
            child = self._device_card(dev)
            self._cards[dev.key] = child
            key = "network" if dev.kind == "network" else "devices"
            (self.network_box if key == "network" else self.devices_box).append(child)
            counts[key] += 1

        any_visible = False
        for key, widget in self.sections.items():
            show = counts[key] > 0 and self.section_enabled(key)
            widget.set_visible(show)
            any_visible = any_visible or show
        self.disks_button.set_visible(self._has_disks_app and self.section_enabled("disks_button"))
        self.empty_label.set_visible(not any_visible)
        self._refresh_usage()

    def _place_tile(self, entry: dict) -> Gtk.FlowBoxChild:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, valign=Gtk.Align.START)
        box.add_css_class("vitrine-tile")
        img = Gtk.Image.new_from_gicon(_color_icon(entry.get("gicon"), entry["uri"]))
        img.set_pixel_size(48)
        # Até duas linhas, centralizadas: nomes longos continuam legíveis.
        lbl = Gtk.Label(label=entry["label"], ellipsize=Pango.EllipsizeMode.END,
                        wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR, lines=2,
                        justify=Gtk.Justification.CENTER, width_chars=10, max_width_chars=12)
        box.append(img)
        box.append(lbl)
        child = Gtk.FlowBoxChild()
        child.set_child(box)
        child.set_tooltip_text(entry["label"])
        child._vitrine_uri = entry["uri"]
        child._vitrine_label = entry["label"]
        child._vitrine_device = None
        self._add_context_menu(child)
        return child

    def _device_card(self, dev: Device) -> Gtk.FlowBoxChild:
        card = Gtk.Box(spacing=12)
        card.add_css_class("card")
        card.add_css_class("vitrine-card")
        card.set_size_request(300, -1)
        img = Gtk.Image()
        if dev.gicon is not None:
            img.set_from_gicon(dev.gicon)
        img.set_pixel_size(48)
        card.append(img)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, hexpand=True,
                       valign=Gtk.Align.CENTER)
        top = Gtk.Box(spacing=6)
        name = Gtk.Label(label=dev.name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        name.add_css_class("heading")
        top.append(name)
        badge = Gtk.Label(label="Novo")
        badge.add_css_class("vitrine-badge")
        badge.set_visible(dev.key in self._new_keys)
        top.append(badge)
        info.append(top)
        bar = Gtk.LevelBar(min_value=0, max_value=1)
        bar.add_css_class("vitrine-usage")
        for off in ("low", "high", "full"):
            bar.remove_offset_value(off)
        bar.add_offset_value("vitrine-ok", 0.80)
        bar.add_offset_value("vitrine-warn", 0.92)
        bar.add_offset_value("vitrine-full", 1.0)
        bar.set_visible(dev.mounted)
        info.append(bar)
        detail = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        detail.add_css_class("dim-label")
        detail.add_css_class("caption")
        detail.set_text("Calculando…" if dev.mounted else "Não montado. Abra para montar")
        info.append(detail)
        card.append(info)

        if dev.can_eject():
            eject = Gtk.Button(icon_name="media-eject-symbolic", valign=Gtk.Align.CENTER)
            eject.add_css_class("flat")
            eject.add_css_class("circular")
            eject.set_tooltip_text("Remover com segurança" if dev.removable else "Desmontar")
            eject.connect("clicked", lambda *_a, d=dev: self.eject(d))
            card.append(eject)

        child = Gtk.FlowBoxChild()
        child.set_child(card)
        child._vitrine_uri = dev.uri
        child._vitrine_device = dev
        child._vitrine_bar = bar
        child._vitrine_detail = detail
        child._vitrine_badge = badge
        if dev.key in self._new_keys:
            card.add_css_class("vitrine-new")
        self._add_context_menu(child)
        return child

    # ── uso de espaço ──
    def _refresh_usage(self) -> None:
        for child in list(self._cards.values()):
            dev = child._vitrine_device
            if dev is None or not dev.mounted:
                continue
            Gio.File.new_for_uri(dev.uri).query_filesystem_info_async(
                FS_ATTRS, GLib.PRIORITY_LOW, self._cancel, self._on_fs_info, child)

    @guarded
    def _on_fs_info(self, gfile, result, child) -> None:
        try:
            info = gfile.query_filesystem_info_finish(result)
        except GLib.Error:
            child._vitrine_detail.set_text(child._vitrine_device.uri or "")
            child._vitrine_bar.set_visible(False)
            return
        size = info.get_attribute_uint64("filesystem::size")
        free = info.get_attribute_uint64("filesystem::free")
        fstype = info.get_attribute_string("filesystem::type") or ""
        if size <= 0:
            child._vitrine_bar.set_visible(False)
            child._vitrine_detail.set_text(fstype or "—")
            return
        child._vitrine_bar.set_value(max(0.0, min(1.0, (size - free) / size)))
        text = f"{util.human_size(free)} livres de {util.human_size(size)}"
        if fstype:
            text += f" · {fstype}"
        child._vitrine_detail.set_text(text)

    def _start_usage_poll(self) -> None:
        if not self._usage_source:
            self._usage_source = GLib.timeout_add_seconds(USAGE_REFRESH_S, self._poll_usage)

    def _stop_usage_poll(self) -> None:
        if self._usage_source:
            GLib.source_remove(self._usage_source)
            self._usage_source = 0

    def _poll_usage(self) -> bool:
        if not self.get_mapped():
            self._usage_source = 0
            return GLib.SOURCE_REMOVE
        self._refresh_usage()
        return GLib.SOURCE_CONTINUE

    # ── novos dispositivos ──
    def mark_new(self, key: str) -> None:
        """Destaca e seleciona o card de um dispositivo recém-conectado."""
        self._new_keys[key] = time.monotonic()
        GLib.timeout_add_seconds(30, self._unmark, key)
        if self._dirty or key not in self._cards:
            self.refresh()
        child = self._cards.get(key)
        if child is not None:
            child.get_child().add_css_class("vitrine-new")
            child._vitrine_badge.set_visible(True)
            self.devices_box.select_child(child)
            if self.get_mapped():
                child.grab_focus()

    def _unmark(self, key: str) -> bool:
        self._new_keys.pop(key, None)
        child = self._cards.get(key)
        if child is not None:
            child.get_child().remove_css_class("vitrine-new")
            child._vitrine_badge.set_visible(False)
        return GLib.SOURCE_REMOVE

    # ── ações ──
    @guarded
    def _on_activated(self, _fb, child) -> None:
        self.open_child(child)

    @guarded
    def _on_selected(self, fb) -> None:
        sel = fb.get_selected_children()
        if not sel:
            return
        for other in self._boxes():
            if other is not fb:
                other.unselect_all()
        uri = getattr(sel[0], "_vitrine_uri", None)
        self.ctl.preview_location(uri)

    def open_child(self, child, *, new_window: bool = False) -> None:
        dev = getattr(child, "_vitrine_device", None)
        uri = getattr(child, "_vitrine_uri", None)
        if uri:
            self._open_uri(uri, new_window)
        elif dev is not None and dev.volume is not None:
            self.mount_and_open(dev.volume, dev.key, new_window=new_window)

    def _open_uri(self, uri: str, new_window: bool) -> None:
        if new_window:
            util.show_in_new_window(uri)
        else:
            self.ctl.leave_computer_and_open(uri)

    def mount_and_open(self, volume: Gio.Volume, key: str, *, new_window: bool = False) -> None:
        mount = volume.get_mount()
        if mount is not None:
            self._open_uri(mount.get_default_location().get_uri(), new_window)
            return
        self.hub.own_mounts.add(key)
        op = Gtk.MountOperation.new(self.get_root())

        def done(vol, result):
            try:
                vol.mount_finish(result)
            except GLib.Error as err:
                self.hub.own_mounts.discard(key)
                if not err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED):
                    self.ctl.toast(f"Não foi possível montar {vol.get_name()}: {err.message}")
                return
            m = vol.get_mount()
            if m is not None:
                self._open_uri(m.get_default_location().get_uri(), new_window)

        volume.mount(Gio.MountMountFlags.NONE, op, None, done)

    def eject(self, dev: Device) -> None:
        mount = dev.mount
        if mount is None:
            return
        op = Gtk.MountOperation.new(self.get_root())
        name = dev.name

        def done(m, result, ejecting):
            try:
                if ejecting:
                    m.eject_with_operation_finish(result)
                else:
                    m.unmount_with_operation_finish(result)
            except GLib.Error as err:
                if not err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED):
                    self.ctl.toast(f"Não foi possível remover {name}: {err.message}")
                return
            self.ctl.toast(f"{name} pode ser removido com segurança" if ejecting
                           else f"{name} foi desmontado")

        if mount.can_eject():
            mount.eject_with_operation(Gio.MountUnmountFlags.NONE, op, None, done, True)
        else:
            mount.unmount_with_operation(Gio.MountUnmountFlags.NONE, op, None, done, False)

    # ── personalização ──
    def set_item_hidden(self, key: str, hide: bool) -> None:
        hidden = self.hidden()
        if hide:
            hidden.add(key)
        else:
            hidden.discard(key)
        self._cfg().set("computer_hidden", sorted(hidden))
        self.ctl.ext.refresh_computer_pages()

    def set_section_enabled(self, key: str, on: bool) -> None:
        sections = dict(self._cfg().get("computer_sections") or {})
        sections[key] = on
        self._cfg().set("computer_sections", sections)
        self.ctl.ext.refresh_computer_pages()

    def open_settings(self, page_name: str = "customize") -> None:
        """Escolher o que aparece no Meu computador e se o Nautilus abre direto nele.
        `page_name`: "customize" ou "about" (abre já na página Sobre)."""
        cfg = self._cfg()
        dialog = Adw.PreferencesDialog(title="Personalizar o Meu computador")
        dialog.set_search_enabled(True)
        page = Adw.PreferencesPage(title="Meu computador", icon_name="computer-symbolic",
                                   name="customize")
        dialog.add(page)
        about_page = build_about_page()
        dialog.add(about_page)

        def switch(group, title, subtitle, active, on_change):
            row = Adw.SwitchRow(title=GLib.markup_escape_text(title),
                                subtitle=GLib.markup_escape_text(subtitle or ""), active=active)
            row.connect("notify::active", lambda r, _p: on_change(r.get_active()))
            group.add(row)
            return row

        style = Adw.PreferencesGroup(
            title="Estilo da janela",
            description="Vale na hora, em todas as janelas abertas")
        first = None
        for value, title, subtitle in (
                ("finder", "Finder (macOS)",
                 "Botões da janela à esquerda, barra de ferramentas em cápsulas, "
                 "barra lateral no estilo do Finder"),
                ("nautilus", "Nautilus padrão",
                 "O visual original do Nautilus. Colunas, pré-visualização e Meu computador "
                 "continuam conforme as opções abaixo")):
            check = Gtk.CheckButton(valign=Gtk.Align.CENTER,
                                    active=cfg.get("window_style") == value)
            if first is None:
                first = check
            else:
                check.set_group(first)
            check.connect("toggled", lambda c, v=value: c.get_active() and cfg.set("window_style", v))
            row = Adw.ActionRow(title=title, subtitle=subtitle, activatable_widget=check)
            row.add_prefix(check)
            style.add(row)
        page.add(style)

        finder = Adw.PreferencesGroup(title="Estilo Finder")
        switch(finder, "Seção Etiquetas na barra lateral",
               "Vermelho, Laranja, Amarelo… Clique para ver os arquivos; arraste arquivos para etiquetar",
               bool(cfg.get("tags_in_sidebar")), lambda v: cfg.set("tags_in_sidebar", v))
        switch(finder, "Dimensões das imagens",
               "Largura × altura abaixo do nome, na visão em grade",
               bool(cfg.get("image_dimensions")), lambda v: cfg.set("image_dimensions", v))
        switch(finder, "Barra de caminho",
               "A hierarquia da pasta atual embaixo, clicável",
               bool(cfg.get("path_bar")), lambda v: cfg.set("path_bar", v))
        switch(finder, "Barra de status",
               "Quantidade de itens e espaço disponível, embaixo",
               bool(cfg.get("status_bar")), lambda v: cfg.set("status_bar", v))
        manage = Adw.ButtonRow(title="Todas as etiquetas…")
        manage.connect("activated", lambda *_a: _open_manager(self.ctl))
        finder.add(manage)
        page.add(finder)

        general = Adw.PreferencesGroup(title="Geral")
        switch(general, "Abrir o Nautilus no Meu computador",
               "Ao abrir o Arquivos pelo menu de aplicativos (ou uma janela nova), começar aqui",
               bool(cfg.get("start_on_computer")), lambda v: cfg.set("start_on_computer", v))
        switch(general, "Mostrar na barra lateral",
               "Entrada \"Meu computador\" no topo da barra lateral",
               bool(cfg.get("computer_in_sidebar")),
               lambda v: (cfg.set("computer_in_sidebar", v), self.ctl.ext.refresh_computer_pages()))
        switch(general, "Avisar quando um dispositivo for conectado",
               "Pen drive, HD externo, cartão de memória, celular",
               bool(cfg.get("notify_new_devices")), lambda v: cfg.set("notify_new_devices", v))
        page.add(general)

        views = Adw.PreferencesGroup(title="Visualização das pastas")
        switch(views, "Descoberta automática de pastas",
               "Fotos e vídeos em ícones extra grandes, documentos em lista. "
               "Escolhas feitas à mão numa pasta têm prioridade",
               bool(cfg.get("folder_discovery")), lambda v: cfg.set("folder_discovery", v))
        page.add(views)

        sections =Adw.PreferencesGroup(title="Seções",
                                        description="Quais blocos aparecem na página")
        for key, title, subtitle in SECTIONS:
            switch(sections, title, subtitle, self.section_enabled(key),
                   lambda v, k=key: self.set_section_enabled(k, v))
        page.add(sections)

        hidden = self.hidden()
        items = Adw.PreferencesGroup(title="Itens",
                                     description="Desligue o que não quer ver no Meu computador")
        for entry in self.places():
            switch(items, entry["label"], "Pasta", entry["uri"] not in hidden,
                   lambda v, u=entry["uri"]: self.set_item_hidden(u, not v))
        for dev in self.hub.devices():
            switch(items, dev.name, "Dispositivo" if dev.kind != "network" else "Rede",
                   dev.key not in hidden, lambda v, k=dev.key: self.set_item_hidden(k, not v))
        page.add(items)

        reset = Adw.PreferencesGroup()
        btn = Gtk.Button(label="Mostrar tudo de novo", halign=Gtk.Align.CENTER)
        btn.add_css_class("pill")

        def do_reset(*_a):
            cfg.set("computer_hidden", [])
            cfg.set("computer_sections", {})
            self.ctl.ext.refresh_computer_pages()
            dialog.close()

        btn.connect("clicked", do_reset)
        reset.add(btn)
        page.add(reset)
        if page_name == "about":
            dialog.set_visible_page(about_page)
        dialog.present(self.ctl.win)
        self._settings_dialog = dialog

    def _launch(self, program: str) -> None:
        try:
            Gio.AppInfo.create_from_commandline(program, None, Gio.AppInfoCreateFlags.NONE).launch(
                [], None)
        except GLib.Error as err:
            log(f"não foi possível abrir {program}: {err.message}")

    # ── menu de contexto ──
    def _add_context_menu(self, child: Gtk.FlowBoxChild) -> None:
        gesture = Gtk.GestureClick.new()
        gesture.set_button(Gdk.BUTTON_SECONDARY)
        gesture.connect("pressed", self._on_right_click, child)
        child.add_controller(gesture)

    @guarded
    def _on_right_click(self, gesture, _n, x, y, child) -> None:
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        dev = child._vitrine_device
        uri = child._vitrine_uri
        group = Gio.SimpleActionGroup()
        menu = Gio.Menu()
        top = Gio.Menu()

        def add(section, label, name, fn):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", lambda *_a: fn())
            group.add_action(act)
            section.append(label, f"vcomp.{name}")

        add(top, "Abrir" if uri else "Montar e abrir", "open", lambda: self.open_child(child))
        add(top, "Abrir em nova janela", "new-window",
            lambda: self.open_child(child, new_window=True))
        menu.append_section(None, top)
        if uri:
            mid = Gio.Menu()
            path = Gio.File.new_for_uri(uri).get_path() or uri
            add(mid, "Copiar caminho", "copy", lambda: util.copy_text_to_clipboard(child, path))
            menu.append_section(None, mid)
        if dev is not None and dev.can_eject():
            end = Gio.Menu()
            add(end, "Remover com segurança" if dev.mount.can_eject() else "Desmontar", "eject",
                lambda: self.eject(dev))
            menu.append_section(None, end)
        hide_key = dev.key if dev is not None else uri
        if hide_key:
            last = Gio.Menu()
            add(last, "Ocultar do Meu computador", "hide", lambda: self.set_item_hidden(hide_key, True))
            add(last, "Personalizar…", "customize", lambda: self.ctl.open_settings("customize"))
            menu.append_section(None, last)
        child.insert_action_group("vcomp", group)
        pop = Gtk.PopoverMenu.new_from_model(menu)
        pop.set_parent(child)
        pop.set_has_arrow(False)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        pop.set_pointing_to(rect)
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()


def _open_manager(ctl) -> None:
    from .tagui import open_manager
    open_manager(ctl)
__VITRINE_ARQUIVO_4__
mkdir -p "vitrine"
cat > 'vitrine/config.py' <<'__VITRINE_ARQUIVO_5__'
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
__VITRINE_ARQUIVO_5__
mkdir -p "vitrine"
cat > 'vitrine/discovery.py' <<'__VITRINE_ARQUIVO_6__'
"""Descoberta automática de pastas: olha uma amostra dos arquivos (tipo MIME pela
extensão, sem ler o conteúdo) e diz se a pasta é de mídia, de documentos ou mista.

    "media"      maioria de fotos/vídeos      → ícones extra grandes
    "documents"  maioria de outros arquivos   → lista
    None         mista, vazia ou poucos itens → visualização padrão

O resultado fica em cache e vale enquanto a pasta não mudar (data de modificação).
Escolhas manuais feitas nesta sessão têm prioridade sobre a descoberta."""

from __future__ import annotations

from gi.repository import Gio, GLib

SAMPLE = 200          # itens lidos no máximo, mesmo em pastas enormes
MIN_FILES = 4         # menos arquivos que isso do tipo predominante → sem palpite
CACHE_MAX = 500
_ATTRS = "standard::name,standard::type,standard::fast-content-type,standard::is-hidden"

_CACHE: dict[str, tuple[int, str | None]] = {}   # uri → (mtime, tipo)
_MANUAL: dict[str, tuple[str, str | None]] = {}  # uri → (modo, zoom) escolhidos à mão


def is_media_type(content_type: str) -> bool:
    return content_type.startswith(("image/", "video/"))


def classify(content_types: list[str], ratio: float) -> str | None:
    """Tipo predominante entre os arquivos amostrados (só arquivos, sem pastas)."""
    total = len(content_types)
    if total == 0:
        return None
    media = sum(1 for t in content_types if is_media_type(t))
    other = total - media
    if media >= MIN_FILES and media / total >= ratio:
        return "media"
    if other >= MIN_FILES and other / total >= ratio:
        return "documents"
    return None


def _fast_type(info: Gio.FileInfo) -> str:
    ctype = info.get_attribute_string("standard::fast-content-type")
    if not ctype or ctype == "application/x-zerosize":  # arquivo vazio: vale a extensão
        ctype, _uncertain = Gio.content_type_guess(info.get_name(), None)
    return ctype or ""


def _store(uri: str, mtime: int, kind: str | None) -> None:
    if len(_CACHE) >= CACHE_MAX:
        _CACHE.pop(next(iter(_CACHE)))
    _CACHE[uri] = (mtime, kind)


def discover(uri: str, ratio: float, callback) -> None:
    """Assíncrono: chama `callback(tipo)` com "media", "documents" ou None."""
    gfile = Gio.File.new_for_uri(uri)
    mtime = [None]

    def on_info(f, res):
        try:
            mtime[0] = f.query_info_finish(res).get_attribute_uint64("time::modified")
        except GLib.Error:
            mtime[0] = None
        hit = _CACHE.get(uri)
        if hit is not None and mtime[0] is not None and hit[0] == mtime[0]:
            callback(hit[1])
            return
        f.enumerate_children_async(_ATTRS, Gio.FileQueryInfoFlags.NONE,
                                   GLib.PRIORITY_DEFAULT, None, on_enum)

    def on_enum(f, res):
        try:
            en = f.enumerate_children_finish(res)
        except GLib.Error:
            callback(None)
            return
        en.next_files_async(SAMPLE, GLib.PRIORITY_DEFAULT, None, on_files)

    def on_files(en, res):
        try:
            infos = en.next_files_finish(res)
        except GLib.Error:
            infos = []
        en.close_async(GLib.PRIORITY_LOW, None, None)
        types = [_fast_type(i) for i in infos
                 if i.get_file_type() == Gio.FileType.REGULAR and not i.get_is_hidden()]
        kind = classify(types, ratio)
        if mtime[0] is not None:
            _store(uri, mtime[0], kind)
        callback(kind)

    gfile.query_info_async("time::modified", Gio.FileQueryInfoFlags.NONE,
                           GLib.PRIORITY_DEFAULT, None, on_info)


# ── escolhas manuais (valem nesta sessão, mesmo sem "lembrar por pasta") ──
def remember_manual(uri: str, mode: str, zoom: str | None) -> None:
    _MANUAL[uri] = (mode, zoom)


def manual_choice(uri: str) -> tuple[str, str | None] | None:
    return _MANUAL.get(uri)


def forget_manual(uri: str) -> None:
    _MANUAL.pop(uri, None)
__VITRINE_ARQUIVO_6__
mkdir -p "vitrine"
cat > 'vitrine/gallery.py' <<'__VITRINE_ARQUIVO_7__'
"""Visualização em Galeria (Ctrl+4): imagem grande do item selecionado, faixa de
miniaturas rolável embaixo (com cabeçalhos de grupo: Hoje, Ontem, Últimos 7 dias…) e
painel com os metadados à direita.

É uma visão da Vitrine, como as Colunas. A lista nativa do Nautilus continua aberta por
baixo e recebe a mesma seleção: Espaço (visualização rápida), Propriedades, Renomear,
Mover para a lixeira e as demais ações do Nautilus valem para o item da Galeria.
"""

from __future__ import annotations

import os
import time

from gi.repository import Gdk, Gio, GLib, Gtk, Pango

from . import imageload, native, util
from .util import guarded, log

ATTRS = ("standard::name,standard::display-name,standard::type,standard::content-type,"
         "standard::icon,standard::size,standard::is-hidden,standard::is-backup,"
         "time::modified,time::created,thumbnail::*")
MAX_ITEMS = 5000
THUMB = 72

GROUPS = (
    ("none", "Nenhum"),
    ("date", "Data de modificação"),
    ("type", "Tipo"),
    ("size", "Tamanho"),
    ("tags", "Etiquetas"),
)


def date_bucket(mtime: float, now: float | None = None) -> tuple[int, str]:
    """(ordem, rótulo) do grupo de data, como no Finder: Hoje, Ontem, Últimos 7 dias,
    Últimos 30 dias, meses do ano atual e, antes disso, o ano."""
    now_dt = GLib.DateTime.new_from_unix_local(int(now if now is not None else time.time()))
    dt = GLib.DateTime.new_from_unix_local(int(mtime))
    today = GLib.DateTime.new_local(now_dt.get_year(), now_dt.get_month(), now_dt.get_day_of_month(), 0, 0, 0)
    days = int((today.to_unix() - GLib.DateTime.new_local(
        dt.get_year(), dt.get_month(), dt.get_day_of_month(), 0, 0, 0).to_unix()) // 86400)
    if days <= 0:
        return 0, "Hoje"
    if days == 1:
        return 1, "Ontem"
    if days < 7:
        return 2, "Últimos 7 dias"
    if days < 30:
        return 3, "Últimos 30 dias"
    if dt.get_year() == now_dt.get_year():
        return 100 - dt.get_month(), f"{_MONTHS[dt.get_month() - 1]}"
    return 1000 + (now_dt.get_year() - dt.get_year()), str(dt.get_year())


_MONTHS = ("Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto",
           "Setembro", "Outubro", "Novembro", "Dezembro")

_SIZES = ((1024 ** 3, "Maiores que 1 GB"), (100 * 1024 ** 2, "100 MB a 1 GB"),
          (1024 ** 2, "1 MB a 100 MB"), (0, "Menores que 1 MB"))


class Item:
    __slots__ = ("uri", "path", "name", "is_dir", "ctype", "size", "mtime", "ctime",
                 "thumb", "icon", "tags", "button", "image")

    def __init__(self, folder: Gio.File, info: Gio.FileInfo, tags) -> None:
        child = folder.get_child(info.get_name())
        self.uri = child.get_uri()
        self.path = child.get_path()
        self.name = info.get_display_name()
        self.is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
        self.ctype = info.get_content_type() or ""
        self.size = info.get_size()
        mod = info.get_modification_date_time()
        self.mtime = mod.to_unix() if mod is not None else 0
        created = info.get_creation_date_time()
        self.ctime = created.to_unix() if created is not None else None
        self.thumb = imageload.best_thumbnail(info)
        self.icon = info.get_icon()
        self.tags = tags.tags_of(self.uri) if self.path else []
        self.button = None
        self.image = None


def group_of(item: Item, mode: str, store) -> tuple:
    if mode == "date":
        return date_bucket(item.mtime)
    if mode == "type":
        label = "Pastas" if item.is_dir else (Gio.content_type_get_description(item.ctype) or "Outros")
        return (0 if item.is_dir else 1, label.lower()), label
    if mode == "size":
        if item.is_dir:
            return 99, "Pastas"
        for i, (limit, label) in enumerate(_SIZES):
            if item.size >= limit:
                return i, label
    if mode == "tags":
        names = store.names()
        for i, name in enumerate(names):
            if name in item.tags:
                return i, name
        return 999, "Sem etiqueta"
    return 0, ""


def sort_key(item: Item, mode: str, store):
    name = GLib.utf8_collate_key_for_filename(item.name, -1)
    if mode == "date":
        return (group_of(item, mode, store)[0], -item.mtime, name)
    if mode == "size":
        return (group_of(item, mode, store)[0], -item.size, name)
    return (group_of(item, mode, store)[0], not item.is_dir, name)


class GalleryView(Gtk.Box):
    __gtype_name__ = "VitrineGalleryView"

    def __init__(self, ctl) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self.add_css_class("vitrine-gallery")
        self.ctl = ctl
        self.folder: Gio.File | None = None
        self.items: list[Item] = []
        self.selected: Item | None = None
        self._cancel = Gio.Cancellable()
        self._monitor = None
        self._reload_source = 0
        self._load_token = 0
        self._prefs = Gio.Settings.new("org.gnome.nautilus.preferences")
        self.set_focusable(True)

        # imagem grande + faixa
        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        self.stage = Gtk.Stack(vexpand=True, transition_type=Gtk.StackTransitionType.CROSSFADE,
                               transition_duration=120)
        self.picture = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True)
        self.picture.add_css_class("vitrine-gallery-picture")
        self.picture.set_overflow(Gtk.Overflow.HIDDEN)  # cantos arredondados cortam a imagem
        self.big_icon = Gtk.Image(pixel_size=160)
        self.empty = Gtk.Label(label="Pasta vazia")
        self.empty.add_css_class("dim-label")
        self.empty.add_css_class("title-2")
        for name, w in (("picture", self.picture), ("icon", self.big_icon), ("empty", self.empty)):
            self.stage.add_named(w, name)
        stage_frame = Gtk.Box(vexpand=True)
        stage_frame.add_css_class("vitrine-gallery-stage")
        self.stage.set_hexpand(True)
        stage_frame.append(self.stage)
        main.append(stage_frame)
        self.strip = Gtk.Box(spacing=6, valign=Gtk.Align.CENTER)
        self.strip.add_css_class("vitrine-gallery-strip")
        self.scroller = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER,
                                           hscrollbar_policy=Gtk.PolicyType.AUTOMATIC,
                                           child=self.strip)
        self.scroller.set_size_request(-1, THUMB + 54)
        main.append(self.scroller)
        self.append(main)

        # metadados
        self.info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, width_request=260)
        self.info.add_css_class("vitrine-gallery-info")
        self.title = Gtk.Label(xalign=0, wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR)
        self.title.add_css_class("title-4")
        self.kind = Gtk.Label(xalign=0, wrap=True)
        self.kind.add_css_class("dim-label")
        self.grid = Gtk.Grid(column_spacing=10, row_spacing=6, margin_top=12)
        self.tags_box = Gtk.Box(spacing=4, margin_top=8)
        self.open_btn = Gtk.Button(label="Abrir", halign=Gtk.Align.START, margin_top=12)
        self.open_btn.add_css_class("pill")
        self.open_btn.connect("clicked", lambda *_a: self.selected and self.activate_item(self.selected))
        for w in (self.title, self.kind, self.tags_box, self.grid, self.open_btn):
            self.info.append(w)
        self.append(self.info)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)
        self._prefs.connect("changed::show-hidden-files", lambda *_a: self.reload())
        ctl.ext.tags.on_change(lambda: self.get_mapped() and self.reload())

    # ── pasta ──
    def set_folder(self, uri: str | None) -> None:
        folder = Gio.File.new_for_uri(uri) if uri else None
        if folder is not None and self.folder is not None and folder.equal(self.folder) and self.items:
            return
        self.folder = folder
        self.selected = None
        self._watch()
        self.reload()

    def _watch(self) -> None:
        if self._monitor is not None:
            self._monitor.cancel()
            self._monitor = None
        if self.folder is None:
            return
        try:
            self._monitor = self.folder.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            self._monitor.connect("changed", lambda *_a: self._reload_soon())
        except GLib.Error:
            self._monitor = None

    def _reload_soon(self) -> None:
        if self._reload_source:
            return
        self._reload_source = GLib.timeout_add(400, self._reload_now)

    def _reload_now(self) -> bool:
        self._reload_source = 0
        if self.get_mapped():
            self.reload()
        return GLib.SOURCE_REMOVE

    def reload(self) -> None:
        self._cancel.cancel()
        self._cancel = Gio.Cancellable()
        self._load_token += 1
        token = self._load_token
        if self.folder is None:
            self._show([])
            return
        keep = self.selected.uri if self.selected is not None else None
        show_hidden = self._prefs.get_boolean("show-hidden-files")
        folder = self.folder
        infos: list = []

        def on_enum(f, res):
            try:
                en = f.enumerate_children_finish(res)
            except GLib.Error as err:
                if not err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED):
                    log(f"galeria: {err.message}")
                    self._show([])
                return
            en.next_files_async(200, GLib.PRIORITY_DEFAULT, self._cancel, on_files)

        def on_files(en, res):
            try:
                batch = en.next_files_finish(res)
            except GLib.Error:
                return
            if token != self._load_token:
                return
            for info in batch:
                if show_hidden or not (info.get_is_hidden() or info.get_is_backup()):
                    infos.append(info)
            if batch and len(infos) < MAX_ITEMS:
                en.next_files_async(200, GLib.PRIORITY_DEFAULT, self._cancel, on_files)
                return
            en.close_async(GLib.PRIORITY_LOW, None, None)
            items = [Item(folder, i, self.ctl.ext.tags) for i in infos]
            self._show(items, keep)

        folder.enumerate_children_async(ATTRS, Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT,
                                        self._cancel, on_enum)

    # ── montagem da faixa ──
    def group_mode(self) -> str:
        mode = self.ctl.cfg.get("gallery_group_by")
        return mode if mode in dict(GROUPS) else "date"

    def _show(self, items: list[Item], keep: str | None = None) -> None:
        store = self.ctl.ext.tags
        mode = self.group_mode()
        items.sort(key=lambda it: sort_key(it, mode, store))
        self.items = items
        child = self.strip.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.strip.remove(child)
            child = nxt
        last = None
        for item in items:
            if mode != "none":
                key, label = group_of(item, mode, store)
                if key != last:
                    head = Gtk.Label(label=label, valign=Gtk.Align.CENTER)
                    head.add_css_class("vitrine-gallery-group")
                    self.strip.append(head)
                    last = key
            self.strip.append(self._button(item))
        if not items:
            self.selected = None
            self.stage.set_visible_child_name("empty")
            self._fill_info(None)
            return
        target = next((it for it in items if it.uri == keep), items[0])
        self.select(target, sync_native=False)

    def _button(self, item: Item) -> Gtk.Button:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        image = Gtk.Picture(content_fit=Gtk.ContentFit.COVER, can_shrink=True)
        image.set_size_request(THUMB, THUMB)
        image.add_css_class("vitrine-gallery-thumb")
        image.set_overflow(Gtk.Overflow.HIDDEN)
        if item.thumb:
            image.set_filename(item.thumb)
        else:
            icon = Gtk.Image.new_from_gicon(item.icon) if item.icon else Gtk.Image.new_from_icon_name("text-x-generic")
            icon.set_pixel_size(THUMB - 16)
            icon.set_size_request(THUMB, THUMB)
            image = icon
        box.append(image)
        dots = Gtk.Box(spacing=2, halign=Gtk.Align.CENTER, height_request=8)
        for t in item.tags[:4]:
            d = Gtk.Image.new_from_icon_name(f"vitrine-tag-{self.ctl.ext.tags.color_of(t)}")
            d.set_pixel_size(8)
            dots.append(d)
        box.append(dots)
        btn = Gtk.Button(child=box, tooltip_text=item.name)
        btn.add_css_class("flat")
        btn.add_css_class("vitrine-gallery-item")
        btn.connect("clicked", lambda *_a, it=item: self.select(it))
        double = Gtk.GestureClick(button=Gdk.BUTTON_PRIMARY)
        double.connect("pressed", lambda g, n, *_a, it=item: n == 2 and self.activate_item(it))
        btn.add_controller(double)
        menu = Gtk.GestureClick(button=Gdk.BUTTON_SECONDARY)
        menu.connect("pressed", self._on_menu, item)
        btn.add_controller(menu)
        item.button = btn
        return btn

    # ── seleção ──
    def select(self, item: Item, *, sync_native: bool = True) -> None:
        if self.selected is not None and self.selected.button is not None:
            self.selected.button.remove_css_class("selected")
        self.selected = item
        if item.button is not None:
            item.button.add_css_class("selected")
            GLib.idle_add(self._scroll_to, item)
        self._stage(item)
        self._fill_info(item)
        if sync_native:
            self._sync_native(item)

    def _scroll_to(self, item: Item) -> bool:
        btn = item.button
        if btn is None or not btn.get_mapped():
            return GLib.SOURCE_REMOVE
        ok, rect = btn.compute_bounds(self.strip)
        if ok:
            adj = self.scroller.get_hadjustment()
            x, w = rect.get_x(), rect.get_width()
            page = adj.get_page_size()
            if x < adj.get_value():
                adj.set_value(max(0, x - 24))
            elif x + w > adj.get_value() + page:
                adj.set_value(x + w - page + 24)
        return GLib.SOURCE_REMOVE

    def _sync_native(self, item: Item) -> None:
        model = native.find_model(self.ctl.active_slot())
        if model is not None:
            native.select_uris(model, [item.uri])

    def _stage(self, item: Item) -> None:
        token = self._load_token
        if item.path and item.ctype.startswith("image/"):
            if item.thumb:
                self.picture.set_filename(item.thumb)
                self.stage.set_visible_child_name("picture")
            else:
                self.big_icon.set_from_gicon(item.icon)
                self.stage.set_visible_child_name("icon")

            def done(fut):
                try:
                    tex = fut.result()[0]
                except Exception as err:  # noqa: BLE001
                    log(f"galeria: {item.name}: {err}")
                    return
                GLib.idle_add(apply, tex)

            def apply(tex):
                if token == self._load_token and self.selected is item:
                    self.picture.set_paintable(tex)
                    self.stage.set_visible_child_name("picture")
                return GLib.SOURCE_REMOVE

            imageload.EXECUTOR.submit(imageload.load, item.path, item.ctype).add_done_callback(done)
        elif item.thumb:
            self.picture.set_filename(item.thumb)
            self.stage.set_visible_child_name("picture")
        else:
            if item.icon is not None:
                self.big_icon.set_from_gicon(item.icon)
            self.stage.set_visible_child_name("icon")

    def _fill_info(self, item: Item | None) -> None:
        child = self.grid.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.grid.remove(child)
            child = nxt
        child = self.tags_box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.tags_box.remove(child)
            child = nxt
        self.info.set_visible(item is not None)
        if item is None:
            return
        self.title.set_label(item.name)
        self.kind.set_label("Pasta" if item.is_dir else (Gio.content_type_get_description(item.ctype) or ""))
        rows = []
        if not item.is_dir:
            rows.append(("Tamanho", util.human_size(item.size)))
        if item.path and item.ctype in ("image/jpeg", "image/png"):
            pr = imageload.probe(item.path, item.ctype)
            if pr.width and pr.height:
                w, h = (pr.height, pr.width) if pr.orientation in (5, 6, 7, 8) else (pr.width, pr.height)
                rows.append(("Dimensões", f"{w:,} × {h:,}".replace(",", ".")))
        rows.append(("Modificado", _fmt(item.mtime)))
        if item.ctime:
            rows.append(("Criado", _fmt(item.ctime)))
        for i, (k, v) in enumerate(rows):
            key = Gtk.Label(label=k, xalign=1)
            key.add_css_class("dim-label")
            self.grid.attach(key, 0, i, 1, 1)
            self.grid.attach(Gtk.Label(label=v, xalign=0, wrap=True, selectable=True), 1, i, 1, 1)
        for t in item.tags:
            d = Gtk.Image.new_from_icon_name(f"vitrine-tag-{self.ctl.ext.tags.color_of(t)}")
            d.set_pixel_size(10)
            self.tags_box.append(d)
            self.tags_box.append(Gtk.Label(label=t, margin_end=8))
        self.tags_box.set_visible(bool(item.tags))
        self.open_btn.set_label("Abrir pasta" if item.is_dir else "Abrir")

    # ── ações ──
    def activate_item(self, item: Item) -> None:
        if item.is_dir:
            self.ctl.navigate(item.uri)
        else:
            util.open_uri(item.uri)

    def move(self, delta: int) -> None:
        if not self.items:
            return
        i = self.items.index(self.selected) if self.selected in self.items else -1
        self.select(self.items[max(0, min(len(self.items) - 1, i + delta))])

    @guarded
    def _on_key(self, _ctrl, keyval, _code, state) -> bool:
        if state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK):
            return False
        if keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self.move(-1)
        elif keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self.move(+1)
        elif keyval == Gdk.KEY_Home and self.items:
            self.select(self.items[0])
        elif keyval == Gdk.KEY_End and self.items:
            self.select(self.items[-1])
        elif keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and self.selected is not None:
            self.activate_item(self.selected)
        elif keyval == Gdk.KEY_space and self.selected is not None:
            self._sync_native(self.selected)
            self.ctl.quicklook()
        else:
            return False
        return True

    @guarded
    def _on_menu(self, gesture, _n, x, y, item: Item) -> None:
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.select(item)
        from .finder.toolbar import nt  # rótulos com os nomes do GNOME

        menu = Gio.Menu()
        top = Gio.Menu()
        top.append(nt("_Open", "Abrir"), "vgallery.open")
        top.append(nt("Open _With…", "Abrir com…"), "view.open-with-other-application")
        menu.append_section(None, top)
        mid = Gio.Menu()
        mid.append(nt("Rena_me…", "Renomear…"), "view.rename")
        mid.append(nt("C_ompress…", "Comprimir…"), "view.compress")
        mid.append(nt("_Copy", "Copiar"), "view.copy")
        mid.append(nt("Mo_ve to Trash", "Mover para a lixeira"), "view.move-to-trash")
        menu.append_section(None, mid)
        end = Gio.Menu()
        end.append(nt("P_roperties", "Propriedades"), "view.properties")
        menu.append_section(None, end)
        group = Gio.SimpleActionGroup()
        act = Gio.SimpleAction.new("open", None)
        act.connect("activate", lambda *_a: self.activate_item(item))
        group.add_action(act)
        btn = item.button
        btn.insert_action_group("vgallery", group)
        pop = Gtk.PopoverMenu.new_from_model(menu)
        pop.set_parent(btn)
        pop.set_has_arrow(False)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        pop.set_pointing_to(rect)
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()


def _fmt(ts: float | None) -> str:
    if not ts:
        return "—"
    return GLib.DateTime.new_from_unix_local(int(ts)).format("%d/%m/%Y %H:%M")
__VITRINE_ARQUIVO_7__
mkdir -p "vitrine"
cat > 'vitrine/history.py' <<'__VITRINE_ARQUIVO_8__'
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
__VITRINE_ARQUIVO_8__
mkdir -p "vitrine"
cat > 'vitrine/imageload.py' <<'__VITRINE_ARQUIVO_9__'
"""Carregamento rápido de imagens para o preview.

No Fedora 45 o gdk-pixbuf usa o glycin, que abre um processo isolado (sandbox)
para cada imagem: ~50 ms só para ler as dimensões e ~70 ms+ para decodificar.
Aqui:

* JPEG/PNG/TIFF vão pelo decodificador interno do GTK (sem sandbox, ~3x mais rápido);
* dimensões e rotação EXIF são lidas direto do cabeçalho do arquivo, em Python;
* só fotos rotacionadas, gigantes ou de outros formatos (WebP, HEIC, AVIF…) usam o glycin;
* imagens já vistas ficam num cache; as vizinhas são pré-carregadas.
"""

from __future__ import annotations

import os
import struct
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio  # noqa: E402

FAST_TYPES = ("image/jpeg", "image/png", "image/tiff")
FAST_MAX_PIXELS = 40_000_000  # acima disso, decodifica já reduzida (economiza memória)
SCALED_MAX_PX = 1600
HEADER_BYTES = 256 * 1024

EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="vitrine-img")


class Probe:
    __slots__ = ("width", "height", "orientation")

    def __init__(self, width=0, height=0, orientation=1) -> None:
        self.width, self.height, self.orientation = width, height, orientation


def _probe_jpeg(data: bytes) -> Probe:
    p = Probe()
    if data[:2] != b"\xff\xd8":
        return p
    i = 2
    n = len(data)
    while i + 4 <= n:
        if data[i] != 0xFF:
            break
        marker = data[i + 1]
        if marker == 0xFF:  # bytes de preenchimento
            i += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        if marker in (0xD9, 0xDA):  # fim da imagem / início dos dados
            break
        seg_len = struct.unpack(">H", data[i + 2:i + 4])[0]
        seg = data[i + 4:i + 2 + seg_len]
        if marker == 0xE1 and seg[:6] == b"Exif\x00\x00":
            p.orientation = _exif_orientation(seg[6:]) or 1
        elif marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            if len(seg) >= 5:
                p.height, p.width = struct.unpack(">HH", seg[1:5])
            break
        i += 2 + seg_len
    return p


def _exif_orientation(tiff: bytes) -> int:
    if len(tiff) < 8 or tiff[:2] not in (b"II", b"MM"):
        return 1
    e = "<" if tiff[:2] == b"II" else ">"
    ifd = struct.unpack(e + "I", tiff[4:8])[0]
    if ifd + 2 > len(tiff):
        return 1
    count = struct.unpack(e + "H", tiff[ifd:ifd + 2])[0]
    for k in range(count):
        off = ifd + 2 + 12 * k
        if off + 12 > len(tiff):
            break
        if struct.unpack(e + "H", tiff[off:off + 2])[0] == 0x0112:
            return struct.unpack(e + "H", tiff[off + 8:off + 10])[0]
    return 1


def probe(path: str, ct: str) -> Probe:
    """Dimensões e orientação lidas do cabeçalho, sem decodificar a imagem."""
    try:
        with open(path, "rb") as fh:
            data = fh.read(HEADER_BYTES if ct == "image/jpeg" else 64)
    except OSError:
        return Probe()
    if ct == "image/jpeg":
        return _probe_jpeg(data)
    if ct == "image/png" and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return Probe(w, h, 1)
    return Probe()


def guess_type(path: str) -> str:
    ct, _uncertain = Gio.content_type_guess(path, None)
    return ct or ""


def cache_key(path: str):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return (path, st.st_mtime_ns, st.st_size)


def load(path: str, ct: str):
    """Roda numa thread. Devolve (textura, largura_original, altura_original)."""
    pr = probe(path, ct)
    pixels = pr.width * pr.height
    if ct in FAST_TYPES and pr.orientation == 1 and pixels <= FAST_MAX_PIXELS:
        tex = Gdk.Texture.new_from_filename(path)
        return tex, (pr.width or tex.get_width()), (pr.height or tex.get_height())
    # Caminho lento (glycin): foto girada pelo EXIF, gigante ou formato não-nativo.
    pix = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, SCALED_MAX_PX, SCALED_MAX_PX, True)
    pix = pix.apply_embedded_orientation() or pix
    w, h = pr.width, pr.height
    if pr.orientation in (5, 6, 7, 8):
        w, h = h, w
    return Gdk.Texture.new_for_pixbuf(pix), w, h


class TextureCache:
    """LRU em memória, limitado por quantidade e por total de pixels."""

    def __init__(self, max_items: int = 24, max_pixels: int = 160_000_000) -> None:
        self._items: OrderedDict = OrderedDict()
        self._max_items = max_items
        self._max_pixels = max_pixels
        self._pixels = 0

    def get(self, key):
        val = self._items.get(key)
        if val is not None:
            self._items.move_to_end(key)
        return val

    def __contains__(self, key) -> bool:
        return key in self._items

    def put(self, key, val) -> None:
        if key is None or key in self._items:
            return
        tex = val[0]
        self._items[key] = val
        self._pixels += tex.get_width() * tex.get_height()
        while self._items and (len(self._items) > self._max_items or self._pixels > self._max_pixels):
            _k, (old, _w, _h) = self._items.popitem(last=False)
            self._pixels -= old.get_width() * old.get_height()


CACHE = TextureCache()


def best_thumbnail(info: Gio.FileInfo) -> str | None:
    """A maior miniatura que o Nautilus/GNOME já gerou para o arquivo (carrega em ~1 ms)."""
    for suffix in ("-xxlarge", "-xlarge", "-large", "", "-normal"):
        path = info.get_attribute_byte_string(f"thumbnail::path{suffix}")
        if not path:
            continue
        valid_attr = f"thumbnail::is-valid{suffix}"
        if info.has_attribute(valid_attr) and not info.get_attribute_boolean(valid_attr):
            continue
        if os.path.exists(path):
            return path
    return None


THUMB_ATTRS = ",".join(
    f"thumbnail::{k}{s}"
    for s in ("", "-normal", "-large", "-xlarge", "-xxlarge")
    for k in ("path", "is-valid")
)
__VITRINE_ARQUIVO_9__
mkdir -p "vitrine"
cat > 'vitrine/main.py' <<'__VITRINE_ARQUIVO_10__'
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
__VITRINE_ARQUIVO_10__
mkdir -p "vitrine"
cat > 'vitrine/native.py' <<'__VITRINE_ARQUIVO_11__'
"""Ponte com as partes internas do Nautilus (aba/slot, modo de visualização, seleção).

Regra de ouro: nunca guardar referência forte a widgets ou modelos do Nautilus.
Tudo é procurado sob demanda; o modelo de seleção é acompanhado por weak_ref.
"""

from __future__ import annotations

from gi.repository import Adw, Gio, GLib, Gtk

from .util import debug, find_first, gtype_name, log, walk

# Locais onde o Nautilus fixa a própria visualização (não aplicamos regras).
SPECIAL_SCHEMES = ("recent", "starred", "trash", "x-network-view", "network", "computer",
                   "search", "other-locations", "burn", "admin-root")


def is_nautilus_window(win) -> bool:
    return gtype_name(win) == "NautilusWindow"


def find_tab_view(win) -> Adw.TabView | None:
    return find_first(win, lambda w: isinstance(w, Adw.TabView))


def active_slot(win):
    tv = find_tab_view(win)
    if tv is None:
        return None
    page = tv.get_selected_page()
    return page.get_child() if page is not None else None


def slot_location(slot) -> Gio.File | None:
    if slot is None:
        return None
    try:
        return slot.get_property("location")
    except TypeError:
        return None


def slot_uri(slot) -> str | None:
    loc = slot_location(slot)
    return loc.get_uri() if loc is not None else None


def is_regular_location(uri: str | None) -> bool:
    if not uri:
        return False
    scheme = GLib.Uri.peek_scheme(uri) or ""
    return scheme not in SPECIAL_SCHEMES


def open_location(slot, uri: str) -> bool:
    if slot is None:
        return False
    return bool(slot.activate_action("slot.open-location", GLib.Variant("s", uri)))


# ── barra lateral nativa ──

def _prop(obj, name):
    try:
        return obj.get_property(name)
    except (TypeError, AttributeError):
        return None


def sidebar_places(win) -> list[dict]:
    """Os locais da barra lateral do Nautilus, na mesma ordem e com os mesmos nomes.

    Lê as propriedades de cada NautilusSidebarRow (uri, label, start-icon…).
    Linhas de dispositivos (com mount/volume/drive) vêm marcadas em `device`."""
    sidebar = find_first(win, lambda w: gtype_name(w) == "NautilusSidebar")
    if sidebar is None:
        return []
    out = []
    for row in walk(sidebar):
        if gtype_name(row) != "NautilusSidebarRow":
            continue
        uri = _prop(row, "uri")
        label = _prop(row, "label")
        if not uri or not label or _prop(row, "placeholder"):
            continue
        if row.has_css_class("sidebar-new-bookmark-row"):
            continue
        device = any(_prop(row, p) is not None for p in ("mount", "volume", "drive"))
        out.append({
            "uri": uri,
            "label": label,
            "gicon": _prop(row, "start-icon"),
            "section": int(_prop(row, "section-type") or 0),
            "place": int(_prop(row, "place-type") or 0),
            "device": device,
            "visible": row.get_visible(),
        })
    return out


# ── modo de visualização (lista/grade) ──

def _files_view(slot):
    return find_first(slot, lambda w: gtype_name(w) == "NautilusFilesView")


def view_mode(slot) -> str | None:
    """'list' ou 'grid' conforme o widget que o Nautilus está mostrando agora."""
    root = _files_view(slot) or slot
    for w in walk(root):
        name = gtype_name(w)
        if name == "NautilusGridView":
            return "grid"
        if name == "NautilusListView":
            return "list"
    return None


def set_view_mode(slot, mode: str) -> bool:
    """Leva o slot para 'list' ou 'grid' usando a ação nativa de alternância."""
    current = view_mode(slot)
    if current is None or current == mode:
        return False
    ok = slot.activate_action("slot.files-view-mode-toggle", None)
    debug(f"set_view_mode {current}->{mode} via toggle ok={ok}")
    return bool(ok)


def zoom_in(widget) -> None:
    widget.activate_action("view.zoom-in", None)


def preview_with_sushi(widget) -> bool:
    """Mesma coisa que apertar Espaço no Nautilus."""
    return bool(widget.activate_action("view.preview-selection", None))


# ── seleção (NautilusViewModel é um Gtk.SelectionModel) ──

def find_model(slot):
    root = _files_view(slot) or slot
    for w in walk(root):
        if isinstance(w, (Gtk.ColumnView, Gtk.ListView, Gtk.GridView)):
            model = w.get_model()
            if model is not None and gtype_name(model) == "NautilusViewModel":
                return model
    return None


def _item_uri(item) -> str | None:
    if isinstance(item, Gtk.TreeListRow):
        item = item.get_item()
    if item is None:
        return None
    try:
        info = item.get_property("file")
    except TypeError:
        return None
    try:
        return info.get_uri() if info is not None else None
    except Exception:  # noqa: BLE001
        return None


def selected_uris(model, limit: int = 2000) -> list[str]:
    if model is None:
        return []
    bitset = model.get_selection()
    out = []
    n = min(bitset.get_size(), limit)
    for i in range(n):
        uri = _item_uri(model.get_item(bitset.get_nth(i)))
        if uri:
            out.append(uri)
    return out


def neighbor_uris(model, offsets=(1, -1, 2, -2)) -> list[str]:
    """Itens ao redor do único item selecionado (para pré-carregar o preview)."""
    if model is None:
        return []
    bitset = model.get_selection()
    if bitset.get_size() != 1:
        return []
    pos = bitset.get_nth(0)
    n = model.get_n_items()
    out = []
    for d in offsets:
        p = pos + d
        if 0 <= p < n:
            uri = _item_uri(model.get_item(p))
            if uri:
                out.append(uri)
    return out


def select_uris(model, uris: list[str]) -> bool:
    """Seleciona (e retorna True se achou) os itens com estes URIs no modelo nativo."""
    if model is None or not uris:
        return False
    wanted = {Gio.File.new_for_uri(u).get_uri() for u in uris}
    n = model.get_n_items()
    sel = Gtk.Bitset.new_empty()
    found = False
    for pos in range(n):
        uri = _item_uri(model.get_item(pos))
        if uri in wanted:
            sel.add(pos)
            found = True
    if found:
        model.set_selection(sel, Gtk.Bitset.new_range(0, n))
    return found


class ModelWatch:
    """Um handler de 'selection-changed' no modelo nativo, sem segurá-lo vivo."""

    def __init__(self, callback) -> None:
        self._callback = callback
        self._ref = None
        self._handler = 0

    def get(self):
        return self._ref() if self._ref is not None else None

    def bind(self, model) -> bool:
        if model is not None and model == self.get():
            return False
        self.unbind()
        if model is not None:
            self._ref = model.weak_ref(self._on_finalized)
            self._handler = model.connect("selection-changed", self._on_changed)
            debug("ModelWatch: ligado a novo NautilusViewModel")
        return True

    def unbind(self) -> None:
        model = self.get()
        if model is not None and self._handler:
            try:
                model.disconnect(self._handler)
            except Exception:  # noqa: BLE001
                pass
        self._ref = None
        self._handler = 0

    def _on_finalized(self, *_a) -> None:
        self._ref = None
        self._handler = 0

    def _on_changed(self, model, _pos, _n) -> None:
        try:
            self._callback(model)
        except Exception as err:  # noqa: BLE001
            log(f"ModelWatch callback: {err}")
__VITRINE_ARQUIVO_11__
mkdir -p "vitrine"
cat > 'vitrine/preview.py' <<'__VITRINE_ARQUIVO_12__'
"""Painel de pré-visualização à direita: imagem, texto, miniatura de vídeo/PDF e informações."""

from __future__ import annotations

import threading

import gi

from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import imageload, util  # noqa: E402
from .util import guarded, log  # noqa: E402

try:
    gi.require_version("GnomeDesktop", "4.0")
    from gi.repository import GnomeDesktop  # noqa: E402

    _THUMB_FACTORY = GnomeDesktop.DesktopThumbnailFactory.new(
        GnomeDesktop.DesktopThumbnailSize.XLARGE
    )
except Exception:  # noqa: BLE001
    _THUMB_FACTORY = None

INFO_ATTRS = ",".join(
    (
        "standard::*",
        "time::modified",
        "time::created",
        "time::access",
        imageload.THUMB_ATTRS,
        "access::can-read",
        "unix::mode",
        "owner::user",
    )
)
PREFETCH_MAX = 4
TEXT_MAX_BYTES = 256 * 1024
TEXT_MAX_LINES = 400
FOLDER_LIST_MAX = 300


def _is_text(ct: str) -> bool:
    return bool(ct) and (
        Gio.content_type_is_a(ct, "text/plain")
        or ct in ("application/json", "application/xml", "application/x-yaml",
                  "application/toml", "application/javascript", "application/x-shellscript")
    )


class PreviewPane(Gtk.Box):
    __gtype_name__ = "VitrinePreviewPane"

    def __init__(self, *, on_navigate, on_reveal, on_quicklook) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.add_css_class("vitrine-preview")
        self._on_navigate = on_navigate
        self._on_reveal = on_reveal
        self._on_quicklook = on_quicklook
        self._cancel: Gio.Cancellable | None = None
        self._token = 0
        self._current_uri: str | None = None
        self._folder_uri: str | None = None
        self._pending = 0

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        self.append(scroller)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        body.set_margin_top(18)
        body.set_margin_bottom(18)
        body.set_margin_start(16)
        body.set_margin_end(16)
        scroller.set_child(body)

        # Área de mídia: imagem / ícone / texto / conteúdo da pasta.
        self.media = Gtk.Stack()
        self.media.set_transition_type(Gtk.StackTransitionType.NONE)
        self._inflight: set = set()

        self.picture = Gtk.Picture()
        self.picture.set_can_shrink(True)
        self.picture.set_content_fit(Gtk.ContentFit.CONTAIN)
        self.picture.set_size_request(-1, 240)
        self.picture.add_css_class("vitrine-picture")
        pic_click = Gtk.GestureClick.new()
        pic_click.connect("released", lambda g, n, *_: n == 2 and self._open_current())
        self.picture.add_controller(pic_click)
        self.media.add_named(self.picture, "picture")

        self.icon = Gtk.Image()
        self.icon.set_pixel_size(128)
        self.icon.set_margin_top(12)
        self.icon.set_margin_bottom(12)
        self.media.add_named(self.icon, "icon")

        self.text = Gtk.TextView()
        self.text.set_editable(False)
        self.text.set_cursor_visible(False)
        self.text.set_monospace(True)
        self.text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.text.set_top_margin(8)
        self.text.set_bottom_margin(8)
        self.text.set_left_margin(8)
        self.text.set_right_margin(8)
        text_scroll = Gtk.ScrolledWindow()
        text_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        text_scroll.set_size_request(-1, 320)
        text_scroll.set_child(self.text)
        text_scroll.add_css_class("card")
        self.media.add_named(text_scroll, "text")

        self.folder_list = Gtk.ListBox()
        self.folder_list.add_css_class("boxed-list")
        self.folder_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.folder_list.connect("row-activated", self._on_folder_row)
        folder_scroll = Gtk.ScrolledWindow()
        folder_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        folder_scroll.set_size_request(-1, 300)
        folder_scroll.set_child(self.folder_list)
        self.media.add_named(folder_scroll, "folder")
        body.append(self.media)

        self.title = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER, selectable=True)
        self.title.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.title.set_max_width_chars(28)
        self.title.add_css_class("title-3")
        body.append(self.title)

        self.subtitle = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER)
        self.subtitle.add_css_class("dim-label")
        body.append(self.subtitle)

        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        self.open_btn = Gtk.Button(label="Abrir")
        self.open_btn.add_css_class("pill")
        self.open_btn.add_css_class("suggested-action")
        self.open_btn.connect("clicked", lambda *_: self._open_current())
        self.look_btn = Gtk.Button(icon_name="view-reveal-symbolic", tooltip_text="Visualização rápida (Espaço)")
        self.look_btn.add_css_class("circular")
        self.look_btn.connect("clicked", lambda *_: self._on_quicklook())
        buttons.append(self.open_btn)
        buttons.append(self.look_btn)
        body.append(buttons)

        self.info = Gtk.Grid(column_spacing=12, row_spacing=6)
        self.info.set_margin_top(6)
        body.append(Gtk.Separator())
        body.append(self.info)

    # ── API ──
    def set_folder(self, folder_uri: str | None) -> None:
        self._folder_uri = folder_uri

    def show_uris(self, uris, prefetch=None) -> None:
        """Agenda a atualização (agrupa seleções rápidas, ex. segurar a seta).

        `uris` pode ser uma lista ou uma função que devolve a lista. A função é lida
        só na hora de mostrar, para não exibir uma seleção intermediária (por exemplo,
        enquanto o Nautilus reordena os itens ao trocar lista/grade)."""
        if self._pending:
            GLib.source_remove(self._pending)
        self._pending = GLib.timeout_add(
            30, self._apply, uris if callable(uris) else list(uris), prefetch)

    # ── internos ──
    def _new_token(self) -> int:
        if self._cancel is not None:
            self._cancel.cancel()
        self._cancel = Gio.Cancellable()
        self._token += 1
        return self._token

    @guarded
    def _apply(self, uris, prefetch=None) -> bool:
        self._pending = 0
        if callable(uris):
            uris = uris()
        if prefetch is not None:
            GLib.idle_add(self._prefetch, prefetch, priority=GLib.PRIORITY_LOW)
        token = self._new_token()
        if len(uris) > 1:
            self._show_multi(uris, token)
        elif len(uris) == 1:
            self._show_one(uris[0], token, selected=True)
        elif self._folder_uri:
            self._show_one(self._folder_uri, token, selected=False)
        else:
            self._clear()
        return GLib.SOURCE_REMOVE

    def _clear(self) -> None:
        self._current_uri = None
        self.icon.set_from_icon_name("folder-symbolic")
        self.media.set_visible_child_name("icon")
        self.title.set_text("")
        self.subtitle.set_text("")
        self.open_btn.set_visible(False)
        self.look_btn.set_visible(False)
        self._set_rows([])

    def _set_rows(self, rows: list[tuple[str, str]]) -> None:
        child = self.info.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.info.remove(child)
            child = nxt
        for i, (key, value) in enumerate(rows):
            k = Gtk.Label(label=key, xalign=1, yalign=0)
            k.add_css_class("dim-label")
            v = Gtk.Label(label=value, xalign=0, wrap=True, selectable=True, hexpand=True)
            v.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
            v.set_max_width_chars(24)
            self.info.attach(k, 0, i, 1, 1)
            self.info.attach(v, 1, i, 1, 1)

    def _show_one(self, uri: str, token: int, *, selected: bool) -> None:
        self._current_uri = uri
        gfile = Gio.File.new_for_uri(uri)
        gfile.query_info_async(
            INFO_ATTRS, Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT, self._cancel,
            self._on_info, (token, gfile, selected),
        )

    @guarded
    def _on_info(self, gfile: Gio.File, result, data) -> None:
        token, _f, selected = data
        try:
            info = gfile.query_info_finish(result)
        except GLib.Error as err:
            if token == self._token and not err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED):
                self._clear()
                self.title.set_text(gfile.get_basename() or "")
                self.subtitle.set_text(err.message)
            return
        if token != self._token:
            return

        ct = info.get_content_type() or ""
        ftype = info.get_file_type()
        is_dir = ftype == Gio.FileType.DIRECTORY
        self.title.set_text(info.get_display_name())
        desc = "Pasta" if is_dir else (Gio.content_type_get_description(ct) if ct else "")
        self.open_btn.set_visible(selected)
        self.open_btn.set_label("Abrir pasta" if is_dir else "Abrir")
        self.look_btn.set_visible(selected)

        rows = [("Tipo", desc or "—")]
        if not is_dir:
            rows.append(("Tamanho", util.human_size(info.get_size())))
        rows.append(("Modificado", util.format_time(info.get_modification_date_time())))
        created = info.get_creation_date_time() if info.has_attribute("time::created") else None
        if created is not None:
            rows.append(("Criado", util.format_time(created)))
        path = gfile.get_path()
        parent = gfile.get_parent()
        if parent is not None:
            rows.append(("Local", parent.get_path() or parent.get_uri()))
        self._set_rows(rows)
        self.subtitle.set_text(desc if is_dir else f"{desc} · {util.human_size(info.get_size())}")

        if is_dir:
            self._show_folder_contents(gfile, token, rows)
        elif ct.startswith("image/") and path:
            self._show_image(path, ct, info, token, rows)
        elif _is_text(ct) and info.get_size() <= TEXT_MAX_BYTES:
            self._show_icon(info)
            gfile.load_contents_async(self._cancel, self._on_text, token)
        else:
            self._show_thumbnail(gfile, info, token)

    def _show_icon(self, info: Gio.FileInfo) -> None:
        gicon = info.get_icon()
        if gicon is not None:
            self.icon.set_from_gicon(gicon)
        else:
            self.icon.set_from_icon_name("text-x-generic")
        self.media.set_visible_child_name("icon")

    # imagens: miniatura na hora → imagem nítida em seguida (cache + pré-carregamento)
    def _show_image(self, path: str, ct: str, info: Gio.FileInfo, token: int, rows: list) -> None:
        key = imageload.cache_key(path)
        hit = imageload.CACHE.get(key) if key is not None else None
        if hit is not None:
            self._present_image(hit, rows)
            return
        thumb = imageload.best_thumbnail(info)
        shown = False
        if thumb:
            try:
                self.picture.set_paintable(Gdk.Texture.new_from_filename(thumb))
                self.media.set_visible_child_name("picture")
                shown = True
            except GLib.Error:
                pass
        if not shown:
            self._show_icon(info)
        self._submit(key, path, ct, token, rows)

    def _submit(self, key, path: str, ct: str, token: int | None, rows: list | None) -> None:
        """token=None é pré-carregamento (só enche o cache)."""
        if key is None or key in self._inflight:
            return
        self._inflight.add(key)

        def work():
            if token is not None and token != self._token:
                GLib.idle_add(self._inflight.discard, key)
                return  # o usuário já foi para outro arquivo
            try:
                val = imageload.load(path, ct)
            except Exception as err:  # noqa: BLE001
                log(f"preview: imagem {path}: {err}")
                GLib.idle_add(self._inflight.discard, key)
                return
            GLib.idle_add(self._image_loaded, key, val, token, rows)

        imageload.EXECUTOR.submit(work)

    @guarded
    def _image_loaded(self, key, val, token, rows) -> bool:
        self._inflight.discard(key)
        imageload.CACHE.put(key, val)
        if token is not None and token == self._token:
            self._present_image(val, rows)
        return GLib.SOURCE_REMOVE

    def _present_image(self, val, rows: list) -> None:
        tex, w, h = val
        self.picture.set_paintable(tex)
        self.media.set_visible_child_name("picture")
        if w and h:
            self._set_rows(rows[:1] + [("Dimensões", f"{w} × {h} px")] + rows[1:])

    @guarded
    def _prefetch(self, fn) -> bool:
        uris = fn() if callable(fn) else fn
        for uri in (uris or [])[:PREFETCH_MAX]:
            path = Gio.File.new_for_uri(uri).get_path()
            if not path:
                continue
            ct = imageload.guess_type(path)
            if not ct.startswith("image/"):
                continue
            key = imageload.cache_key(path)
            if key is not None and key not in imageload.CACHE:
                self._submit(key, path, ct, None, None)
        return GLib.SOURCE_REMOVE

    # texto
    @guarded
    def _on_text(self, gfile, result, token) -> None:
        try:
            ok, data, _etag = gfile.load_contents_finish(result)
        except GLib.Error:
            return
        if token != self._token or not ok:
            return
        text = data.decode("utf-8", errors="replace")
        lines = text.splitlines()
        if len(lines) > TEXT_MAX_LINES:
            text = "\n".join(lines[:TEXT_MAX_LINES]) + "\n…"
        self.text.get_buffer().set_text(text)
        self.media.set_visible_child_name("text")

    # vídeo, PDF, documentos: miniatura do sistema
    def _show_thumbnail(self, gfile: Gio.File, info: Gio.FileInfo, token: int) -> None:
        self._show_icon(info)
        thumb = imageload.best_thumbnail(info)
        if thumb:
            try:
                self.picture.set_paintable(Gdk.Texture.new_from_filename(thumb))
                self.media.set_visible_child_name("picture")
                return
            except GLib.Error:
                pass
        if _THUMB_FACTORY is None:
            return
        uri = gfile.get_uri()
        ct = info.get_content_type() or ""
        mtime = info.get_modification_date_time()
        mtime_s = mtime.to_unix() if mtime is not None else 0

        def work():
            try:
                if not _THUMB_FACTORY.can_thumbnail(uri, ct, mtime_s):
                    return
                pix = _THUMB_FACTORY.generate_thumbnail(uri, ct, None)
                if pix is None:
                    return
                _THUMB_FACTORY.save_thumbnail(pix, uri, mtime_s, None)
                tex = Gdk.Texture.new_for_pixbuf(pix)
                GLib.idle_add(self._thumb_ready, token, tex)
            except Exception as err:  # noqa: BLE001
                log(f"preview: miniatura {uri}: {err}")

        threading.Thread(target=work, daemon=True).start()

    @guarded
    def _thumb_ready(self, token, tex) -> bool:
        if token == self._token:
            self.picture.set_paintable(tex)
            self.media.set_visible_child_name("picture")
        return GLib.SOURCE_REMOVE

    # pastas: lista do conteúdo (como a próxima coluna do Finder)
    def _show_folder_contents(self, gfile: Gio.File, token: int, rows: list) -> None:
        self.icon.set_from_icon_name("folder")
        self.media.set_visible_child_name("icon")
        gfile.enumerate_children_async(
            "standard::name,standard::display-name,standard::icon,standard::type,standard::is-hidden",
            Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT, self._cancel,
            self._on_enum, (token, rows, []),
        )

    @guarded
    def _on_enum(self, gfile, result, data) -> None:
        token, rows, acc = data
        try:
            enum = gfile.enumerate_children_finish(result)
        except GLib.Error:
            return
        enum.next_files_async(100, GLib.PRIORITY_DEFAULT, self._cancel, self._on_batch,
                              (token, rows, acc, gfile))

    @guarded
    def _on_batch(self, enum, result, data) -> None:
        token, rows, acc, folder = data
        try:
            infos = enum.next_files_finish(result)
        except GLib.Error:
            return
        if token != self._token:
            enum.close_async(GLib.PRIORITY_LOW, None, None)
            return
        acc.extend(i for i in infos if not i.get_is_hidden())
        if infos and len(acc) < 5000:
            enum.next_files_async(200, GLib.PRIORITY_DEFAULT, self._cancel, self._on_batch, data)
            return
        enum.close_async(GLib.PRIORITY_LOW, None, None)
        n_dirs = sum(1 for i in acc if i.get_file_type() == Gio.FileType.DIRECTORY)
        n_files = len(acc) - n_dirs
        self.subtitle.set_text(f"{len(acc)} itens · {n_dirs} pastas, {n_files} arquivos")
        self._set_rows([("Conteúdo", f"{len(acc)} itens")] + rows)

        while (row := self.folder_list.get_row_at_index(0)) is not None:
            self.folder_list.remove(row)
        acc.sort(key=lambda i: (i.get_file_type() != Gio.FileType.DIRECTORY,
                                GLib.utf8_collate_key_for_filename(i.get_display_name(), -1)))
        if not acc:
            return
        for info in acc[:FOLDER_LIST_MAX]:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=8)
            box.set_margin_top(4)
            box.set_margin_bottom(4)
            box.set_margin_start(8)
            box.set_margin_end(8)
            img = Gtk.Image()
            if info.get_icon() is not None:
                img.set_from_gicon(info.get_icon())
            lbl = Gtk.Label(label=info.get_display_name(), xalign=0, hexpand=True)
            lbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            box.append(img)
            box.append(lbl)
            row.set_child(box)
            row._vitrine_uri = folder.get_child(info.get_name()).get_uri()
            row._vitrine_dir = info.get_file_type() == Gio.FileType.DIRECTORY
            row._vitrine_parent = folder.get_uri()
            self.folder_list.append(row)
        self.media.set_visible_child_name("folder")

    @guarded
    def _on_folder_row(self, _lb, row) -> None:
        uri = getattr(row, "_vitrine_uri", None)
        if not uri:
            return
        if getattr(row, "_vitrine_dir", False):
            self._on_navigate(uri)
        else:
            self._on_reveal(row._vitrine_parent, uri)

    # várias seleções
    def _show_multi(self, uris: list[str], token: int) -> None:
        self._current_uri = None
        self.icon.set_from_icon_name("edit-select-all-symbolic")
        self.media.set_visible_child_name("icon")
        self.title.set_text(f"{len(uris)} itens selecionados")
        self.subtitle.set_text("Calculando tamanho…")
        self.open_btn.set_visible(False)
        self.look_btn.set_visible(True)
        self._set_rows([])

        def work():
            total = 0
            for u in uris[:2000]:
                try:
                    i = Gio.File.new_for_uri(u).query_info("standard::size,standard::type",
                                                           Gio.FileQueryInfoFlags.NONE, None)
                    if i.get_file_type() != Gio.FileType.DIRECTORY:
                        total += i.get_size()
                except GLib.Error:
                    pass
                if token != self._token:
                    return
            GLib.idle_add(self._multi_ready, token, total)

        threading.Thread(target=work, daemon=True).start()

    @guarded
    def _multi_ready(self, token, total) -> bool:
        if token == self._token:
            self.subtitle.set_text(f"{util.human_size(total)} em arquivos (sem contar subpastas)")
        return GLib.SOURCE_REMOVE

    def _open_current(self) -> None:
        if not self._current_uri:
            return
        f = Gio.File.new_for_uri(self._current_uri)
        if f.query_file_type(Gio.FileQueryInfoFlags.NONE, None) == Gio.FileType.DIRECTORY:
            self._on_navigate(self._current_uri)
        else:
            util.open_uri(self._current_uri)
__VITRINE_ARQUIVO_12__
mkdir -p "vitrine"
cat > 'vitrine/selftest.py' <<'__VITRINE_ARQUIVO_13__'
"""Autoteste dentro do Nautilus real. Só roda com VITRINE_SELFTEST=1.

Navega por pastas, troca modos, seleciona arquivos e grava PASSOU/FALHOU no log.
No final restaura as regras e o zoom que existiam antes.
"""

from __future__ import annotations

import copy
import os
import shutil
import tempfile
import time

from gi.repository import Gio, GLib, Gtk

from . import discovery, imageload, native, util
from .util import gtype_name, log

STEP_MS = 1500


def _image_uris(model) -> list[str]:
    out = []
    if model is None:
        return out
    for pos in range(model.get_n_items()):
        uri = native._item_uri(model.get_item(pos))
        path = Gio.File.new_for_uri(uri).get_path() if uri else None
        if path and imageload.guess_type(path) in imageload.FAST_TYPES:
            out.append(uri)
        if len(out) >= 3:
            break
    return out


def _time_preview(ctl, uri: str, label: str, check) -> None:
    """Seleciona `uri` na lista nativa e mede: 1ª imagem visível e imagem nítida."""
    path = Gio.File.new_for_uri(uri).get_path()
    key = imageload.cache_key(path)
    before = ctl.preview.picture.get_paintable()
    t0 = time.monotonic()
    marks = {}
    native.select_uris(native.find_model(ctl.active_slot()), [uri])

    def poll():
        now = (time.monotonic() - t0) * 1000
        pic = ctl.preview.picture.get_paintable()
        on_picture = ctl.preview.media.get_visible_child_name() == "picture"
        if "first" not in marks and on_picture and pic is not None and pic is not before:
            marks["first"] = now
        hit = imageload.CACHE.get(key)
        if hit is not None and pic is hit[0] and on_picture:
            marks.setdefault("first", now)
            marks["full"] = now
        if "full" in marks or now > 1300:
            full = marks.get("full")
            check(f"preview {label}", full is not None and full < 600,
                  f"{os.path.basename(path)}: 1ª imagem={marks.get('first', -1):.0f} ms, "
                  f"nítida={full if full is not None else -1:.0f} ms")
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    GLib.timeout_add(5, poll)


def run(ctl) -> bool:
    cfg = ctl.cfg
    saved_folders = copy.deepcopy(cfg.folders)
    saved_settings = copy.deepcopy(cfg.settings)
    saved_zoom = ctl.ext.current_grid_zoom()
    # Roda com regras padrão (as suas ficam num backup e voltam no fim).
    try:
        import json

        from .config import FOLDERS_PATH
        with open(FOLDERS_PATH + ".selftest-backup", "w", encoding="utf-8") as fh:
            json.dump(saved_folders, fh, indent=2, ensure_ascii=False)
    except OSError:
        pass
    cfg.folders.clear()
    cfg._seed_pictures_rule()
    cfg.settings["default_mode"] = "list"
    cfg.settings["start_on_computer"] = False
    # Suas escolhas de exibição também ficam de lado durante o teste (voltam no fim):
    # painel de pré-visualização aberto e nada oculto no Meu computador.
    cfg.settings["computer_hidden"] = []
    cfg.settings["computer_sections"] = {}
    ctl.ext.refresh_computer_pages()
    ctl.set_preview_visible(True)
    home = Gio.File.new_for_path(os.path.expanduser("~")).get_uri()
    pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
    pictures_uri = Gio.File.new_for_path(pictures).get_uri() if pictures else None
    project = Gio.File.new_for_path(os.path.join(os.path.dirname(os.path.dirname(
        os.path.realpath(__file__))), "vitrine")).get_uri()
    results: list[tuple[str, bool, str]] = []
    images: list[str] = []

    def check(name, ok, detail=""):
        results.append((name, bool(ok), detail))
        log(f"SELFTEST {'PASSOU' if ok else 'FALHOU'}: {name} {detail}")

    def slot():
        return ctl.active_slot()

    def state():
        s = slot()
        return {
            "uri": native.slot_uri(s),
            "view": native.view_mode(s),
            "vmode": getattr(s, "_vitrine_mode", None),
            "strip": ctl.strip.get_visible(),
            "cols": [c.folder.get_basename() for c in ctl.strip.columns],
            "zoom": ctl.ext.current_grid_zoom(),
            "preview": (ctl.preview.get_visible(), ctl.preview.media.get_visible_child_name(),
                        ctl.preview.title.get_text()),
        }

    steps = []

    def step(fn):
        steps.append(fn)
        return fn

    @step
    def s0():
        st = state()
        check("injeção (botões e painel existem)",
              ctl.btn_columns is not None and ctl.btn_columns.get_root() is ctl.win
              and ctl.preview.get_root() is ctl.win, str(st))
        # A janela pode ter aberto no Meu computador com a pasta pessoal por baixo:
        # sair dele para a mesma pasta não gera navegação, por isso este caminho.
        ctl.leave_computer_and_open(home)

    @step
    def s1():
        st = state()
        check("pasta pessoal abre em lista", st["view"] == "list" and not st["strip"], str(st))
        check("preview mostra a pasta atual sem seleção",
              st["preview"][0] and st["preview"][2] != "", str(st["preview"]))
        if pictures_uri:
            ctl.navigate(pictures_uri)

    @step
    def s2():
        st = state()
        if pictures_uri:
            check("Imagens abre em ícones grandes", st["view"] == "grid" and st["zoom"] == "extra-large",
                  str(st))
            images.extend(_image_uris(native.find_model(slot())))
            if images:
                _time_preview(ctl, images[0], "1ª foto (sem cache)", check)

    @step
    def s2b():
        if len(images) > 1:
            _time_preview(ctl, images[1], "foto vizinha (pré-carregada)", check)

    @step
    def s2c():
        if images:
            _time_preview(ctl, images[0], "voltar à 1ª foto (cache)", check)

    @step
    def s2d():
        ctl.navigate(home)

    @step
    def s3():
        st = state()
        check("voltando para a pasta pessoal, volta para lista", st["view"] == "list", str(st))
        ctl.navigate(project)

    @step
    def s4():
        st = state()
        check("pasta do projeto abre (sem regra) em lista", st["view"] == "list", str(st))
        ctl.user_set_mode("columns")

    @step
    def s5():
        st = state()
        check("Ctrl+3 / Colunas liga as colunas",
              st["strip"] and st["vmode"] == "columns" and st["view"] == "list"
              and st["cols"][-1:] == ["nautilus-vitrine"], str(st))
        check("botão de colunas fica ativo", ctl.btn_columns.get_active())
        model = native.find_model(slot())
        main_py = Gio.File.new_for_uri(project).get_child("main.py").get_uri()
        check("seleção nativa por URI", native.select_uris(model, [main_py]))

    @step
    def s6():
        st = state()
        check("preview acompanha a seleção da lista nativa",
              st["preview"][2] == "main.py" and st["preview"][1] == "text", str(st["preview"]))
        parent = Gio.File.new_for_uri(project).get_parent().get_uri()
        ctl.navigate(parent)

    @step
    def s7():
        st = state()
        check("navegar continua em colunas (sem regra)", st["strip"] and st["vmode"] == "columns",
              str(st))
        ctl.navigate(project)

    @step
    def s8():
        st = state()
        check("pasta lembrada em colunas", st["vmode"] == "columns", str(st))
        ctl.user_set_mode("list")

    @step
    def s9():
        st = state()
        check("Ctrl+1 sai das colunas", not st["strip"] and st["view"] == "list", str(st))
        ctl.user_set_mode("grid", "large")

    @step
    def s10():
        st = state()
        check("trocar para ícones aplica e lembra o zoom",
              st["view"] == "grid" and st["zoom"] == "large"
              and (cfg.folders.get(Gio.File.new_for_uri(project).get_uri()) or {}).get("zoom") == "large",
              str(st))
        sel = native.selected_uris(native.find_model(slot()))
        expected = Gio.File.new_for_uri(sel[0]).get_basename() if len(sel) == 1 else None
        check("preview mostra a mesma seleção do Nautilus depois de trocar para ícones",
              expected is None or st["preview"][2] == expected,
              f"preview={st['preview']} nativo={sel}")
        ctl.navigate(home)

    @step
    def c1():
        ctl.show_computer(True)

    def tile_uris(page):
        uris = []
        for box in (page.places_box,):
            child = box.get_first_child()
            while child is not None:
                uris.append(getattr(child, "_vitrine_uri", None))
                child = child.get_next_sibling()
        return uris

    @step
    def c2():
        page = ctl.computer
        uris = tile_uris(page)
        tiles = len(uris)
        sidebar = [e["uri"] for e in native.sidebar_places(ctl.win) if not e["device"]]
        check("todos os locais da barra lateral aparecem (Recentes, Favoritos, Rede, Lixeira, marcadores)",
              sidebar and all(u in uris for u in sidebar)
              and all(s in uris for s in ("recent:///", "starred:///", "trash:///")),
              f"barra lateral={len(sidebar)} página={tiles} faltando={[u for u in sidebar if u not in uris]}")
        system = page._cards.get("system:/")
        detail = system._vitrine_detail.get_text() if system is not None else ""
        check("Meu computador abre (Ctrl+Shift+C / barra lateral)",
              ctl.content_stack.get_visible_child_name() == "computer"
              and ctl.sidebar_list is not None
              and ctl.sidebar_list.get_selected_row() is not None,
              f"página={ctl.content_stack.get_visible_child_name()} sidebar={ctl.sidebar_list is not None}")
        check("disco do sistema mostra o uso de espaço",
              system is not None and system._vitrine_bar.get_value() > 0 and "livres" in detail,
              detail)
        ctl._vitrine_toasts_before = ctl.toasts_shown
        ctl.ext.hub.announce("selftest:usb", "Pen drive (teste)")
        page.mark_new("system:/")

    @step
    def c3():
        page = ctl.computer
        system = page._cards.get("system:/")
        check("aviso de dispositivo novo aparece com botão Abrir",
              ctl.toasts_shown == ctl._vitrine_toasts_before + 1,
              f"avisos={ctl.toasts_shown}")
        check("dispositivo novo fica destacado e selecionado",
              system is not None and system._vitrine_badge.get_visible()
              and system in page.devices_box.get_selected_children())
        page._unmark("system:/")
        ctl.navigate(project)

    @step
    def c4():
        st = state()
        check("navegar sai do Meu computador",
              ctl.content_stack.get_visible_child_name() == "tabs"
              and ctl.sidebar_list.get_selected_row() is None
              and st["uri"] == Gio.File.new_for_uri(project).get_uri(), str(st))
        ctl.show_computer(True)

    @step
    def c5():
        ctl.computer.open_child(ctl.computer._cards["system:/"])

    @step
    def c6():
        st = state()
        check("abrir o disco do sistema navega para /",
              ctl.content_stack.get_visible_child_name() == "tabs" and st["uri"] == "file:///",
              str(st))
        ctl.navigate(home)

    @step
    def c7():
        ctl.show_computer(True)
        page = ctl.computer
        page.set_item_hidden("starred:///", True)
        page.set_section_enabled("devices", False)

    @step
    def c8():
        page = ctl.computer
        uris = tile_uris(page)
        check("personalizar: ocultar item e seção",
              "starred:///" not in uris and not page.sections["devices"].get_visible()
              and page.sections["places"].get_visible(),
              f"itens={uris}")
        page.set_item_hidden("starred:///", False)
        page.set_section_enabled("devices", True)
        uris = tile_uris(page)
        check("personalizar: mostrar de novo",
              "starred:///" in uris and page.sections["devices"].get_visible())
        home_uri = Gio.File.new_for_uri(home).get_uri().rstrip("/")
        special = [i for i, u in enumerate(uris) if (GLib.Uri.peek_scheme(u) or "") != "file"]
        folders = [i for i, u in enumerate(uris) if (GLib.Uri.peek_scheme(u) or "") == "file"]
        check("pastas num grupo único: pasta pessoal primeiro, locais especiais no fim",
              uris and uris[0].rstrip("/") == home_uri
              and (not special or not folders or max(folders) < min(special)),
              f"ordem={uris}")
        try:
            page.open_settings()
            dlg = page._settings_dialog
            ok = dlg is not None and dlg.get_root() is not None
            dlg.close()
        except Exception as err:  # noqa: BLE001
            ok = False
            log(f"open_settings: {err!r}")
        check("tela de personalização abre", ok)
        try:
            ctl.open_settings("about")
            dlg = page._settings_dialog
            visible = dlg.get_visible_page()
            ok = visible is not None and visible.get_name() == "about"
            dlg.close()
        except Exception as err:  # noqa: BLE001
            ok = False
            log(f"open_settings(about): {err!r}")
        check("menu ☰ → Sobre abre o diálogo já na página Sobre", ok)
        cfg.settings["start_on_computer"] = True
        project_dir = Gio.File.new_for_uri(project).get_uri()
        check("opção abrir no Meu computador (só ao abrir na pasta pessoal)",
              ctl.should_start_on_computer(home) and not ctl.should_start_on_computer(project_dir))
        cfg.settings["start_on_computer"] = False
        for box in (page.places_box,):
            child = box.get_first_child()
            while child is not None:
                if getattr(child, "_vitrine_uri", None) == "recent:///":
                    page.open_child(child)
                    break
                child = child.get_next_sibling()

    @step
    def c9():
        st = state()
        check("abrir Recentes pelo Meu computador",
              ctl.content_stack.get_visible_child_name() == "tabs" and st["uri"] == "recent:///",
              str(st))
        ctl.navigate(home)

    # ── descoberta automática de pastas ──
    disc: dict[str, str] = {}

    @step
    def d1():
        ratio = 0.6
        check("descoberta: classifica mídia, documentos, mista e vazia",
              discovery.classify(["image/jpeg"] * 5 + ["text/plain"], ratio) == "media"
              and discovery.classify(["application/pdf"] * 5, ratio) == "documents"
              and discovery.classify(["image/png"] * 3 + ["text/plain"] * 3, ratio) is None
              and discovery.classify([], ratio) is None)
        root = tempfile.mkdtemp(prefix="vitrine-selftest-")
        disc["root"] = root
        for name, files in (("fotos", [f"f{i}.jpg" for i in range(6)]),
                            ("docs", [f"d{i}.pdf" for i in range(3)] + [f"n{i}.txt" for i in range(3)])):
            path = os.path.join(root, name)
            os.makedirs(path)
            for f in files:
                open(os.path.join(path, f), "wb").close()
            disc[name] = Gio.File.new_for_path(path).get_uri()
        cfg.settings["folder_discovery"] = True
        cfg.settings["default_mode"] = "grid"  # prova que documentos vão para a lista
        cfg.settings["remember_per_folder"] = False
        ctl.navigate(disc["fotos"])

    @step
    def d2():
        st = state()
        check("descoberta: pasta de fotos abre em ícones extra grandes",
              st["view"] == "grid" and st["zoom"] == "extra-large", str(st))
        ctl.navigate(disc["docs"])

    @step
    def d3():
        st = state()
        check("descoberta: pasta de documentos abre em lista", st["view"] == "list", str(st))
        ctl.user_set_mode("grid", "medium")

    @step
    def d4():
        ctl.navigate(disc["fotos"])

    @step
    def d5():
        ctl.navigate(disc["docs"])

    @step
    def d6():
        st = state()
        check("descoberta: escolha manual tem prioridade na pasta",
              st["view"] == "grid" and cfg.rule_for(disc["docs"])[0] is None, str(st))
        discovery.forget_manual(disc["docs"])
        shutil.rmtree(disc["root"], ignore_errors=True)
        cfg.settings["folder_discovery"] = False
        cfg.settings["default_mode"] = "list"
        cfg.settings["remember_per_folder"] = saved_settings.get("remember_per_folder", True)
        ctl.navigate(home)

    # ── Voltar/Avançar com o Meu computador ──
    target = pictures_uri or project

    def on_computer() -> bool:
        return ctl.content_stack.get_visible_child_name() == "computer"

    def same(uri_a, uri_b) -> bool:
        return bool(uri_a and uri_b) and Gio.File.new_for_uri(uri_a).equal(
            Gio.File.new_for_uri(uri_b))

    @step
    def h1():
        swapped = [w for w in util.walk(ctl.win) if isinstance(w, Gtk.Button)
                   and w.get_action_name() == "vitrine.back"]
        check("Voltar: botões ←, Alt+← e mouse passam pela Vitrine",
              swapped and ctl.history_shortcuts_removed >= 2 and ctl._mouse_takeover,
              f"botões={len(swapped)} atalhos={ctl.history_shortcuts_removed} "
              f"mouse={ctl._mouse_takeover}")
        ctl.show_computer(True)  # Pasta pessoal → Meu computador

    @step
    def h2():
        ctl.leave_computer_and_open(target)  # → Imagens

    @step
    def h3():
        ctl.win.activate_action("vitrine.back", None)

    @step
    def h4():
        check("Voltar: Imagens → Meu computador", on_computer()
              and same(state()["uri"], target), str(state()))
        ctl.win.activate_action("vitrine.forward", None)

    @step
    def h5():
        check("Avançar: Meu computador → Imagens", not on_computer()
              and same(state()["uri"], target), str(state()))
        ctl.win.activate_action("vitrine.back", None)

    @step
    def h6():
        ctl.win.activate_action("vitrine.back", None)  # Meu computador → Pasta pessoal

    @step
    def h7():
        check("Voltar: Meu computador → Pasta pessoal", not on_computer()
              and same(state()["uri"], home), str(state()))
        ctl.navigate(home)

    # ── estilo Finder ↔ Nautilus padrão ──
    from . import finder as finder_mod

    shots = os.environ.get("VITRINE_SNAPSHOT_DIR", "")

    def shot(name):
        if shots:
            os.makedirs(shots, exist_ok=True)
            util.snapshot_png(ctl.win, os.path.join(shots, f"{name}.png"))

    def finder_widgets():
        return [w for w in util.walk(ctl.win)
                if any(c.startswith(("vitrine-capsule", "vitrine-finder", "vitrine-search", "vitrine-tags"))
                       for c in w.get_css_classes()) and w is not ctl.win]

    style_state = {}

    @step
    def f0():
        ctl.cfg.set("window_style", "nautilus")

    @step
    def f1():
        st = ctl.style
        style_state["layouts"] = (st.header and st.header.get_decoration_layout(),)
        style_state["n_native"] = sum(1 for _ in util.walk(ctl.win))
        shot("nautilus-padrao")
        ctl.cfg.set("window_style", "finder")

    @step
    def f2():
        st = ctl.style
        views = st.toolbar.view_buttons if st.toolbar else {}
        check("estilo Finder: aplicado na hora (classe, CSS, barra de ferramentas)",
              st.active and ctl.win.has_css_class("vitrine-finder") and finder_mod.css_loaded()
              and set(views) == {"grid", "list", "columns", "gallery"},
              finder_mod.describe(ctl.win))
        check("estilo Finder: botões da janela ficam no padrão do GNOME",
              (st.header.get_decoration_layout(),) == style_state["layouts"]
              and not any(c.startswith("vitrine") for w in util.walk(ctl.win)
                          if gtype_name(w) == "GtkWindowControls" for c in w.get_css_classes()),
              str(st.header.get_decoration_layout()))
        active = [m for m, b in views.items() if b.get_active()]
        check("estilo Finder: seletor de visualização mostra o modo atual",
              len(active) == 1, str(active))
        style_state["n_widgets"] = len(finder_widgets())
        shot("finder")
        ctl.cfg.set("window_style", "nautilus")

    @step
    def f3():
        st = ctl.style
        leftovers = finder_widgets()
        check("Nautilus padrão: nada da camada Finder sobra (CSS, classe, widgets)",
              not st.active and not ctl.win.has_css_class("vitrine-finder")
              and not finder_mod.css_loaded() and not leftovers
              and sum(1 for _ in util.walk(ctl.win)) == style_state["n_native"]
              and "vitrine_dimensions" not in Gio.Settings.new("org.gnome.nautilus.icon-view").get_strv("captions")
              and "Vitrine::tags" not in Gio.Settings.new("org.gnome.nautilus.list-view").get_strv("default-visible-columns"),
              f"{finder_mod.describe(ctl.win)} sobras={[w.get_css_classes() for w in leftovers]} "
              f"widgets={sum(1 for _ in util.walk(ctl.win))}/{style_state['n_native']}")
        ctl.cfg.set("window_style", "finder")

    @step
    def f4():
        check("Finder de novo: restaurado sem duplicar nada",
              ctl.style.active and len(finder_widgets()) == style_state["n_widgets"],
              f"{len(finder_widgets())} vs {style_state['n_widgets']}")
        ctl.show_computer(True)

    @step
    def f5():
        tb = ctl.style.toolbar
        check("Finder: título mostra Meu computador e ← volta para a pasta",
              tb is not None and tb.title.get_label() == "Meu computador", tb.title.get_label())
        shot("finder-meu-computador")
        ctl.win.activate_action("vitrine.back", None)

    # ── etiquetas e dimensões ──
    tagdir = {}

    def icons_named(name):
        out = []
        for w in util.walk(ctl.win):
            if not isinstance(w, Gtk.Image) or not w.get_mapped():
                continue
            gicon = w.get_gicon()
            names = list(gicon.get_names()) if isinstance(gicon, Gio.ThemedIcon) else []
            if w.get_icon_name() == name or name in names:
                out.append(w)
        return out

    @step
    def t0():
        gi_require = __import__("gi")
        gi_require.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf
        root = tempfile.mkdtemp(prefix="vitrine-selftest-tags-")
        png = os.path.join(root, "foto.png")
        GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 300, 200).savev(png, "png", [], [])
        txt = os.path.join(root, "nota.txt")
        open(txt, "w").close()
        tagdir.update(root=root, png=Gio.File.new_for_path(png).get_uri(),
                      txt=Gio.File.new_for_path(txt).get_uri())
        ctl.navigate(Gio.File.new_for_path(root).get_uri())

    @step
    def t1():
        ctl.user_set_mode("grid", "large")
        ctl.ext.tags.toggle([tagdir["png"], tagdir["txt"]], "Vermelho")

    @step
    def t2():
        from .tags import read_tags, uri_to_path
        check("etiquetas: grava user.xdg.tags nos arquivos",
              read_tags(uri_to_path(tagdir["png"])) == ["Vermelho"])
        dots = [w for w in icons_named("vitrine-tag-red")
                if util.ancestor(w, lambda a: gtype_name(a) == "NautilusGridCell") is not None]
        check("etiquetas: o Nautilus mostra a bolinha (emblema) nos arquivos",
              len(dots) >= 2, f"emblemas={len(dots)}")
        dims = [w for w in util.walk(ctl.win) if isinstance(w, Gtk.Label)
                and w.get_label() == "300 × 200" and w.get_mapped()]
        blue = dims and dims[0].get_color().blue > max(dims[0].get_color().red, dims[0].get_color().green)
        check("ícones: dimensões da imagem abaixo do nome, em azul", len(dims) == 1 and blue,
              f"legendas={len(dims)} cor={dims[0].get_color().to_string() if dims else '-'}")
        cell = next((w for w in util.walk(ctl.win) if gtype_name(w) == "NautilusGridCell"), None)
        if cell is not None and dims:
            chain, w = [], dims[0]
            while w is not None:
                chain.append(f"{gtype_name(w)}{w.get_css_classes()}")
                w = w.get_parent()
            log(f"legenda: cor={dims[0].get_color().to_string()} ancestrais={' < '.join(chain[:9])}")
        shot("finder-icones-etiquetas")
        ctl.user_set_mode("gallery")

    # ── Galeria e barras de baixo ──
    @step
    def g1():
        gal = ctl.gallery
        heads = [w.get_label() for w in util.walk(gal.strip)
                 if isinstance(w, Gtk.Label) and "vitrine-gallery-group" in w.get_css_classes()]
        sel = native.selected_uris(native.find_model(slot()))
        tb = ctl.style.toolbar
        check("galeria: abre com a faixa de miniaturas e o grupo Hoje",
              ctl.content_stack.get_visible_child_name() == "gallery" and len(gal.items) == 2
              and gal.selected is not None and heads == ["Hoje"],
              f"página={ctl.content_stack.get_visible_child_name()} itens={len(gal.items)} grupos={heads}")
        check("galeria: botão Galeria ativo na barra do Finder",
              tb is not None and tb.view_buttons["gallery"].get_active())
        check("galeria: seleção vai para a lista nativa (Espaço, Propriedades…)",
              gal.selected is not None and sel == [gal.selected.uri], f"{sel}")
        shot("finder-galeria")
        ctl.cfg.set("path_bar", True)
        ctl.cfg.set("status_bar", True)

    @step
    def g2():
        gal = ctl.gallery
        first = gal.selected
        gal.move(+1)
        sel = native.selected_uris(native.find_model(slot()))
        check("galeria: setas trocam o item e a seleção nativa",
              gal.selected is not first and sel == [gal.selected.uri])
        bar = ctl.style.bottombar
        crumbs = bar.crumbs(native.slot_uri(slot())) if bar else []
        check("barra de caminho: hierarquia clicável até a pasta atual",
              bar is not None and bar.path_scroll.get_visible()
              and crumbs and crumbs[-1][0] == os.path.basename(tagdir["root"]),
              str([c[0] for c in crumbs]))
        bar.update()
        check("barra de status: itens e espaço disponível",
              bar.status.get_visible() and bar.status.get_label().startswith("2 itens"),
              bar.status.get_label())
        from gi.repository import Nautilus
        models = ctl.ext.get_models([Nautilus.FileInfo.create_for_uri(tagdir["png"])])
        item = models[0].get_model().get_item(0) if models else None
        check("Propriedades (Ctrl+I): aba Etiquetas",
              item is not None and item.get_value() == "Vermelho",
              item.get_value() if item else "sem aba")

    @step
    def g3():
        shot("finder-galeria-barras")
        ctl.cfg.set("path_bar", False)
        ctl.cfg.set("status_bar", False)
        ctl.user_set_mode("grid", "large")
        ctl.show_tag("Vermelho")

    @step
    def t3():
        page = ctl.tag_page
        n = 0
        child = page.flow.get_first_child()
        while child is not None:
            n += 1
            child = child.get_next_sibling()
        check("etiquetas: clicar na etiqueta mostra os arquivos com ela",
              ctl.content_stack.get_visible_child_name() == "tag" and n == 2
              and ctl.style.toolbar.title.get_label() == "Vermelho", f"itens={n}")
        check("etiquetas: seção Etiquetas na barra lateral",
              ctl.tag_sidebar is not None and ctl.tag_sidebar.get_mapped())
        shot("finder-etiqueta-vermelho")
        ctl.leave_tag_and_open(Gio.File.new_for_path(tagdir["root"]).get_uri())

    @step
    def t4():
        check("etiquetas: navegar fecha a página da etiqueta",
              ctl.tag_visible() is None and ctl.content_stack.get_visible_child_name() == "tabs")
        ctl.ext.tags.clear([tagdir["png"], tagdir["txt"]])
        discovery.forget_manual(Gio.File.new_for_path(tagdir["root"]).get_uri())
        cfg.forget(Gio.File.new_for_path(tagdir["root"]).get_uri())
        ctl.navigate(home)

    @step
    def t5():
        shutil.rmtree(tagdir["root"], ignore_errors=True)
        ctl.cfg.set("tags_in_sidebar", False)

    @step
    def t6():
        off = ctl.tag_sidebar is None and not any(
            "vitrine-tags-section" in w.get_css_classes() for w in util.walk(ctl.win))
        ctl.cfg.set("tags_in_sidebar", True)
        check("opção Seção Etiquetas vale na hora (desliga e liga)",
              off and ctl.tag_sidebar is not None and ctl.style.active)

    @step
    def s11():
        st = state()
        check("regra não vaza para outras pastas", st["view"] == "list", str(st))
        # restaura tudo
        cfg.folders.clear()
        cfg.folders.update(saved_folders)
        cfg.settings.clear()
        cfg.settings.update(saved_settings)
        cfg.save()
        ctl.set_preview_visible(bool(saved_settings.get("preview_visible")))
        ctl.ext.refresh_computer_pages()
        ctl.apply_window_style()
        if ctl.style is not None and ctl.style.active:  # opções do Finder restauradas
            ctl.style.remove()
            ctl.style.apply()
        ctl.ext.set_grid_zoom(saved_zoom)
        ok = sum(1 for r in results if r[1])
        log(f"SELFTEST RESUMO: {ok}/{len(results)} passaram")

    def runner(i=[0]):
        if i[0] >= len(steps):
            return GLib.SOURCE_REMOVE
        try:
            steps[i[0]]()
        except Exception as err:  # noqa: BLE001
            check(f"passo {i[0]} gerou exceção", False, repr(err))
        i[0] += 1
        return GLib.SOURCE_CONTINUE

    GLib.timeout_add(STEP_MS, runner)
    return GLib.SOURCE_REMOVE
__VITRINE_ARQUIVO_13__
mkdir -p "vitrine"
cat > 'vitrine/tags.py' <<'__VITRINE_ARQUIVO_14__'
"""Etiquetas coloridas, guardadas no atributo estendido padrão `user.xdg.tags`.

O atributo guarda os *nomes* das etiquetas separados por vírgula (o mesmo formato do
Dolphin/KDE e de outros gerenciadores), então as etiquetas continuam valendo fora da
Vitrine. A cor de cada nome fica nas preferências (GSettings, chave `tags`).

O sistema de arquivos não tem um jeito rápido de achar "todos os arquivos com a
etiqueta X", então a Vitrine mantém um índice (~/.local/share/nautilus-vitrine/
tags.json) com os arquivos que ela etiquetou ou que o Nautilus mostrou com etiqueta;
`scan()` procura numa pasta (ex.: a pasta pessoal) quando o usuário pede.

Python puro (sem GTK): testado em tools/test_tags.py.
"""

from __future__ import annotations

import json
import os
import threading
from urllib.parse import unquote, urlparse

from .util import log

XATTR = "user.xdg.tags"
INDEX_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                         "nautilus-vitrine")

# cor → (hex, emoji para menus de texto, nome padrão)
PALETTE = {
    "red": ("#ff453a", "🔴", "Vermelho"),
    "orange": ("#ff9f0a", "🟠", "Laranja"),
    "yellow": ("#ffd60a", "🟡", "Amarelo"),
    "green": ("#30d158", "🟢", "Verde"),
    "blue": ("#0a84ff", "🔵", "Azul"),
    "purple": ("#bf5af2", "🟣", "Roxo"),
    "gray": ("#98989d", "⚪", "Cinza"),
}
DEFAULT_TAGS = [(PALETTE[c][2], c) for c in ("red", "orange", "yellow", "green", "blue", "purple")]


class TagError(Exception):
    """Não foi possível gravar a etiqueta (ex.: pen drive FAT, sem permissão)."""


def uri_to_path(uri: str) -> str | None:
    p = urlparse(uri)
    return unquote(p.path) if p.scheme == "file" else None


def path_to_uri(path: str) -> str:
    from urllib.parse import quote
    return "file://" + quote(os.path.abspath(path))


def read_tags(path: str) -> list[str]:
    try:
        raw = os.getxattr(path, XATTR, follow_symlinks=True)
    except OSError:
        return []
    names = []
    for part in raw.decode("utf-8", "replace").split(","):
        part = part.strip()
        if part and part not in names:
            names.append(part)
    return names


def write_tags(path: str, names: list[str]) -> None:
    try:
        if names:
            os.setxattr(path, XATTR, ",".join(names).encode("utf-8"), follow_symlinks=True)
        else:
            try:
                os.removexattr(path, XATTR, follow_symlinks=True)
            except OSError as err:
                if err.errno not in (61, 95):  # ENODATA / ENOTSUP: já não tinha
                    raise
    except OSError as err:
        raise TagError(f"{os.path.basename(path)}: {err.strerror}") from err


class TagStore:
    """Definições (nome, cor), leitura/escrita nos arquivos e o índice."""

    def __init__(self, cfg, index_path: str | None = None, on_files_changed=None) -> None:
        self.cfg = cfg
        self.index_path = index_path or os.path.join(INDEX_DIR, "tags.json")
        self.on_files_changed = on_files_changed   # callback(uris) → avisar o Nautilus
        self._listeners: list = []
        self._lock = threading.Lock()
        self.index: dict[str, list[str]] = self._load_index()

    # ── definições ──
    def definitions(self) -> list[tuple[str, str]]:
        raw = self.cfg.get("tags")
        out = []
        for item in raw or DEFAULT_TAGS:
            try:
                name, color = item
            except (TypeError, ValueError):
                continue
            if name and name not in (n for n, _c in out):
                out.append((str(name), color if color in PALETTE else "gray"))
        return out

    def names(self) -> list[str]:
        return [n for n, _c in self.definitions()]

    def color_of(self, name: str) -> str:
        return dict(self.definitions()).get(name, "gray")

    def _save_definitions(self, defs) -> None:
        self.cfg.set("tags", [(n, c) for n, c in defs])
        self._notify()

    def create(self, name: str, color: str = "gray") -> bool:
        name = _clean(name)
        if not name or name in self.names():
            return False
        self._save_definitions(self.definitions() + [(name, color)])
        return True

    def recolor(self, name: str, color: str) -> None:
        self._save_definitions([(n, color if n == name else c) for n, c in self.definitions()])

    def rename(self, old: str, new: str) -> bool:
        new = _clean(new)
        if not new or new == old or new in self.names():
            return False
        self._save_definitions([(new if n == old else n, c) for n, c in self.definitions()])
        self._rewrite(old, lambda names: [new if n == old else n for n in names])
        return True

    def delete(self, name: str) -> None:
        self._save_definitions([(n, c) for n, c in self.definitions() if n != name])
        self._rewrite(name, lambda names: [n for n in names if n != name])

    def _rewrite(self, name: str, fn) -> None:
        """Atualiza os arquivos conhecidos (índice) que têm a etiqueta `name`."""
        changed = []
        for uri in self.files_with(name):
            path = uri_to_path(uri)
            try:
                new = fn(read_tags(path))
                write_tags(path, new)
                self.remember(uri, new)
                changed.append(uri)
            except TagError as err:
                log(f"etiquetas: {err}")
        self._files_changed(changed)

    # ── arquivos ──
    def tags_of(self, uri: str) -> list[str]:
        path = uri_to_path(uri)
        return read_tags(path) if path else []

    def set_tags(self, uris: list[str], names: list[str]) -> None:
        done = []
        for uri in uris:
            path = uri_to_path(uri)
            if path is None:
                continue
            write_tags(path, names)
            self.remember(uri, names)
            done.append(uri)
        self._files_changed(done)

    def toggle(self, uris: list[str], name: str) -> bool:
        """Se todos já têm a etiqueta, tira de todos; senão, põe em todos.
        Retorna True se a etiqueta foi aplicada."""
        local = [u for u in uris if uri_to_path(u)]
        apply = not local or not all(name in self.tags_of(u) for u in local)
        self._change(local, lambda names: (names + [name]) if apply and name not in names
                     else ([n for n in names if n != name] if not apply else names))
        return apply

    def add(self, uris: list[str], name: str) -> None:
        self._change([u for u in uris if uri_to_path(u)],
                     lambda names: names if name in names else names + [name])

    def clear(self, uris: list[str]) -> None:
        self._change([u for u in uris if uri_to_path(u)], lambda _names: [])

    def _change(self, uris, fn) -> None:
        done, errors = [], []
        for uri in uris:
            path = uri_to_path(uri)
            try:
                new = fn(read_tags(path))
                write_tags(path, new)
                self.remember(uri, new)
                done.append(uri)
            except TagError as err:
                errors.append(str(err))
        self._files_changed(done)
        if errors:
            raise TagError("; ".join(errors[:3]))

    def _files_changed(self, uris) -> None:
        if uris:
            self._save_index()
            if self.on_files_changed is not None:
                self.on_files_changed(uris)
            self._notify()

    # ── índice ──
    def _load_index(self) -> dict[str, list[str]]:
        try:
            with open(self.index_path, encoding="utf-8") as fh:
                data = json.load(fh)
            return {k: list(v) for k, v in data.items() if isinstance(v, list)}
        except (OSError, ValueError):
            return {}

    def _save_index(self) -> None:
        with self._lock:
            data = dict(self.index)
        try:
            os.makedirs(os.path.dirname(self.index_path), exist_ok=True)
            tmp = self.index_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(data, fh, ensure_ascii=False)
            os.replace(tmp, self.index_path)
        except OSError as err:
            log(f"etiquetas: falha ao salvar o índice ({err})")

    def remember(self, uri: str, names: list[str]) -> bool:
        """Anota no índice (sem gravar em disco). True se mudou."""
        with self._lock:
            old = self.index.get(uri)
            if names:
                if old == names:
                    return False
                self.index[uri] = list(names)
            elif old is None:
                return False
            else:
                del self.index[uri]
        return True

    def seen(self, uri: str, names: list[str]) -> None:
        """O Nautilus mostrou este arquivo (provedor de informações)."""
        if self.remember(uri, names):
            self._save_index()

    def files_with(self, name: str) -> list[str]:
        """Arquivos do índice que *ainda* têm a etiqueta (confere no disco)."""
        out, stale = [], []
        with self._lock:
            items = list(self.index.items())
        for uri, names in items:
            if name not in names:
                continue
            path = uri_to_path(uri)
            if path is None or not os.path.exists(path):
                stale.append(uri)
                continue
            current = read_tags(path)
            if current != names:
                self.remember(uri, current)
            if name in current:
                out.append(uri)
        for uri in stale:
            self.remember(uri, [])
        if stale:
            self._save_index()
        return sorted(out, key=lambda u: os.path.basename(uri_to_path(u) or u).lower())

    def scan(self, root: str, *, max_files: int = 200_000, stop=None) -> int:
        """Procura arquivos etiquetados em `root` (pula pastas ocultas). Devolve quantos
        achou. Feito para rodar numa thread."""
        found = seen = 0
        for dirpath, dirnames, filenames in os.walk(root):
            if stop is not None and stop():
                break
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in dirnames + filenames:
                seen += 1
                path = os.path.join(dirpath, name)
                names = read_tags(path)
                if names:
                    found += 1
                    self.remember(path_to_uri(path), names)
            if seen > max_files:
                log(f"etiquetas: busca parada em {max_files} itens")
                break
        self._save_index()
        return found

    # ── avisos ──
    def on_change(self, cb) -> None:
        self._listeners.append(cb)

    def off_change(self, cb) -> None:
        if cb in self._listeners:
            self._listeners.remove(cb)

    def _notify(self) -> None:
        for cb in list(self._listeners):
            try:
                cb()
            except Exception as err:  # noqa: BLE001
                log(f"etiquetas: ouvinte: {err}")


def _clean(name: str) -> str:
    return (name or "").replace(",", " ").strip()[:60]
__VITRINE_ARQUIVO_14__
mkdir -p "vitrine"
cat > 'vitrine/tagui.py' <<'__VITRINE_ARQUIVO_15__'
"""Telas das etiquetas: botão da barra de ferramentas, seção da barra lateral, página
com os arquivos de uma etiqueta e a tela "Todas as etiquetas…".

As bolinhas coloridas são os próprios ícones de emblema (assets/vitrine-tag-<cor>.svg),
então a cor é a mesma no Nautilus, nos menus e aqui.
"""

from __future__ import annotations

import os
import threading

from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

from . import native, util
from .tags import PALETTE, TagError, uri_to_path
from .util import guarded, log


def dot(color: str, size: int = 12) -> Gtk.Image:
    img = Gtk.Image.new_from_icon_name(f"vitrine-tag-{color}")
    img.set_pixel_size(size)
    return img


def _apply(ctl, fn) -> None:
    try:
        fn()
    except TagError as err:
        ctl.toast(f"Não foi possível etiquetar: {err}")


# ───────────────────────── botão da barra de ferramentas ─────────────────────────
class TagMenuButton(Gtk.MenuButton):
    """Aplica/remove etiquetas nos itens selecionados."""

    def __init__(self, ctl) -> None:
        super().__init__(icon_name="vitrine-tag-symbolic", tooltip_text="Etiquetas",
                         valign=Gtk.Align.CENTER)
        self.add_css_class("flat")
        self.ctl = ctl
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.add_css_class("navigation-sidebar")
        self.list.connect("row-activated", self._on_row)
        pop = Gtk.Popover(child=self.list)
        pop.connect("show", lambda *_a: self.refresh())
        self.set_popover(pop)

    def _uris(self) -> list[str]:
        return [u for u in native.selected_uris(self.ctl.model_watch.get()) if uri_to_path(u)]

    def refresh(self) -> None:
        self.list.remove_all()
        uris = self._uris()
        store = self.ctl.ext.tags
        current = [set(store.tags_of(u)) for u in uris]
        for name, color in store.definitions():
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=10)
            box.append(dot(color))
            box.append(Gtk.Label(label=name, xalign=0, hexpand=True))
            check = Gtk.Image.new_from_icon_name("object-select-symbolic")
            check.set_visible(bool(current) and all(name in c for c in current))
            box.append(check)
            row.set_child(box)
            row.set_sensitive(bool(uris))
            row._vitrine_tag = name
            self.list.append(row)
        for label, action in (("Remover etiquetas", "clear"), ("Todas as etiquetas…", "manage")):
            row = Gtk.ListBoxRow()
            row.set_child(Gtk.Label(label=label, xalign=0))
            row._vitrine_action = action
            row.set_sensitive(action == "manage" or any(current))
            self.list.append(row)

    @guarded
    def _on_row(self, _lb, row) -> None:
        store = self.ctl.ext.tags
        uris = self._uris()
        name = getattr(row, "_vitrine_tag", None)
        action = getattr(row, "_vitrine_action", None)
        if name:
            _apply(self.ctl, lambda: store.toggle(uris, name))
            self.refresh()
            return
        self.get_popover().popdown()
        if action == "clear":
            _apply(self.ctl, lambda: store.clear(uris))
        elif action == "manage":
            open_manager(self.ctl)


# ───────────────────────── seção da barra lateral ─────────────────────────
class TagSidebar(Gtk.Box):
    """Seção "Etiquetas" recolhível, logo abaixo dos locais nativos."""

    def __init__(self, ctl) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.add_css_class("vitrine-tags-section")
        self.ctl = ctl
        cfg = ctl.cfg
        self.arrow = Gtk.Image()
        head = Gtk.Box(spacing=6)
        title = Gtk.Label(label="Etiquetas", xalign=0, hexpand=True)
        title.add_css_class("vitrine-sidebar-heading")
        head.append(title)
        head.append(self.arrow)
        self.header = Gtk.Button(child=head)
        self.header.add_css_class("flat")
        self.header.add_css_class("vitrine-tags-header")
        self.header.connect("clicked", lambda *_a: self.set_expanded(not self.revealer.get_reveal_child()))
        self.append(self.header)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.list.add_css_class("navigation-sidebar")
        self.list.connect("row-activated", self._on_row)
        self.revealer = Gtk.Revealer(child=self.list,
                                     transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.append(self.revealer)
        self.set_expanded(bool(cfg.get("tags_section_expanded")), save=False)
        self.listener = self.refresh   # FinderStyle desconecta ao remover a seção
        ctl.ext.tags.on_change(self.listener)
        self.refresh()

    def set_expanded(self, on: bool, save: bool = True) -> None:
        self.revealer.set_reveal_child(on)
        self.arrow.set_from_icon_name("pan-down-symbolic" if on else "pan-end-symbolic")
        if save:
            self.ctl.cfg.set("tags_section_expanded", on)

    def refresh(self) -> None:
        self.list.remove_all()
        for name, color in self.ctl.ext.tags.definitions():
            self.list.append(self._row(dot(color, 14), name, name))
        self.list.append(self._row(Gtk.Image.new_from_icon_name("view-more-horizontal-symbolic"),
                                   "Todas as etiquetas…", None))

    def _row(self, icon, label, tag) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        box = Gtk.Box(spacing=12)
        box.append(icon)
        box.append(Gtk.Label(label=label, xalign=0, hexpand=True,
                             ellipsize=Pango.EllipsizeMode.END))
        row.set_child(box)
        row._vitrine_tag = tag
        if tag:
            drop = Gtk.DropTarget.new(Gdk.FileList, Gdk.DragAction.COPY)
            drop.connect("drop", self._on_drop, tag)
            row.add_controller(drop)
        return row

    @guarded
    def _on_row(self, _lb, row) -> None:
        tag = getattr(row, "_vitrine_tag", None)
        if tag:
            self.ctl.show_tag(tag)
        else:
            self.list.unselect_all()
            open_manager(self.ctl)

    @guarded
    def _on_drop(self, _target, value, _x, _y, tag) -> bool:
        uris = [f.get_uri() for f in value.get_files()]
        _apply(self.ctl, lambda: self.ctl.ext.tags.add(uris, tag))
        n = len(uris)
        self.ctl.toast(f"Etiqueta {tag} aplicada a {n} {'item' if n == 1 else 'itens'}")
        return True

    def select(self, tag: str | None) -> None:
        row = self.list.get_first_child()
        while row is not None:
            if tag is not None and getattr(row, "_vitrine_tag", None) == tag:
                self.list.select_row(row)
                return
            row = row.get_next_sibling()
        self.list.unselect_all()


# ───────────────────────── página de uma etiqueta ─────────────────────────
class TagPage(Gtk.ScrolledWindow):
    __gtype_name__ = "VitrineTagPage"

    def __init__(self, ctl) -> None:
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.add_css_class("vitrine-computer")
        self.ctl = ctl
        self.tag: str | None = None
        self._scanning = False
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        for side in ("top", "bottom", "start", "end"):
            getattr(body, f"set_margin_{side}")(24 if side in ("top", "bottom") else 18)
        clamp = Adw.Clamp(maximum_size=1100, tightening_threshold=700, child=body)
        self.set_child(clamp)
        head = Gtk.Box(spacing=12)
        self.head_dot = Gtk.Image()
        self.head_dot.set_pixel_size(22)
        self.title = Gtk.Label(xalign=0)
        self.title.add_css_class("title-1")
        self.count = Gtk.Label(xalign=0, hexpand=True, valign=Gtk.Align.BASELINE_FILL)
        self.count.add_css_class("dim-label")
        self.scan_btn = Gtk.Button(label="Procurar na pasta pessoal", valign=Gtk.Align.CENTER,
                                   tooltip_text="Acha arquivos etiquetados por outros programas")
        self.scan_btn.connect("clicked", lambda *_a: self.scan())
        for w in (self.head_dot, self.title, self.count, self.scan_btn):
            head.append(w)
        body.append(head)
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, homogeneous=True,
                                max_children_per_line=8, min_children_per_line=2,
                                column_spacing=6, row_spacing=6, valign=Gtk.Align.START)
        self.flow.add_css_class("vitrine-folders")
        self.flow.connect("child-activated", self._on_activated)
        body.append(self.flow)
        self.empty = Gtk.Label(wrap=True, xalign=0, label=(
            "Nenhum arquivo com esta etiqueta. Arquivos etiquetados por outros programas "
            "aparecem depois de abertos no Nautilus, ou com “Procurar na pasta pessoal”."))
        self.empty.add_css_class("dim-label")
        body.append(self.empty)
        ctl.ext.tags.on_change(lambda: self.get_mapped() and self.refresh())

    def show(self, tag: str) -> None:
        self.tag = tag
        self.refresh()

    def refresh(self) -> None:
        store = self.ctl.ext.tags
        tag = self.tag
        if tag is None:
            return
        self.head_dot.set_from_icon_name(f"vitrine-tag-{store.color_of(tag)}")
        self.title.set_label(tag)
        self.flow.remove_all()
        uris = store.files_with(tag)
        for uri in uris:
            self.flow.append(self._tile(uri, store))
        n = len(uris)
        self.count.set_label(f"{n} {'item' if n == 1 else 'itens'}")
        self.empty.set_visible(n == 0)

    def _tile(self, uri: str, store) -> Gtk.FlowBoxChild:
        gfile = Gio.File.new_for_uri(uri)
        try:
            info = gfile.query_info("standard::icon,standard::display-name,standard::type,"
                                    "thumbnail::path", Gio.FileQueryInfoFlags.NONE, None)
        except GLib.Error:
            info = None
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.add_css_class("vitrine-tile")
        thumb = info.get_attribute_byte_string("thumbnail::path") if info else None
        if thumb and os.path.exists(thumb):
            pic = Gtk.Picture.new_for_filename(thumb)
            pic.set_content_fit(Gtk.ContentFit.CONTAIN)
            pic.set_size_request(64, 64)
            pic.add_css_class("vitrine-thumb")
            box.append(pic)
        else:
            img = Gtk.Image.new_from_gicon(info.get_icon()) if info and info.get_icon() \
                else Gtk.Image.new_from_icon_name("text-x-generic")
            img.set_pixel_size(64)
            box.append(img)
        name = info.get_display_name() if info else gfile.get_basename()
        box.append(Gtk.Label(label=name, ellipsize=Pango.EllipsizeMode.MIDDLE, lines=2, wrap=True,
                             justify=Gtk.Justification.CENTER, max_width_chars=14))
        dots = Gtk.Box(spacing=2, halign=Gtk.Align.CENTER)
        for t in store.tags_of(uri):
            dots.append(dot(store.color_of(t), 10))
        box.append(dots)
        child = Gtk.FlowBoxChild(child=box)
        child.set_tooltip_text(uri_to_path(uri) or uri)
        child._vitrine_uri = uri
        child._vitrine_dir = bool(info and info.get_file_type() == Gio.FileType.DIRECTORY)
        menu = Gtk.GestureClick(button=Gdk.BUTTON_SECONDARY)
        menu.connect("pressed", self._on_menu, child)
        child.add_controller(menu)
        return child

    @guarded
    def _on_activated(self, _fb, child) -> None:
        if child._vitrine_dir:
            self.ctl.leave_tag_and_open(child._vitrine_uri)
        else:
            util.open_uri(child._vitrine_uri)

    @guarded
    def _on_menu(self, gesture, _n, x, y, child) -> None:
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        uri = child._vitrine_uri
        group = Gio.SimpleActionGroup()
        menu = Gio.Menu()

        def add(label, name, fn):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", lambda *_a: fn())
            group.add_action(act)
            menu.append(label, f"vtag.{name}")

        add("Abrir", "open", lambda: self._on_activated(None, child))
        add("Mostrar na pasta", "reveal", lambda: self.ctl.leave_tag_and_reveal(uri))
        add(f"Remover a etiqueta {self.tag}", "untag",
            lambda: _apply(self.ctl, lambda: self.ctl.ext.tags.toggle([uri], self.tag)))
        child.insert_action_group("vtag", group)
        pop = Gtk.PopoverMenu.new_from_model(menu)
        pop.set_parent(child)
        pop.set_has_arrow(False)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        pop.set_pointing_to(rect)
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()

    def scan(self) -> None:
        if self._scanning:
            return
        self._scanning = True
        self.scan_btn.set_sensitive(False)
        self.scan_btn.set_label("Procurando…")
        store = self.ctl.ext.tags

        def work():
            try:
                found = store.scan(os.path.expanduser("~"))
            except Exception as err:  # noqa: BLE001
                log(f"etiquetas: busca falhou ({err})")
                found = -1
            GLib.idle_add(done, found)

        def done(found):
            self._scanning = False
            self.scan_btn.set_sensitive(True)
            self.scan_btn.set_label("Procurar na pasta pessoal")
            self.refresh()
            if found >= 0:
                self.ctl.toast(f"{found} {'item etiquetado encontrado' if found == 1 else 'itens etiquetados encontrados'}")
            return GLib.SOURCE_REMOVE

        threading.Thread(target=work, daemon=True, name="vitrine-tag-scan").start()


# ───────────────────────── Todas as etiquetas… ─────────────────────────
def open_manager(ctl) -> None:
    dialog = TagManager(ctl)
    dialog.present(ctl.win)


class TagManager(Adw.Dialog):
    """Criar, renomear, trocar a cor e apagar etiquetas."""

    def __init__(self, ctl) -> None:
        super().__init__(title="Etiquetas", content_width=420, content_height=520)
        self.ctl = ctl
        self.store = ctl.ext.tags
        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        page = Adw.PreferencesPage()
        self.group = Adw.PreferencesGroup(
            description="Os nomes ficam gravados nos arquivos (atributo user.xdg.tags) e "
                        "valem em outros gerenciadores de arquivos. Renomear ou apagar "
                        "atualiza os arquivos que a Vitrine conhece.")
        page.add(self.group)
        add_group = Adw.PreferencesGroup()
        add_btn = Gtk.Button(label="Nova etiqueta", halign=Gtk.Align.CENTER)
        add_btn.add_css_class("pill")
        add_btn.connect("clicked", lambda *_a: self._new())
        add_group.add(add_btn)
        page.add(add_group)
        view.set_content(page)
        self.set_child(view)
        self.rows: list = []
        self._build()

    def _build(self) -> None:
        for row in self.rows:
            self.group.remove(row)
        self.rows = []
        for name, color in self.store.definitions():
            row = Adw.EntryRow(title="Nome", text=name, show_apply_button=True)
            row.add_prefix(self._color_button(name, color))
            delete = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER,
                                tooltip_text="Apagar etiqueta")
            delete.add_css_class("flat")
            delete.connect("clicked", lambda *_a, n=name: self._delete(n))
            row.add_suffix(delete)
            row.connect("apply", lambda r, old=name: self._rename(old, r.get_text()))
            self.group.add(row)
            self.rows.append(row)

    def _color_button(self, name: str, color: str) -> Gtk.MenuButton:
        grid = Gtk.FlowBox(max_children_per_line=7, selection_mode=Gtk.SelectionMode.NONE)
        btn = Gtk.MenuButton(child=dot(color, 16), valign=Gtk.Align.CENTER,
                             tooltip_text="Cor")
        btn.add_css_class("flat")
        for key, (_hex, _emoji, label) in PALETTE.items():
            choice = Gtk.Button(child=dot(key, 18), tooltip_text=label)
            choice.add_css_class("flat")
            choice.add_css_class("circular")
            choice.connect("clicked", lambda *_a, k=key: (btn.popdown(), self._recolor(name, k)))
            grid.append(choice)
        btn.set_popover(Gtk.Popover(child=grid))
        return btn

    @guarded
    def _rename(self, old: str, new: str) -> None:
        if self.store.rename(old, new):
            self.ctl.toast(f"Etiqueta {old} agora se chama {new.strip()}")
        self._build()

    @guarded
    def _recolor(self, name: str, color: str) -> None:
        self.store.recolor(name, color)
        self._build()

    @guarded
    def _delete(self, name: str) -> None:
        self.store.delete(name)
        self._build()

    @guarded
    def _new(self) -> None:
        n = 1
        while f"Etiqueta {n}" in self.store.names():
            n += 1
        self.store.create(f"Etiqueta {n}", "gray")
        self._build()
        if self.rows:
            self.rows[-1].grab_focus()
__VITRINE_ARQUIVO_15__
mkdir -p "vitrine"
cat > 'vitrine/util.py' <<'__VITRINE_ARQUIVO_16__'
"""Utilitários: log, varredura da árvore de widgets e operações de arquivo nativas."""

from __future__ import annotations

import functools
import os
import time
import traceback

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, GObject, Gtk  # noqa: E402

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
LOG_DIR = os.path.join(GLib.get_user_cache_dir(), "nautilus-vitrine")
LOG_PATH = os.path.join(LOG_DIR, "vitrine.log")
DEBUG = os.environ.get("VITRINE_DEBUG", "") not in ("", "0")
_LOG_MAX_BYTES = 512 * 1024


def log(msg: str) -> None:
    """Escreve uma linha em ~/.cache/nautilus-vitrine/vitrine.log."""
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > _LOG_MAX_BYTES:
            os.replace(LOG_PATH, LOG_PATH + ".1")
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except OSError:
        pass


def debug(msg: str) -> None:
    if DEBUG:
        log("[debug] " + msg)


def guarded(fn):
    """Envolve callbacks de sinal: uma exceção vira linha de log, nunca derruba o Nautilus."""

    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except Exception:  # noqa: BLE001
            log(f"ERRO em {fn.__qualname__}:\n{traceback.format_exc()}")
            return None

    return wrapper


def gtype_name(obj) -> str:
    try:
        return GObject.type_name(obj.__gtype__)
    except Exception:  # noqa: BLE001
        return type(obj).__name__


def walk(widget):
    """Percorre o widget e todos os descendentes (profundidade primeiro)."""
    if widget is None:
        return
    stack = [widget]
    while stack:
        w = stack.pop()
        yield w
        children = []
        child = w.get_first_child()
        while child is not None:
            children.append(child)
            child = child.get_next_sibling()
        stack.extend(reversed(children))


def find_first(root, pred):
    for w in walk(root):
        try:
            if pred(w):
                return w
        except Exception:  # noqa: BLE001
            continue
    return None


def find_by_type_name(root, name: str):
    return find_first(root, lambda w: gtype_name(w) == name)


def ancestor(widget, pred):
    w = widget.get_parent() if widget is not None else None
    while w is not None:
        if pred(w):
            return w
        w = w.get_parent()
    return None


def dump_tree(root, max_depth: int = 18) -> str:
    """Árvore de widgets em texto (para depuração em versões novas do Nautilus)."""
    lines = []

    def rec(w, depth):
        if depth > max_depth:
            return
        bid = ""
        try:
            bid = w.get_buildable_id() or ""
        except Exception:  # noqa: BLE001
            pass
        css = ",".join(w.get_css_classes() or [])
        lines.append(f"{'  ' * depth}{gtype_name(w)} id={bid!r} css=[{css}] vis={w.get_visible()}")
        c = w.get_first_child()
        while c is not None:
            rec(c, depth + 1)
            c = c.get_next_sibling()

    rec(root, 0)
    return "\n".join(lines)


def is_tab_view(w) -> bool:
    return isinstance(w, Adw.TabView)


def is_toolbar_view(w) -> bool:
    return isinstance(w, Adw.ToolbarView)


# ── Operações de arquivo do próprio Nautilus (D-Bus) ─────────────────────────
# Usar a API FileOperations2 do Nautilus em vez de Gio direto mantém o
# comportamento nativo: barra de progresso, diálogos de conflito e Desfazer (Ctrl+Z).

_FILE_OPS_BUS = "org.gnome.Nautilus"
_FILE_OPS_PATH = "/org/gnome/Nautilus/FileOperations2"
_FILE_OPS_IFACE = "org.gnome.Nautilus.FileOperations2"


def _platform_data() -> dict:
    return {"timestamp": GLib.Variant("u", 0)}


def file_operation(method: str, args: tuple, signature: str) -> None:
    """Chama um método de FileOperations2 de forma assíncrona."""

    def on_done(conn, result):
        try:
            conn.call_finish(result)
        except GLib.Error as err:
            log(f"FileOperations2.{method} falhou: {err.message}")

    def on_bus(_src, result):
        try:
            conn = Gio.bus_get_finish(result)
        except GLib.Error as err:
            log(f"sem barramento de sessão: {err.message}")
            return
        params = GLib.Variant(f"({signature}a{{sv}})", (*args, _platform_data()))
        conn.call(
            _FILE_OPS_BUS,
            _FILE_OPS_PATH,
            _FILE_OPS_IFACE,
            method,
            params,
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
            on_done,
        )

    Gio.bus_get(Gio.BusType.SESSION, None, on_bus)


def move_uris(uris: list[str], dest_dir_uri: str) -> None:
    file_operation("MoveURIs", (uris, dest_dir_uri), "ass")


def copy_uris(uris: list[str], dest_dir_uri: str) -> None:
    file_operation("CopyURIs", (uris, dest_dir_uri), "ass")


def trash_uris(uris: list[str]) -> None:
    file_operation("TrashURIs", (uris,), "as")


def open_uri(uri: str) -> None:
    """Abre com o aplicativo padrão (igual ao duplo clique do Nautilus)."""

    def done(_src, result):
        try:
            Gio.AppInfo.launch_default_for_uri_finish(result)
        except GLib.Error as err:
            log(f"não foi possível abrir {uri}: {err.message}")

    Gio.AppInfo.launch_default_for_uri_async(uri, None, None, done)


def show_in_new_window(uri: str) -> None:
    """org.freedesktop.FileManager1.ShowFolders — abre uma janela nova do Nautilus."""

    def on_bus(_src, result):
        try:
            conn = Gio.bus_get_finish(result)
        except GLib.Error:
            return
        conn.call(
            "org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1",
            "org.freedesktop.FileManager1",
            "ShowFolders",
            GLib.Variant("(ass)", ([uri], "")),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
            None,
        )

    Gio.bus_get(Gio.BusType.SESSION, None, on_bus)


def copy_text_to_clipboard(widget: Gtk.Widget, text: str) -> None:
    widget.get_clipboard().set(text)


def human_size(n: int) -> str:
    return GLib.format_size(n)


def format_time(dt: GLib.DateTime | None) -> str:
    if dt is None:
        return "—"
    return dt.to_local().format("%d/%m/%Y %H:%M")


def snapshot_png(widget: Gtk.Widget, path: str) -> bool:
    """Salva o widget (ex.: a janela inteira) como PNG. Usado pelo autoteste."""
    gi.require_version("Graphene", "1.0")
    from gi.repository import Graphene

    w, h = widget.get_width(), widget.get_height()
    paintable = Gtk.WidgetPaintable.new(widget).get_current_image()
    snap = Gtk.Snapshot()
    paintable.snapshot(snap, w, h)
    node = snap.to_node()
    native = widget.get_native()
    if node is None or native is None or w <= 0 or h <= 0:
        return False
    tex = native.get_renderer().render_texture(node, Graphene.Rect().init(0, 0, w, h))
    return bool(tex.save_to_png(path))
__VITRINE_ARQUIVO_16__
mkdir -p "vitrine"
cat > 'vitrine/window.py' <<'__VITRINE_ARQUIVO_17__'
"""Controlador por janela: injeta Colunas + Pré-visualização e aplica as regras por pasta."""

from __future__ import annotations

import os

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from . import discovery, native
from .columns import ColumnStrip
from .computer import ComputerPage
from .finder import FinderStyle
from .gallery import GalleryView
from .history import History
from .preview import PreviewPane
from .tagui import TagPage
from .util import (ancestor, debug, dump_tree, find_by_type_name, find_first, gtype_name, guarded,
                   log, walk)

_MOD_MASK = (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
             | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)
_MEDIA_SAMPLE = 250
_NATIVE_STEP_TIMEOUT_MS = 4000   # o Nautilus não respondeu a um Voltar/Avançar pedido
_LEAVE_FALLBACK_MS = 1500        # saiu do Meu computador e o Nautilus não navegou
_HISTORY_KEYS = {"<alt>left", "<alt>right", "back", "forward"}


def _is_history_trigger(text: str) -> bool:
    """"<Alt>Left|Back" → True; "<Alt>Up" → False (só Voltar/Avançar)."""
    parts = [p.strip().lower() for p in (text or "").split("|") if p.strip()]
    return bool(parts) and all(p in _HISTORY_KEYS for p in parts)


class WindowController:
    def __init__(self, ext, win: Gtk.Window) -> None:
        self.ext = ext
        self.cfg = ext.cfg
        self.win = win
        self.columns_on = False
        self.tab_view: Adw.TabView | None = None
        self.strip: ColumnStrip | None = None
        self.preview: PreviewPane | None = None
        self.paned: Gtk.Paned | None = None
        self.btn_columns: Gtk.ToggleButton | None = None
        self.btn_preview: Gtk.ToggleButton | None = None
        self._syncing_buttons = False
        self._setting_pos = False
        self._pos_initialized = False
        self._reveal_target: tuple[str, str] | None = None
        self._reveal_source = 0
        self._media_cache: dict[str, bool] = {}
        self.model_watch = native.ModelWatch(self._on_native_selection)
        self.computer: ComputerPage | None = None
        self.content_stack: Gtk.Stack | None = None
        self.sidebar_list: Gtk.ListBox | None = None
        self._computer_visible = False
        self.toasts_shown = 0
        self.actions: Gio.SimpleActionGroup | None = None
        self._native_forward_probe: Gtk.Button | None = None
        self._nautilus_prefs = Gio.Settings.new("org.gnome.nautilus.preferences")
        self._mouse_takeover = False
        self.history_shortcuts_removed = 0
        self._leave_source = 0
        self.style: FinderStyle | None = None
        self.tag_page: TagPage | None = None
        self.gallery: GalleryView | None = None
        self.gallery_on = False
        self._tag_visible: str | None = None
        self.tag_sidebar = None  # seção Etiquetas (só no estilo Finder)

    # ───────────────────────── injeção ─────────────────────────
    def inject(self) -> bool:
        if self.ext.debug_dump:
            log("árvore da janela:\n" + dump_tree(self.win))
        tv = native.find_tab_view(self.win)
        if tv is None:
            log("inject: AdwTabView não encontrado; a estrutura do Nautilus mudou")
            return False
        toolbar = ancestor(tv, lambda w: isinstance(w, Adw.ToolbarView))
        if toolbar is None or toolbar.get_content() is not tv:
            log(f"inject: pai inesperado do TabView ({gtype_name(tv.get_parent())})")
            return False
        self.tab_view = tv

        self.strip = ColumnStrip(
            column_width=int(self.cfg.get("column_width")),
            max_visible=int(self.cfg.get("max_visible_columns")),
            on_navigate=self.navigate,
            on_reveal=self.reveal,
        )
        self.strip.set_visible(False)
        self.preview = PreviewPane(
            on_navigate=self.navigate,
            on_reveal=self.reveal,
            on_quicklook=self.quicklook,
        )
        self.preview.set_visible(bool(self.cfg.get("preview_visible")))

        self.computer = ComputerPage(self, self.ext.hub)

        # [colunas | (abas do Nautilus ou Meu computador)]  ‖  [pré-visualização]
        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        toolbar.set_content(None)  # `tv` continua vivo: a referência Python o segura
        tv.set_hexpand(True)
        self.content_stack = Gtk.Stack(hexpand=True, hhomogeneous=False, vhomogeneous=False)
        self.content_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.content_stack.set_transition_duration(120)
        self.content_stack.add_named(tv, "tabs")
        self.content_stack.add_named(self.computer, "computer")
        self.tag_page = TagPage(self)
        self.content_stack.add_named(self.tag_page, "tag")
        self.gallery = GalleryView(self)
        self.content_stack.add_named(self.gallery, "gallery")
        self.content_stack.set_visible_child_name("tabs")
        inner.append(self.strip)
        inner.append(self.content_stack)
        # Sonda invisível: o GTK deixa um botão ligado a uma ação sensível ou não conforme
        # a ação está ativa. Assim sabemos se o Avançar *nativo* está ativo (usado pelo
        # plano B do histórico), já que os botões ← → visíveis passam a usar nossas ações.
        self._native_forward_probe = Gtk.Button(action_name="slot.forward", visible=False)
        inner.append(self._native_forward_probe)

        self.paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.paned.set_wide_handle(False)
        self.paned.set_start_child(inner)
        self.paned.set_end_child(self.preview)
        self.paned.set_resize_start_child(True)
        self.paned.set_shrink_start_child(False)
        self.paned.set_resize_end_child(False)
        self.paned.set_shrink_end_child(False)
        self.paned.connect("notify::max-position", self._on_paned_max)
        self.paned.connect("notify::position", self._on_paned_pos)
        toolbar.set_content(self.paned)

        self._install_actions()
        self._inject_buttons()
        self._inject_sidebar_row()
        self._install_keys()
        self._take_over_history()
        self.style = FinderStyle(self)
        self.apply_window_style()

        tv.connect("notify::selected-page", self._on_tab_switched)
        tv.connect("page-attached", lambda _tv, page, _pos: self._watch_slot(page.get_child()))
        for i in range(tv.get_n_pages()):
            self._watch_slot(tv.get_nth_page(i).get_child())
        self.win.connect("destroy", self._on_destroy)

        GLib.idle_add(self._initial_sync, priority=GLib.PRIORITY_LOW)
        log("janela injetada com sucesso")
        if os.environ.get("VITRINE_SELFTEST", "") not in ("", "0") and not self.ext.selftest_started:
            from . import selftest

            self.ext.selftest_started = True
            GLib.timeout_add(2000, selftest.run, self)
        return True

    def _initial_sync(self) -> bool:
        slot = self.active_slot()
        if slot is not None:
            self._on_slot_location(slot)
        if slot is not None and self.should_start_on_computer(native.slot_uri(slot)):
            # O Meu computador *substitui* a pasta pessoal como primeiro lugar da aba,
            # então o Voltar fica desativado, como no Nautilus quando não há para onde voltar.
            self.history(slot).start_on_computer()
            self._display_computer(True)
            self._update_history_actions()
            log("janela aberta direto no Meu computador")
        return GLib.SOURCE_REMOVE

    def apply_window_style(self) -> None:
        """Estilo da janela: "finder" aplica o visual do Finder; "nautilus" remove tudo
        o que ele acrescentou (vale na hora, em todas as janelas)."""
        if self.style is None:
            return
        if self.cfg.get("window_style") == "finder":
            self.style.apply()
        else:
            self.style.remove()

    def _style_sync(self) -> None:
        if self.style is not None and self.style.active:
            self.style.sync()

    def should_start_on_computer(self, uri: str | None) -> bool:
        """Só quando a janela abriu na pasta pessoal (menu de aplicativos, Ctrl+N).
        Se outro programa pediu uma pasta específica, ela é respeitada."""
        if not self.cfg.get("start_on_computer") or not uri:
            return False
        home = Gio.File.new_for_path(os.path.expanduser("~"))
        return Gio.File.new_for_uri(uri).equal(home)

    def apply_computer_settings(self) -> None:
        if self.sidebar_list is not None:
            self.sidebar_list.set_visible(bool(self.cfg.get("computer_in_sidebar")))
        if self.computer is not None:
            if self.computer.get_mapped():
                self.computer.refresh()
            else:
                self.computer._dirty = True

    def _inject_sidebar_row(self) -> None:
        """Entrada "Meu computador" no topo da barra lateral.

        Usa a API pública AdwToolbarView.add_top_bar da própria barra lateral: nenhum
        widget do Nautilus é movido; a lista nativa de locais continua intocada."""
        sidebar = find_by_type_name(self.win, "NautilusSidebar")
        tbv = ancestor(sidebar, lambda w: isinstance(w, Adw.ToolbarView)) if sidebar else None
        if tbv is None or tbv.get_content() is not sidebar:
            log("inject: barra lateral com estrutura inesperada; sem a entrada Meu computador")
            return
        lb = Gtk.ListBox()
        lb.add_css_class("navigation-sidebar")
        lb.add_css_class("vitrine-sidebar")
        lb.set_selection_mode(Gtk.SelectionMode.SINGLE)
        row = Gtk.ListBoxRow()
        row.set_tooltip_text("Meu computador (Ctrl+Shift+C)")
        box = Gtk.Box(spacing=12)
        box.append(Gtk.Image.new_from_icon_name("computer-symbolic"))
        box.append(Gtk.Label(label="Meu computador", xalign=0, hexpand=True))
        box.append(self._sidebar_menu_button())
        row.set_child(box)
        lb.append(row)
        lb.connect("row-activated", lambda *_a: self.show_computer(True))
        tbv.add_top_bar(lb)
        self.sidebar_list = lb
        lb.set_visible(bool(self.cfg.get("computer_in_sidebar")))

        # Clicar em qualquer local nativo da barra lateral sai do Meu computador.
        # (A nossa linha está *ao lado* da NautilusSidebar, numa barra superior do
        # AdwToolbarView, e não dentro dela: este gesto nunca vê cliques no ☰.)
        click = Gtk.GestureClick.new()
        click.set_button(Gdk.BUTTON_PRIMARY)
        click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        click.connect("released", self._on_sidebar_click, sidebar)
        sidebar.add_controller(click)

    def _sidebar_menu_button(self) -> Gtk.MenuButton:
        """☰ encostado à direita da linha, onde o Nautilus põe o ⏏ dos dispositivos.

        Não ativa a linha nem muda a seleção: ao receber o clique, o botão *reivindica*
        a sequência do evento (EventSequenceState.CLAIMED) e o GTK cancela os gestos dos
        widgets acima dele, inclusive o do ListBox que ativaria/selecionaria a linha."""
        menu = Gio.Menu()
        menu.append("Personalizar o Meu computador…", "vitrine.customize")
        menu.append("Sobre a Vitrine", "vitrine.about")
        btn = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu,
                             valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER,
                             tooltip_text="Opções do Meu computador")
        btn.set_margin_start(4)
        # Mesma classe do botão ⏏ nativo (nautilus-sidebar-row.ui): o CSS do próprio
        # Nautilus deixa o botão igual aos nativos nos temas claro e escuro.
        btn.add_css_class("sidebar-button")
        btn.set_focus_on_click(False)
        return btn

    @guarded
    def _on_sidebar_click(self, _gesture, _n, x, y, sidebar) -> None:
        if not self._computer_visible:
            return
        picked = sidebar.pick(x, y, Gtk.PickFlags.DEFAULT)
        row = ancestor(picked, lambda w: gtype_name(w) == "NautilusSidebarRow") if picked else None
        uri = None
        if row is not None:
            try:
                uri = row.get_property("uri")
            except TypeError:
                uri = None
        if row is None:
            return  # clique fora de um local (área vazia, título de seção)
        GLib.idle_add(self._leave_computer_towards, uri)

    def _leave_computer_towards(self, uri: str | None) -> bool:
        """Sai do Meu computador indo para `uri` (que o Nautilus está abrindo, ou não)."""
        slot = self.active_slot()
        if slot is None or not self._computer_visible:
            return GLib.SOURCE_REMOVE
        if uri and self._same_as_native(slot, uri):
            # O Nautilus não navega para a pasta que já está aberta: registramos nós.
            self.history(slot).leave_computer_in_place(native.slot_uri(slot))
            self._display_computer(False)
            self._update_history_actions()
        else:
            self._display_computer(False)
            self._expect_navigation(slot)
        return GLib.SOURCE_REMOVE

    @staticmethod
    def _same_as_native(slot, uri: str) -> bool:
        loc = native.slot_location(slot)
        return loc is not None and loc.equal(Gio.File.new_for_uri(uri))

    def _expect_navigation(self, slot) -> None:
        """Escondemos a página e o Nautilus vai navegar; o `notify::location` registra a
        entrada. Se ele não navegar (erro, pasta inacessível), registramos que saímos
        do Meu computador para a pasta que já estava por baixo."""
        if self._leave_source:
            GLib.source_remove(self._leave_source)

        def fallback():
            self._leave_source = 0
            h = self.history(slot)
            if h.on_computer() and not (slot is self.active_slot() and self._computer_visible):
                h.leave_computer_in_place(native.slot_uri(slot))
                self._update_history_actions()
            return GLib.SOURCE_REMOVE

        self._leave_source = GLib.timeout_add(_LEAVE_FALLBACK_MS, fallback)

    # ───────────────────────── Meu computador ─────────────────────────
    def show_computer(self, on: bool = True) -> None:
        """Abrir/fechar o Meu computador por escolha do usuário (barra lateral, atalho,
        menu): registra no histórico da aba e mostra/esconde a página."""
        slot = self.active_slot()
        if slot is None:
            return
        self.hide_tag()
        h = self.history(slot)
        if on:
            h.open_computer()
        elif h.on_computer():
            h.leave_computer_in_place(native.slot_uri(slot))
        self._display_computer(on)
        self._update_history_actions()

    def _display_computer(self, on: bool) -> None:
        """Só a parte visual: troca entre a lista do Nautilus e a página Meu computador."""
        if self.content_stack is None or self.computer is None:
            return
        if on == self._computer_visible:
            return
        self._computer_visible = on
        self.content_stack.set_visible_child_name("computer" if on else self._main_page())
        if on:
            if self.strip is not None:
                self.strip.set_visible(False)
            if self.preview is not None:
                self.preview.set_folder(None)
                self.preview.show_uris([])
            if self.sidebar_list is not None:
                self.sidebar_list.select_row(self.sidebar_list.get_row_at_index(0))
            sidebar = find_by_type_name(self.win, "NautilusSidebar")
            native_lb = find_first(sidebar, lambda w: isinstance(w, Gtk.ListBox)) if sidebar else None
            if native_lb is not None:
                native_lb.unselect_all()
            self.computer.grab_focus()
            self._style_sync()
        else:
            if self.sidebar_list is not None:
                self.sidebar_list.unselect_all()
            slot = self.active_slot()
            if slot is not None:
                self._apply_view(slot)
                self._sync_active_ui(slot)

    def computer_visible(self) -> bool:
        return self._computer_visible

    # ───────────────────────── página de uma etiqueta ─────────────────────────
    def show_tag(self, name: str) -> None:
        """Arquivos com a etiqueta `name` (clique na barra lateral). Fica por cima da
        lista, como o Meu computador, mas não entra no histórico de Voltar/Avançar."""
        if self.content_stack is None or self.tag_page is None:
            return
        self._tag_visible = name
        self.tag_page.show(name)
        self.content_stack.set_visible_child_name("tag")
        if self.strip is not None:
            self.strip.set_visible(False)
        if self.preview is not None:
            self.preview.set_folder(None)
            self.preview.show_uris([])
        if self.sidebar_list is not None:
            self.sidebar_list.unselect_all()
        sidebar = find_by_type_name(self.win, "NautilusSidebar")
        native_lb = find_first(sidebar, lambda w: isinstance(w, Gtk.ListBox)) if sidebar else None
        if native_lb is not None:
            native_lb.unselect_all()
        if self.tag_sidebar is not None:
            self.tag_sidebar.select(name)
        self._style_sync()

    def tag_visible(self) -> str | None:
        return self._tag_visible

    def hide_tag(self) -> None:
        if self._tag_visible is None:
            return
        self._tag_visible = None
        if self.tag_sidebar is not None:
            self.tag_sidebar.select(None)
        if self.content_stack is not None:
            self.content_stack.set_visible_child_name("computer" if self._computer_visible else self._main_page())
        if self._computer_visible:
            if self.sidebar_list is not None:
                self.sidebar_list.select_row(self.sidebar_list.get_row_at_index(0))
        else:
            slot = self.active_slot()
            if slot is not None:
                self._apply_view(slot)
                self._sync_active_ui(slot)
        self._style_sync()

    def leave_tag_and_open(self, uri: str) -> None:
        self.hide_tag()
        if self._computer_visible:
            self.leave_computer_and_open(uri)
        else:
            self.navigate(uri)

    def leave_tag_and_reveal(self, uri: str) -> None:
        self.hide_tag()
        if self._computer_visible:
            self.show_computer(False)
        parent = Gio.File.new_for_uri(uri).get_parent()
        if parent is not None:
            self.reveal(parent.get_uri(), uri)

    def leave_computer_and_open(self, uri: str) -> None:
        """Abrir um item da página (pasta, disco, dispositivo recém-montado)."""
        slot = self.active_slot()
        if slot is None:
            return
        h = self.history(slot)
        if h.on_computer() and self._same_as_native(slot, uri):
            h.leave_computer_in_place(native.slot_uri(slot))
            self._display_computer(False)
            self._update_history_actions()
            return
        self._display_computer(False)
        if h.on_computer():
            self._expect_navigation(slot)
        self.navigate(uri)

    def open_settings(self, page: str = "customize") -> None:
        """Diálogo de personalização, já na página pedida ("customize" ou "about")."""
        if self.computer is not None:
            self.computer.open_settings(page)

    # ───────────────────────── Voltar / Avançar ─────────────────────────
    def history(self, slot) -> History:
        """Histórico da aba (cada aba tem o seu, guardado no próprio slot)."""
        h = getattr(slot, "_vitrine_history", None)
        if h is None:
            h = History()
            slot._vitrine_history = h
            uri = native.slot_uri(slot)
            if uri:
                h.on_location(uri)
        return h

    def _install_actions(self) -> None:
        """Ações da Vitrine nesta janela, com o prefixo "vitrine." (menus, botões ← →,
        atalhos)."""
        group = Gio.SimpleActionGroup()

        def add(name, cb):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", lambda *_a: cb())
            group.add_action(act)

        add("customize", lambda: self.open_settings("customize"))
        add("about", lambda: self.open_settings("about"))
        add("back", lambda: self.go_history(-1))
        add("forward", lambda: self.go_history(+1))
        self.win.insert_action_group("vitrine", group)
        self.actions = group

    def _take_over_history(self) -> None:
        """Faz todas as formas de Voltar/Avançar passarem pelo histórico da Vitrine.

        Nautilus 51: ações slot.back/slot.forward (não existe win.back), atalhos
        Alt+←/→ e teclas Back/Forward, botões 8/9 do mouse num gesto próprio da janela
        e nenhum gesto de deslizar no touchpad. Cada ponto é trocado de forma
        determinística (sem depender da ordem em que o GTK entrega os eventos)."""
        n = self._take_over_buttons()
        self.history_shortcuts_removed = self._take_over_shortcuts()
        log(f"histórico: {n} botões ← →, {self.history_shortcuts_removed} atalhos de teclado")
        self._take_over_mouse()
        self._update_history_actions()

    def _take_over_shortcuts(self) -> int:
        """Alt+←/→ e as teclas Back/Forward. No Nautilus 51 elas não são atalhos do
        aplicativo: ficam num GtkShortcutController do NautilusShortcutManager (o widget
        que envolve todo o conteúdo da janela). Removemos só esses atalhos (na memória,
        nada é salvo; Alt+↑ e os demais ficam) e tratamos as teclas em `_on_key`."""
        removed = 0
        for owner in (find_by_type_name(self.win, "NautilusShortcutManager"), self.win):
            if owner is None:
                continue
            controllers = owner.observe_controllers()
            for i in range(controllers.get_n_items()):
                ctrl = controllers.get_item(i)
                if not isinstance(ctrl, Gtk.ShortcutController):
                    continue
                doomed = []
                for j in range(ctrl.get_n_items()):
                    shortcut = ctrl.get_item(j)
                    trigger = shortcut.get_trigger()
                    if trigger is not None and _is_history_trigger(trigger.to_string()):
                        doomed.append(shortcut)
                for shortcut in doomed:
                    debug(f"histórico: removendo atalho nativo {shortcut.get_trigger().to_string()}")
                    ctrl.remove_shortcut(shortcut)
                    removed += 1
        return removed

    def _take_over_buttons(self) -> int:
        """Botões ← → do cabeçalho e da barra inferior (janela estreita) passam a usar as
        nossas ações. Bônus: o GTK ativa/desativa o botão conforme a ação, então o
        estado deles reflete o histórico combinado sem código extra."""
        n = 0
        for nat, ours in (("slot.back", "vitrine.back"), ("slot.forward", "vitrine.forward")):
            for w in walk(self.win):
                if isinstance(w, Gtk.Button) and w is not self._native_forward_probe \
                        and w.get_action_name() == nat:
                    w.set_action_name(ours)
                    n += 1
        return n

    def _take_over_mouse(self) -> None:
        """Botões laterais do mouse. O Nautilus os trata num GestureClick (todos os
        botões, fase de captura) na própria janela e navega direto, sem passar pela ação.
        Desligamos só esse gesto (fase NONE, nada é salvo) e pomos o nosso no lugar.
        Se não acharmos exatamente um, não mexemos em nada."""
        found = []
        controllers = self.win.observe_controllers()
        for i in range(controllers.get_n_items()):
            c = controllers.get_item(i)
            if (isinstance(c, Gtk.GestureClick) and c.get_button() == 0
                    and c.get_propagation_phase() == Gtk.PropagationPhase.CAPTURE):
                found.append(c)
        if len(found) != 1:
            log(f"histórico: gesto do mouse do Nautilus não identificado ({len(found)}); "
                "botões 8/9 ficam com o Nautilus")
            return
        found[0].set_propagation_phase(Gtk.PropagationPhase.NONE)
        ours = Gtk.GestureClick.new()
        ours.set_button(0)
        ours.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        ours.connect("pressed", self._on_mouse_button)
        self.win.add_controller(ours)
        self._mouse_takeover = True

    @guarded
    def _on_mouse_button(self, gesture, _n, _x, _y) -> None:
        prefs = self._nautilus_prefs
        if not prefs.get_boolean("mouse-use-extra-buttons"):
            return
        button = gesture.get_current_button()
        if button == prefs.get_uint("mouse-back-button"):
            delta = -1
        elif button == prefs.get_uint("mouse-forward-button"):
            delta = +1
        else:
            return
        gesture.set_state(Gtk.EventSequenceState.CLAIMED)
        self.go_history(delta)

    def go_history(self, delta: int) -> None:
        slot = self.active_slot()
        if slot is None:
            return
        h = self.history(slot)
        step = h.back() if delta < 0 else h.forward()
        if step is None:
            return
        self.hide_tag()
        debug(f"histórico {'voltar' if delta < 0 else 'avançar'}: {h.entries} idx={h.idx} "
              f"nativo={step.native}")
        self._display_computer(step.show_computer)
        if step.native:
            self._native_step(slot, step.native)
        self._update_history_actions()

    def _native_step(self, slot, sign: int) -> None:
        slot.activate_action("slot.back" if sign < 0 else "slot.forward", None)
        h = self.history(slot)
        before = h.pending

        def timeout():
            if h.pending == before and h.pending:
                log("histórico: o Nautilus não respondeu ao Voltar/Avançar; desistindo")
                h.cancel_pending()
                self._update_history_actions()
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(_NATIVE_STEP_TIMEOUT_MS, timeout)

    def _update_history_actions(self) -> None:
        if self.actions is None:
            return
        slot = self.active_slot()
        h = self.history(slot) if slot is not None else None
        self.actions.lookup_action("back").set_enabled(bool(h and h.can_back()))
        self.actions.lookup_action("forward").set_enabled(bool(h and h.can_forward()))

    def _check_hidden_native_back(self, slot, uri: str) -> bool:
        """Plano B: depois de uma navegação nova o Avançar nativo fica sempre desativado.
        Se ele estiver ativo, o Nautilus voltou sem passar por nós (ex.: menu de
        histórico do botão ←)."""
        probe = self._native_forward_probe
        if (slot is self.active_slot() and probe is not None and probe.get_sensitive()
                and native.slot_uri(slot) == uri
                and self.history(slot).native_went_back(uri)):
            debug(f"histórico: Voltar nativo detectado, realinhado em {uri}")
            self._update_history_actions()
        return GLib.SOURCE_REMOVE

    def preview_location(self, uri: str | None) -> None:
        if self.preview is None or not self.preview.get_visible():
            return
        # Recentes, Favoritos, Rede e Lixeira não são pastas comuns: sem preview.
        self.preview.show_uris([uri] if uri and native.is_regular_location(uri) else [])

    def toast(self, text: str, button_label: str | None = None, on_button=None,
              timeout: int = 5) -> None:
        overlay = find_first(self.win, lambda w: isinstance(w, Adw.ToastOverlay))
        if overlay is None:
            log(f"aviso (sem área de avisos): {text}")
            return
        t = Adw.Toast(title=GLib.markup_escape_text(text))
        t.set_timeout(timeout)
        if button_label and on_button is not None:
            t.set_button_label(button_label)
            t.connect("button-clicked", lambda *_a: on_button())
        overlay.add_toast(t)
        self.toasts_shown += 1

    def on_new_device(self, key: str, name: str, mount, volume) -> None:
        """Pen drive, HD externo, cartão… acabou de ser conectado."""

        def open_device():
            m = mount or (volume.get_mount() if volume is not None else None)
            if m is not None:
                self.leave_computer_and_open(m.get_default_location().get_uri())
            elif volume is not None:
                self.computer.mount_and_open(volume, key)

        self.toast(f"{name} conectado", "Abrir", open_device, timeout=10)
        if self.computer is not None:
            self.computer.mark_new(key)

    def _inject_buttons(self) -> None:
        box = Gtk.Box(spacing=0)
        box.add_css_class("linked")
        self.btn_columns = Gtk.ToggleButton(icon_name="view-dual-symbolic",
                                            tooltip_text="Colunas (Ctrl+3)")
        self.btn_columns.connect("toggled", self._on_btn_columns)
        self.btn_preview = Gtk.ToggleButton(icon_name="sidebar-show-right-symbolic",
                                            tooltip_text="Pré-visualização (Ctrl+Shift+P)")
        self.btn_preview.set_active(bool(self.cfg.get("preview_visible")))
        self.btn_preview.connect("toggled", self._on_btn_preview)
        box.append(self.btn_columns)
        box.append(self.btn_preview)

        toolbar = find_by_type_name(self.win, "NautilusToolbar")
        controls = find_by_type_name(toolbar, "NautilusViewControls") if toolbar else None
        parent = controls.get_parent() if controls is not None else None
        if isinstance(parent, Gtk.Box):
            parent.insert_child_after(box, controls.get_prev_sibling())
            box.set_margin_end(6)
            return
        header = find_first(toolbar or self.win, lambda w: isinstance(w, Adw.HeaderBar))
        if header is not None:
            header.pack_end(box)
            return
        log("inject: nenhum lugar para os botões na barra; use os atalhos")

    def _install_keys(self) -> None:
        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.win.add_controller(keys)

    @guarded
    def _on_key(self, _ctrl, keyval, _code, state) -> bool:
        mods = state & _MOD_MASK
        # Voltar/Avançar (os atalhos nativos foram removidos em _take_over_shortcuts).
        if mods == Gdk.ModifierType.ALT_MASK and keyval in (Gdk.KEY_Left, Gdk.KEY_Right):
            self.go_history(-1 if keyval == Gdk.KEY_Left else +1)
            return True
        if not mods and keyval in (Gdk.KEY_Back, Gdk.KEY_Forward):
            self.go_history(-1 if keyval == Gdk.KEY_Back else +1)
            return True
        if mods == Gdk.ModifierType.CONTROL_MASK:
            if keyval in (Gdk.KEY_1, Gdk.KEY_2, Gdk.KEY_3, Gdk.KEY_4) and self._computer_visible:
                self.show_computer(False)
            if keyval == Gdk.KEY_4:
                self.user_set_mode("gallery")
                return True
            if keyval in (Gdk.KEY_i, Gdk.KEY_I):
                # Propriedades (o "Obter informações" do Finder); o Nautilus não tem Ctrl+I.
                slot = self.active_slot()
                if slot is not None:
                    slot.activate_action("view.properties", None)
                return True
            if keyval == Gdk.KEY_3:
                self.user_set_mode("columns")
                return True
            if keyval in (Gdk.KEY_1, Gdk.KEY_2):
                # O Nautilus troca lista/grade sozinho; nós só registramos e saímos das colunas.
                mode = "list" if keyval == Gdk.KEY_1 else "grid"
                GLib.idle_add(self._after_native_key, mode)
                return False
        if mods == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK):
            if keyval in (Gdk.KEY_P, Gdk.KEY_p):
                self.set_preview_visible(not self.preview.get_visible())
                return True
            if keyval in (Gdk.KEY_C, Gdk.KEY_c):
                self.show_computer(not self._computer_visible)
                return True
        return False

    def _after_native_key(self, mode: str) -> bool:
        self.user_set_mode(mode)
        return GLib.SOURCE_REMOVE

    # ───────────────────────── slots / abas ─────────────────────────
    def active_slot(self):
        if self.tab_view is None:
            return None
        page = self.tab_view.get_selected_page()
        return page.get_child() if page is not None else None

    def _watch_slot(self, slot) -> None:
        if slot is None or getattr(slot, "_vitrine_watched", False):
            return
        slot._vitrine_watched = True
        slot.connect("notify::location", lambda s, _p: self._on_slot_location(s))

    @guarded
    def _on_tab_switched(self, *_a) -> None:
        slot = self.active_slot()
        if slot is None:
            return
        # O Meu computador pertence à aba: aparece se for o lugar atual desta aba.
        # Os botões ← → podem ter sido religados pelo Nautilus; garantimos de novo.
        self._take_over_buttons()
        self._update_history_actions()
        self.hide_tag()
        if self.history(slot).on_computer():
            self._display_computer(True)
            return
        if self._computer_visible:
            self._display_computer(False)
            return
        self._apply_view(slot)
        self._sync_active_ui(slot)

    @guarded
    def _on_slot_location(self, slot) -> None:
        uri = native.slot_uri(slot)
        if uri is None:
            return
        h = getattr(slot, "_vitrine_history", None)
        if h is None:
            self.history(slot)  # primeira vez: já registra `uri`
            result = "new"
        else:
            result = h.on_location(uri)
        if result == "step":
            # Diferença de mais de um passo: pede o próximo depois que este terminou.
            GLib.idle_add(self._native_step, slot, h.pending)
            return
        self.ext.suppress()
        if slot is self.active_slot():
            self.hide_tag()  # navegou: a página da etiqueta fecha
            if self._computer_visible:
                self._display_computer(False)  # navegou (barra de caminho, busca…)
            self._sync_active_ui(slot)
            self._update_history_actions()
            if result == "new":
                # Dá tempo ao Nautilus de atualizar o estado do Avançar nativo.
                GLib.timeout_add(150, self._check_hidden_native_back, slot, uri)
        GLib.idle_add(self._apply_rule_for_slot, slot, uri, priority=GLib.PRIORITY_LOW)

    def _sync_active_ui(self, slot) -> None:
        loc = native.slot_location(slot)
        uri = loc.get_uri() if loc is not None else None
        regular = native.is_regular_location(uri)
        if self.strip is not None:
            self.strip.set_location(loc if (regular and self.columns_on) else None)
            if not self.columns_on:
                self.strip.set_visible(False)
        if self.preview is not None:
            self.preview.set_folder(uri if regular else None)
            self.preview.show_uris([])
        self._rebind_model_soon()
        if self.gallery_on and self.gallery is not None and regular:
            self.gallery.set_folder(uri)
        self._style_sync()

    def _rebind_model_soon(self) -> None:
        for delay in (0, 250, 900):
            GLib.timeout_add(delay, self._rebind_model)

    @guarded
    def _rebind_model(self) -> bool:
        slot = self.active_slot()
        model = native.find_model(slot) if slot is not None else None
        if self.model_watch.bind(model) and model is not None:
            self._on_native_selection(model)
        self._watch_view_switch(slot)
        return GLib.SOURCE_REMOVE

    def _watch_view_switch(self, slot) -> None:
        """Percebe quando o usuário troca lista/grade pelo botão ou menu do próprio Nautilus."""
        fv = find_by_type_name(slot, "NautilusFilesView") if slot is not None else None
        overlay = find_first(fv, lambda w: isinstance(w, Gtk.Overlay)) if fv is not None else None
        if overlay is None or getattr(overlay, "_vitrine_watched", False):
            return
        overlay._vitrine_watched = True
        overlay.connect("notify::child", self._on_native_view_switched)

    @guarded
    def _on_native_view_switched(self, *_a) -> None:
        self._rebind_model_soon()
        if self.ext.is_suppressed():
            return
        GLib.timeout_add(60, self._record_native_mode)

    def _record_native_mode(self) -> bool:
        slot = self.active_slot()
        mode = native.view_mode(slot) if slot is not None else None
        if mode is None:
            return GLib.SOURCE_REMOVE
        if (self.columns_on or self.gallery_on) and mode == "list":
            return GLib.SOURCE_REMOVE  # coluna usa lista por baixo; nada mudou de fato
        debug(f"usuário trocou a visualização nativa para {mode}")
        self.user_set_mode(mode)
        return GLib.SOURCE_REMOVE

    # ───────────────────────── seleção / pré-visualização ─────────────────────────
    def _on_native_selection(self, _model) -> None:
        if self.preview is None or not self.preview.get_visible() or self._computer_visible:
            return
        self.preview.show_uris(lambda: native.selected_uris(self.model_watch.get()),
                               prefetch=lambda: native.neighbor_uris(self.model_watch.get()))

    def quicklook(self) -> None:
        native.preview_with_sushi(self.active_slot() or self.win)

    def navigate(self, uri: str) -> None:
        native.open_location(self.active_slot(), uri)

    def reveal(self, folder_uri: str, file_uri: str) -> None:
        """Abre `folder_uri` na lista nativa e seleciona `file_uri` quando carregar."""
        slot = self.active_slot()
        if slot is None:
            return
        if native.slot_uri(slot) != Gio.File.new_for_uri(folder_uri).get_uri():
            native.open_location(slot, folder_uri)
        self._reveal_target = (folder_uri, file_uri)
        if self._reveal_source:
            GLib.source_remove(self._reveal_source)
        tries = [0]

        def attempt() -> bool:
            tries[0] += 1
            s = self.active_slot()
            model = native.find_model(s) if s is not None else None
            if model is not None and native.select_uris(model, [file_uri]):
                self._reveal_source = 0
                return GLib.SOURCE_REMOVE
            if tries[0] > 40:
                self._reveal_source = 0
                return GLib.SOURCE_REMOVE
            return GLib.SOURCE_CONTINUE

        self._reveal_source = GLib.timeout_add(100, attempt)

    # ───────────────────────── modos e regras por pasta ─────────────────────────
    @guarded
    def _apply_rule_for_slot(self, slot, uri: str) -> bool:
        if native.slot_uri(slot) != uri:
            return GLib.SOURCE_REMOVE  # já navegou para outro lugar
        if not native.is_regular_location(uri):
            if slot is self.active_slot():
                self._set_columns_visible(False)
                self._set_gallery_visible(False)
            return GLib.SOURCE_REMOVE
        rule, _exact = self.cfg.rule_for(uri)
        current = getattr(slot, "_vitrine_mode", None)
        discover = bool(self.cfg.get("folder_discovery"))
        manual = discovery.manual_choice(uri) if discover else None
        if rule:
            self.apply_mode(slot, rule.get("mode", "list"), rule.get("zoom"))
        elif manual:
            self.apply_mode(slot, *manual)  # escolha manual vence a descoberta
        elif current in ("columns", "gallery"):
            self.apply_mode(slot, current)  # navegar em colunas/galeria continua nelas
        elif discover:
            discovery.discover(uri, float(self.cfg.get("auto_media_ratio")),
                               lambda kind: self._apply_discovered(slot, uri, kind))
        elif self.cfg.get("auto_media_grid"):
            self._detect_media(slot, uri)
        else:
            self.apply_mode(slot, self.cfg.get("default_mode"))
        return GLib.SOURCE_REMOVE

    def apply_mode(self, slot, mode: str, zoom: str | None = None) -> None:
        if mode not in ("list", "grid", "columns", "gallery"):
            mode = "list"
        self.ext.suppress()
        slot._vitrine_mode = mode
        if slot is self.active_slot():
            self._set_columns_visible(mode == "columns")
            self._set_gallery_visible(mode == "gallery")
        native.set_view_mode(slot, "list" if mode in ("columns", "gallery") else mode)
        if mode == "grid":
            self.ext.set_grid_zoom(zoom or self.cfg.get("default_grid_zoom"))
        # Confere depois que o Nautilus terminar de trocar a visualização.
        GLib.timeout_add(350, self._verify_mode, slot, mode)

    def _verify_mode(self, slot, mode: str) -> bool:
        if getattr(slot, "_vitrine_mode", None) != mode:
            return GLib.SOURCE_REMOVE
        want = "list" if mode in ("columns", "gallery") else mode
        if native.view_mode(slot) not in (None, want):
            self.ext.suppress()
            native.set_view_mode(slot, want)
        return GLib.SOURCE_REMOVE

    def user_set_mode(self, mode: str, zoom: str | None = None) -> None:
        """Escolha explícita do usuário na pasta atual: aplica e (se ativado) lembra."""
        slot = self.active_slot()
        uri = native.slot_uri(slot)
        if slot is None:
            return
        if zoom is None and mode == "grid":
            rule, exact = self.cfg.rule_for(uri) if uri else (None, False)
            zoom = ((rule or {}).get("zoom") if exact else None) or self.ext.current_grid_zoom()
        self.apply_mode(slot, mode, zoom)
        if uri and native.is_regular_location(uri):
            discovery.remember_manual(uri, mode, zoom if mode == "grid" else None)
        if self.cfg.get("remember_per_folder") and native.is_regular_location(uri):
            self.cfg.set_rule(uri, mode=mode, zoom=zoom if mode == "grid" else None)

    def record_zoom(self, zoom: str) -> None:
        slot = self.active_slot()
        uri = native.slot_uri(slot)
        if (slot is None or getattr(slot, "_vitrine_mode", None) != "grid"
                or not native.is_regular_location(uri) or not self.cfg.get("remember_per_folder")):
            return
        self.cfg.set_rule(uri, mode="grid", zoom=zoom)

    def _detect_media(self, slot, uri: str) -> None:
        """Pasta com maioria de fotos/vídeos → ícones grandes (sem precisar configurar)."""
        if uri in self._media_cache:
            self._apply_detected(slot, uri, self._media_cache[uri])
            return
        gfile = Gio.File.new_for_uri(uri)

        def on_enum(f, res):
            try:
                en = f.enumerate_children_finish(res)
            except GLib.Error:
                self._apply_detected(slot, uri, False)
                return
            en.next_files_async(_MEDIA_SAMPLE, GLib.PRIORITY_DEFAULT, None, on_files)

        def on_files(en, res):
            try:
                infos = en.next_files_finish(res)
            except GLib.Error:
                infos = []
            en.close_async(GLib.PRIORITY_LOW, None, None)
            files = [i for i in infos if i.get_file_type() == Gio.FileType.REGULAR
                     and not i.get_is_hidden()]
            media = [i for i in files if (i.get_content_type() or "").startswith(("image/", "video/"))]
            ratio = (len(media) / len(files)) if files else 0.0
            is_media = len(media) >= 4 and ratio >= float(self.cfg.get("auto_media_ratio"))
            self._media_cache[uri] = is_media
            self._apply_detected(slot, uri, is_media)

        gfile.enumerate_children_async(
            "standard::type,standard::content-type,standard::is-hidden",
            Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT, None, on_enum)

    @guarded
    def _apply_detected(self, slot, uri: str, is_media: bool) -> None:
        if native.slot_uri(slot) != uri:
            return
        if is_media:
            debug(f"pasta de mídia detectada: {uri}")
            self.apply_mode(slot, "grid", self.cfg.get("auto_media_zoom"))
        else:
            self.apply_mode(slot, self.cfg.get("default_mode"))

    @guarded
    def _apply_discovered(self, slot, uri: str, kind: str | None) -> None:
        """Descoberta automática: mídia → ícones extra grandes; documentos → lista;
        mista/vazia → padrão."""
        if native.slot_uri(slot) != uri or discovery.manual_choice(uri):
            return  # já saiu da pasta, ou o usuário escolheu à mão enquanto analisávamos
        debug(f"descoberta: {uri} -> {kind}")
        if kind == "media":
            self.apply_mode(slot, "grid", self.cfg.get("auto_media_zoom"))
        elif kind == "documents":
            self.apply_mode(slot, "list")
        else:
            self.apply_mode(slot, self.cfg.get("default_mode"))

    # ───────────────────────── colunas / painel ─────────────────────────
    def _apply_view(self, slot) -> None:
        """Visões da Vitrine por cima da lista nativa: Colunas ou Galeria."""
        mode = getattr(slot, "_vitrine_mode", None) if slot is not None else None
        self._set_columns_visible(mode == "columns")
        self._set_gallery_visible(mode == "gallery")

    def _main_page(self) -> str:
        return "gallery" if self.gallery_on else "tabs"

    def _set_gallery_visible(self, on: bool) -> None:
        if self.gallery is None or self.content_stack is None:
            return
        slot = self.active_slot()
        uri = native.slot_uri(slot)
        if on and not native.is_regular_location(uri):
            on = False
        was = self.gallery_on
        self.gallery_on = on
        overlay = self._computer_visible or self._tag_visible is not None
        if on:
            self.gallery.set_folder(uri)
            if not overlay:
                self.content_stack.set_visible_child_name("gallery")
                self.gallery.grab_focus()
            # A Galeria tem o próprio painel de informações.
            if self.preview is not None:
                self.preview.set_visible(False)
        else:
            if self.content_stack.get_visible_child_name() == "gallery":
                self.content_stack.set_visible_child_name("tabs")
            if was and self.preview is not None:
                self.preview.set_visible(bool(self.cfg.get("preview_visible")))
        if was != on:
            self._sync_buttons()

    def _set_columns_visible(self, on: bool) -> None:
        self.columns_on = on
        if self.strip is not None:
            if on:
                slot = self.active_slot()
                loc = native.slot_location(slot)
                ok = loc is not None and native.is_regular_location(loc.get_uri())
                self.strip.set_location(loc if ok else None)
            else:
                self.strip.set_visible(False)
            if self._computer_visible:
                self.strip.set_visible(False)
        self._sync_buttons()

    def set_preview_visible(self, on: bool) -> None:
        self.preview.set_visible(on)
        self.cfg.set("preview_visible", on)
        self._sync_buttons()
        if on:
            self._pos_initialized = False
            self._on_paned_max()
            model = self.model_watch.get()
            self.preview.show_uris(native.selected_uris(model) if model is not None else [])

    def _sync_buttons(self) -> None:
        self._syncing_buttons = True
        try:
            if self.btn_columns is not None:
                self.btn_columns.set_active(self.columns_on)
            if self.btn_preview is not None and self.preview is not None:
                self.btn_preview.set_active(self.preview.get_visible())
        finally:
            self._syncing_buttons = False
        self._style_sync()

    @guarded
    def _on_btn_columns(self, btn) -> None:
        if self._syncing_buttons:
            return
        if btn.get_active():
            self.user_set_mode("columns")
        else:
            self.user_set_mode("list")

    @guarded
    def _on_btn_preview(self, btn) -> None:
        if not self._syncing_buttons:
            self.set_preview_visible(btn.get_active())

    @guarded
    def _on_paned_max(self, *_a) -> None:
        if self._pos_initialized or self.paned is None or not self.preview.get_visible():
            return
        maxpos = self.paned.get_property("max-position")
        if maxpos <= 0:
            return
        width = int(self.cfg.get("preview_width"))
        self._setting_pos = True
        self.paned.set_position(max(200, maxpos - width))
        self._setting_pos = False
        self._pos_initialized = True

    @guarded
    def _on_paned_pos(self, *_a) -> None:
        if self._setting_pos or not self._pos_initialized or not self.preview.get_visible():
            return
        width = self.paned.get_property("max-position") - self.paned.get_position()
        if 180 <= width <= 1200 and width != self.cfg.get("preview_width"):
            self.cfg.set("preview_width", int(width))

    @guarded
    def _on_destroy(self, *_a) -> None:
        if self.style is not None:
            self.style.remove()
        self.model_watch.unbind()
        if self.strip is not None:
            self.strip.teardown()
        self.ext.forget_window(self.win)
__VITRINE_ARQUIVO_17__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/about.css' <<'__VITRINE_ARQUIVO_18__'
/* Card principal da página "Sobre" (vitrine/about.py).
   --card-bg-color do libadwaita já é um pouco mais claro que a janela nos dois temas;
   a borda usa o azul da logo. */
.vitrine-about-hero {
  background-color: var(--card-bg-color);
  border: 1px solid #60a5fa;
  border-radius: 16px;
  padding: 32px 24px 24px 24px;
}
__VITRINE_ARQUIVO_18__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/finder.css' <<'__VITRINE_ARQUIVO_19__'
/* Estilo "Finder (macOS)" da Vitrine.
 *
 * Toda regra começa com window.vitrine-finder: sem essa classe na janela, nada daqui
 * vale (é assim que o "Nautilus padrão" fica limpo). Cores vêm das variáveis do
 * libadwaita (claro/escuro e cor de destaque do sistema).
 *
 * Sem desfoque: o GTK4 não tem backdrop-filter e o GNOME (Mutter) não desfoca janelas
 * de aplicativos. O "vidro" é imitado com tons levemente mais claros/escuros.
 */

/* Os botões da janela (fechar, minimizar, maximizar) ficam no padrão do GNOME. */

/* ── barra de título / ferramentas ── */
window.vitrine-finder .vitrine-finder-header {
  min-height: 52px;
  background-color: var(--view-bg-color);
  box-shadow: none;
}
window.vitrine-finder .vitrine-finder-header > windowhandle > box { padding: 6px 10px; }
window.vitrine-finder .vitrine-finder-title {
  font-weight: 700;
  font-size: 1.15em;
  margin: 0 8px 0 6px;
}

/* cápsulas: grupos de botões arredondados, como no Finder */
window.vitrine-finder .vitrine-capsule {
  border-radius: 99px;
  padding: 3px;
  background-color: color-mix(in srgb, currentColor 5%, transparent);
  box-shadow: 0 0 0 1px color-mix(in srgb, currentColor 7%, transparent),
              0 1px 2px rgb(0 0 0 / 0.06);
}
window.vitrine-finder .vitrine-capsule button,
window.vitrine-finder .vitrine-capsule menubutton > button {
  min-height: 28px; min-width: 34px;
  padding: 0 8px;
  border-radius: 99px;
  background: none;
  box-shadow: none;
}
window.vitrine-finder .vitrine-capsule button:hover,
window.vitrine-finder .vitrine-capsule menubutton > button:hover {
  background-color: color-mix(in srgb, currentColor 8%, transparent);
}
window.vitrine-finder .vitrine-capsule button:checked {
  background-color: color-mix(in srgb, currentColor 13%, transparent);
}
window.vitrine-finder .vitrine-capsule > separator {
  margin: 6px 0;
  background-color: color-mix(in srgb, currentColor 15%, transparent);
}
window.vitrine-finder .vitrine-capsule button:disabled { opacity: 0.35; }

/* campo Pesquisar */
window.vitrine-finder .vitrine-search-pill {
  min-width: 190px; min-height: 30px;
  padding: 0 12px;
  border-radius: 99px;
  background-color: color-mix(in srgb, currentColor 5%, transparent);
  box-shadow: 0 0 0 1px color-mix(in srgb, currentColor 7%, transparent);
}
window.vitrine-finder .vitrine-search-pill label {
  color: color-mix(in srgb, currentColor 55%, transparent);
}

/* ── barra lateral ── */
window.vitrine-finder .vitrine-finder-sidebar,
window.vitrine-finder .vitrine-finder-sidebar-header {
  background-color: color-mix(in srgb, var(--sidebar-bg-color) 85%, var(--view-bg-color));
}
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar {
  background: none;
  padding: 4px 8px;
}
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar > row {
  min-height: 30px;
  margin: 1px 0;
  padding: 0 8px;
  border-radius: 8px;
}
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar > row:selected {
  background-color: color-mix(in srgb, currentColor 11%, transparent);
  color: inherit;
}
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar > row:selected label {
  font-weight: 600;
}
/* ícones na cor de destaque (o ⏏ e os botões da linha ficam neutros) */
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar > row image {
  color: var(--accent-color);
}
window.vitrine-finder .vitrine-finder-sidebar .navigation-sidebar > row button image {
  color: inherit;
}

/* ── conteúdo ── */
window.vitrine-finder .vitrine-computer,
window.vitrine-finder .vitrine-strip { background-color: var(--view-bg-color); }

/* ── seção Etiquetas da barra lateral ── */
window.vitrine-finder .vitrine-tags-section { margin: 10px 0 8px 0; }
window.vitrine-finder .vitrine-tags-header {
  min-height: 24px; padding: 0 16px; border-radius: 6px;
}
window.vitrine-finder .vitrine-sidebar-heading,
window.vitrine-finder .vitrine-tags-header image {
  font-size: 0.85em; font-weight: 700;
  color: color-mix(in srgb, currentColor 50%, transparent);
}
window.vitrine-finder .vitrine-tags-section .navigation-sidebar { padding: 0 8px; background: none; }
window.vitrine-finder .vitrine-tags-section .navigation-sidebar > row {
  min-height: 30px; padding: 0 8px; border-radius: 8px;
}
window.vitrine-finder .vitrine-tags-section .navigation-sidebar > row:selected {
  background-color: color-mix(in srgb, currentColor 11%, transparent); color: inherit;
}
window.vitrine-finder .vitrine-tags-section .navigation-sidebar > row:drop(active) {
  box-shadow: inset 0 0 0 2px var(--accent-bg-color);
}

/* ── visão em grade (a do Finder) ── */
window.vitrine-finder .nautilus-grid-view gridview > child:selected {
  background-color: color-mix(in srgb, currentColor 10%, transparent);
  color: inherit;
}
window.vitrine-finder .nautilus-grid-view gridview > child:selected:hover {
  background-color: color-mix(in srgb, currentColor 14%, transparent);
}
/* bolinhas das etiquetas (emblemas) sem o esmaecido do Nautilus */
window.vitrine-finder .nautilus-view-cell > box.dim-label { opacity: 1; }

/* dimensões das imagens (1ª legenda) em azul, como no Finder. Cor fixa: dentro da
   grade o Nautilus redefine --accent-color (vira cinza ali). */
window.vitrine-finder.vitrine-finder-dimensions .nautilus-grid-view .icon-ui-labels-box > label:nth-child(2) {
  color: #0a64d6;
  opacity: 1;
}
/* tema escuro: a classe vem do Adw.StyleManager (vitrine/finder/__init__.py) */
window.vitrine-finder.vitrine-finder-dark.vitrine-finder-dimensions .nautilus-grid-view .icon-ui-labels-box > label:nth-child(2) {
  color: #5aa9ff;
}

/* ── visão em lista: linhas alternadas suaves ── */
window.vitrine-finder .nautilus-list-view columnview > listview > row:nth-child(even):not(:selected) {
  background-color: color-mix(in srgb, currentColor 3%, transparent);
}

/* miniaturas da página de etiquetas */
window.vitrine-finder .vitrine-thumb { border-radius: 8px; }

/* ── barra de caminho / status (embaixo) ── */
window.vitrine-finder .vitrine-finder-bottombar {
  border-top: 1px solid color-mix(in srgb, currentColor 9%, transparent);
  background-color: var(--view-bg-color);
}
window.vitrine-finder .vitrine-finder-pathbar { padding: 2px 8px; }
window.vitrine-finder .vitrine-finder-pathbar button {
  min-height: 22px; padding: 0 6px; border-radius: 6px; font-size: 0.9em;
}
window.vitrine-finder .vitrine-finder-status {
  font-size: 0.85em; padding: 3px 0 5px 0;
  color: color-mix(in srgb, currentColor 55%, transparent);
}
__VITRINE_ARQUIVO_19__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/nautilus-vitrine-logo.svg' <<'__VITRINE_ARQUIVO_20__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#23232b"/>
      <stop offset="1" stop-color="#0d0d11"/>
    </linearGradient>
    <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#60a5fa"/>
      <stop offset="1" stop-color="#a78bfa"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="240" height="240" rx="56" fill="url(#bg)"/>
  <rect x="8.75" y="8.75" width="238.5" height="238.5" rx="55.25" fill="none" stroke="url(#rim)" stroke-width="1.5"/>
  <path d="M58 98 a18 18 0 0 1 18-18 h30 l14 16 h60 a18 18 0 0 1 18 18 v60 a18 18 0 0 1 -18 18 H76 a18 18 0 0 1 -18-18 Z" fill="none" stroke="url(#glass)" stroke-width="15" stroke-linejoin="round"/>
  <path d="M128 120 Q131.5 136.5 148 140 Q131.5 143.5 128 160 Q124.5 143.5 108 140 Q124.5 136.5 128 120 Z" fill="#ffd166"/>
</svg>
__VITRINE_ARQUIVO_20__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/nautilus-vitrine-mark.svg' <<'__VITRINE_ARQUIVO_21__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#60a5fa"/>
      <stop offset="1" stop-color="#a78bfa"/>
    </linearGradient>
  </defs>
  <path d="M40 90 a22 22 0 0 1 22-22 h38 l18 20 h76 a22 22 0 0 1 22 22 v74 a22 22 0 0 1 -22 22 H62 a22 22 0 0 1 -22-22 Z" fill="none" stroke="url(#glass)" stroke-width="16" stroke-linejoin="round"/>
  <path d="M128 112 Q132.5 133.5 154 138 Q132.5 142.5 128 164 Q123.5 142.5 102 138 Q123.5 133.5 128 112 Z" fill="#ffd166"/>
</svg>
__VITRINE_ARQUIVO_21__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/nautilus-vitrine-symbolic.svg' <<'__VITRINE_ARQUIVO_22__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Ícones simbólicos do GTK são recoloridos forçando `fill`: por isso o contorno
       da pasta é um caminho preenchido (borda externa menos borda interna, evenodd)
       e não um `stroke`. Mesmo desenho do contorno de 1,6 px original. -->
  <path fill="currentColor" fill-rule="evenodd" d="M1.2 4.6 A2.2 2.2 0 0 1 3.4 2.4 H6.2 A0.8 0.8 0 0 1 6.807 2.679 L7.768 3.8 H12.6 A2.2 2.2 0 0 1 14.8 6 V12.4 A2.2 2.2 0 0 1 12.6 14.6 H3.4 A2.2 2.2 0 0 1 1.2 12.4 Z M2.8 4.6 A0.6 0.6 0 0 1 3.4 4 H5.832 L6.793 5.121 A0.8 0.8 0 0 0 7.4 5.4 H12.6 A0.6 0.6 0 0 1 13.2 6 V12.4 A0.6 0.6 0 0 1 12.6 13 H3.4 A0.6 0.6 0 0 1 2.8 12.4 Z"/>
  <path fill="currentColor" d="M8 6.1 Q8.35 8.15 10.4 8.5 Q8.35 8.85 8 10.9 Q7.65 8.85 5.6 8.5 Q7.65 8.15 8 6.1 Z"/>
</svg>
__VITRINE_ARQUIVO_22__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-blue.svg' <<'__VITRINE_ARQUIVO_23__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "blue" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#0a84ff" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_23__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-gray.svg' <<'__VITRINE_ARQUIVO_24__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "gray" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#98989d" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_24__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-green.svg' <<'__VITRINE_ARQUIVO_25__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "green" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#30d158" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_25__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-orange.svg' <<'__VITRINE_ARQUIVO_26__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "orange" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#ff9f0a" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_26__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-purple.svg' <<'__VITRINE_ARQUIVO_27__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "purple" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#bf5af2" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_27__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-red.svg' <<'__VITRINE_ARQUIVO_28__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "red" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#ff453a" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_28__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-symbolic.svg' <<'__VITRINE_ARQUIVO_29__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Etiqueta (botão "Etiquetas" do estilo Finder). Só preenchimento, como todo ícone
       simbólico do GTK: contorno = forma externa menos a interna (evenodd), com o furo. -->
  <path fill="currentColor" fill-rule="evenodd" d="M2.6 1.5 H7.6 a1.5 1.5 0 0 1 1.06 .44 l5.4 5.4 a1.5 1.5 0 0 1 0 2.12 l-4.94 4.94 a1.5 1.5 0 0 1 -2.12 0 l-5.4 -5.4 A1.5 1.5 0 0 1 1.1 7.94 V3 A1.5 1.5 0 0 1 2.6 1.5 Z M2.7 3.1 V7.75 l5.3 5.3 4.95 -4.95 -5.3 -5.3 Z M5 4 a1 1 0 1 1 0 2 a1 1 0 1 1 0 -2 Z"/>
</svg>
__VITRINE_ARQUIVO_29__
mkdir -p "vitrine/assets"
cat > 'vitrine/assets/vitrine-tag-yellow.svg' <<'__VITRINE_ARQUIVO_30__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">
  <!-- Emblema da etiqueta "yellow" (vitrine/tags.py). Anel branco para destacar sobre miniaturas. -->
  <circle cx="8" cy="8" r="6.5" fill="#ffd60a" stroke="#ffffff" stroke-width="1.5"/>
</svg>
__VITRINE_ARQUIVO_30__
mkdir -p "vitrine/finder"
cat > 'vitrine/finder/__init__.py' <<'__VITRINE_ARQUIVO_31__'
"""Estilo "Finder (macOS)": visual e ferramentas inspirados no Finder, por cima do
Nautilus, e removível a qualquer momento.

Como a volta ao "Nautilus padrão" fica limpa:
  * todo o CSS é de um único arquivo (assets/finder.css), com regras presas à classe
    `.vitrine-finder` da janela, e o provedor sai do display quando nenhuma janela usa;
  * cada mudança feita na janela (widget acrescentado, widget escondido, propriedade
    trocada, sinal conectado) registra a sua própria desfeita numa pilha (`_undo`);
    `remove()` desfaz tudo na ordem inversa.
Se algo falhar ao aplicar, desfazemos o que já foi feito e a janela fica no padrão.
"""

from __future__ import annotations

import os

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from ..util import ASSETS, ancestor, find_by_type_name, find_first, gtype_name, log, walk
from ..tagui import TagSidebar
from .bottombar import FinderBottomBar
from .toolbar import FinderToolbar

DIMENSIONS = "vitrine_dimensions"
TAGS_COLUMN = "Vitrine::tags"

_css = {"provider": None, "users": 0}


def _css_acquire() -> None:
    display = Gdk.Display.get_default()
    if display is None:
        return
    if _css["provider"] is None:
        provider = Gtk.CssProvider()
        provider.load_from_path(os.path.join(ASSETS, "finder.css"))
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        _css["provider"] = provider
    _css["users"] += 1


def _css_release() -> None:
    _css["users"] = max(0, _css["users"] - 1)
    display = Gdk.Display.get_default()
    if _css["users"] == 0 and _css["provider"] is not None and display is not None:
        Gtk.StyleContext.remove_provider_for_display(display, _css["provider"])
        _css["provider"] = None


def strip_dimensions_caption() -> None:
    """Tira das preferências do Nautilus o que o estilo Finder pôs (legenda das
    dimensões), inclusive sobras de uma sessão que travou.

    A coluna "Etiquetas" da lista NÃO é ligada automaticamente: mudar
    org.gnome.nautilus.list-view default-visible-columns com a janela aberta derruba o
    Nautilus 51.1 (assertion em nautilus_file_is_in_trash). O usuário a liga em
    "Colunas visíveis"; aqui só limpamos se algo a tiver posto nessa preferência."""
    try:
        settings = Gio.Settings.new("org.gnome.nautilus.icon-view")
        captions = settings.get_strv("captions")
        if DIMENSIONS in captions:
            settings.set_strv("captions", ([c for c in captions if c != DIMENSIONS]
                                           + ["none", "none", "none"])[:3])
        lists = Gio.Settings.new("org.gnome.nautilus.list-view")
        columns = lists.get_strv("default-visible-columns")
        if TAGS_COLUMN in columns:
            lists.set_strv("default-visible-columns", [c for c in columns if c != TAGS_COLUMN])
    except Exception as err:  # noqa: BLE001
        log(f"estilo Finder: preferências do Nautilus ({err!r})")


def css_loaded() -> bool:
    return _css["provider"] is not None


class FinderStyle:
    """Aplica/remove o estilo Finder numa janela (um por WindowController)."""

    def __init__(self, ctl) -> None:
        self.ctl = ctl
        self.win = ctl.win
        self.active = False
        self._undo: list = []
        self.toolbar: FinderToolbar | None = None
        self.header: Adw.HeaderBar | None = None
        self.sidebar_header: Adw.HeaderBar | None = None
        self.split: Adw.OverlaySplitView | None = None
        self.bottombar: FinderBottomBar | None = None

    # ── registro de desfeitas ──
    def _later(self, fn) -> None:
        self._undo.append(fn)

    def _class(self, widget, name: str) -> None:
        if widget is None or widget.has_css_class(name):
            return
        widget.add_css_class(name)
        self._later(lambda: widget.remove_css_class(name))

    def _connect(self, obj, signal: str, cb) -> None:
        hid = obj.connect(signal, cb)
        self._later(lambda: obj.disconnect(hid))

    def _prop(self, obj, name: str, value) -> None:
        old = obj.get_property(name)
        obj.set_property(name, value)
        self._later(lambda: obj.set_property(name, old))

    def _hide(self, widget, restore=None) -> None:
        """Esconde um widget do Nautilus e o mantém escondido, mesmo que o Nautilus
        tente mostrá-lo de novo (alguns têm `visible` ligado a uma propriedade).
        `restore()` diz qual deve ser a visibilidade ao desfazer."""
        if widget is None:
            return
        was = widget.get_visible()
        widget.set_visible(False)

        def keep(w, _p):
            if self.active and w.get_visible():
                w.set_visible(False)

        hid = widget.connect("notify::visible", keep)

        def undo():
            widget.disconnect(hid)
            widget.set_visible(restore() if restore is not None else was)

        self._later(undo)

    # ── aplicar / remover ──
    def apply(self) -> bool:
        if self.active:
            return True
        try:
            self.active = True
            _css_acquire()
            self._later(_css_release)
            self._class(self.win, "vitrine-finder")
            self._follow_dark()
            self._find_bars()
            self._sidebar()
            self._tags_section()
            self._toolbar()
            self._captions()
            self._bottom()
            self.sync()
            log("estilo Finder aplicado")
            return True
        except Exception as err:  # noqa: BLE001
            log(f"estilo Finder: falhou ao aplicar ({err!r}); voltando ao padrão")
            self.remove()
            return False

    def remove(self) -> None:
        strip_dimensions_caption()  # sobra de uma sessão que travou com o Finder ativo
        was_active = self.active
        self.active = False
        while self._undo:
            fn = self._undo.pop()
            try:
                fn()
            except Exception as err:  # noqa: BLE001
                log(f"estilo Finder: falha ao desfazer ({err!r})")
        self.toolbar = None
        if was_active:
            log("estilo Finder removido (Nautilus padrão)")

    # ── partes ──
    def _follow_dark(self) -> None:
        """Classe vitrine-finder-dark quando o tema está escuro (algumas cores do Finder
        são fixas, e o @media prefers-color-scheme não chega a todos os widgets)."""
        manager = Adw.StyleManager.get_default()

        def update(*_a):
            if manager.get_dark():
                self.win.add_css_class("vitrine-finder-dark")
            else:
                self.win.remove_css_class("vitrine-finder-dark")

        update()
        self._connect(manager, "notify::dark", update)
        self._later(lambda: self.win.remove_css_class("vitrine-finder-dark"))

    def _find_bars(self) -> None:
        """Localiza as barras de título do Nautilus. Os botões da janela (fechar,
        minimizar, maximizar) não são tocados: ficam como o GNOME desenha."""
        self.split = find_first(self.win, lambda w: isinstance(w, Adw.OverlaySplitView))
        toolbar = find_by_type_name(self.win, "NautilusToolbar")
        self.header = find_first(toolbar, lambda w: isinstance(w, Adw.HeaderBar)) if toolbar else None
        sidebar = self.split.get_sidebar() if self.split is not None else None
        self.sidebar_header = find_first(sidebar, lambda w: isinstance(w, Adw.HeaderBar)) \
            if sidebar is not None else None
        if self.header is None or self.sidebar_header is None:
            raise RuntimeError("barras de título do Nautilus não encontradas")
        self._class(self.header, "vitrine-finder-header")
        self._class(self.sidebar_header, "vitrine-finder-sidebar-header")

    def _sidebar(self) -> None:
        """Cabeçalho da barra lateral sem o título "Arquivos" e sem a lupa (a pesquisa
        fica na barra de ferramentas); os botões da janela continuam os do GNOME."""
        bar = self.sidebar_header
        title = bar.get_title_widget()
        if title is not None:
            self._hide(title)
        for w in walk(bar):
            if isinstance(w, Gtk.ToggleButton) and w.get_action_name() == "slot.search-global":
                self._hide(w)  # "Buscar em todos os lugares" fica no menu ⋯ e na pesquisa
        sidebar = find_by_type_name(self.win, "NautilusSidebar")
        pane = ancestor(sidebar, lambda w: isinstance(w, Adw.ToolbarView)) if sidebar else None
        self._class(pane, "vitrine-finder-sidebar")

    def _tags_section(self) -> None:
        """Seção Etiquetas logo abaixo dos locais nativos, rolando junto com eles.

        A lista nativa fica num Gtk.Viewport dentro do Gtk.ScrolledWindow da barra
        lateral: pomos uma caixa no lugar dela com [lista nativa, Etiquetas] e, ao
        desfazer, devolvemos a lista ao Viewport. Se a estrutura for outra, a seção vai
        para o rodapé da barra lateral."""
        if not self.ctl.cfg.get("tags_in_sidebar"):
            return
        section = TagSidebar(self.ctl)
        self.ctl.tag_sidebar = section
        store = self.ctl.ext.tags

        def forget():
            store.off_change(section.listener)
            self.ctl.tag_sidebar = None

        self._later(forget)
        sidebar = find_by_type_name(self.win, "NautilusSidebar")
        viewport = find_first(sidebar, lambda w: isinstance(w, Gtk.Viewport)) if sidebar else None
        listbox = viewport.get_child() if viewport is not None else None
        if isinstance(listbox, Gtk.ListBox):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            viewport.set_child(None)   # `listbox` continua vivo: a variável Python o segura
            box.append(listbox)
            box.append(section)
            viewport.set_child(box)

            def undo():
                viewport.set_child(None)
                box.remove(listbox)
                viewport.set_child(listbox)

            self._later(undo)
            return
        pane = ancestor(sidebar, lambda w: isinstance(w, Adw.ToolbarView)) if sidebar else None
        if pane is None:
            raise RuntimeError("barra lateral sem lugar para as Etiquetas")
        pane.add_bottom_bar(section)
        self._later(lambda: pane.remove(section))

    def _bottom(self) -> None:
        """Barra de caminho e barra de status embaixo do conteúdo (opcionais)."""
        content = ancestor(self.ctl.paned, lambda w: isinstance(w, Adw.ToolbarView)) \
            if self.ctl.paned is not None else None
        if content is None:
            return
        bar = FinderBottomBar(self.ctl)
        content.add_bottom_bar(bar)
        self.bottombar = bar

        def undo():
            content.remove(bar)
            self.bottombar = None

        self._later(undo)

    def _captions(self) -> None:
        """Dimensões das imagens abaixo do nome na visão em grade (como no Finder).
        A legenda é uma preferência do próprio Nautilus: guardamos e devolvemos."""
        if not self.ctl.cfg.get("image_dimensions"):
            return
        settings = Gio.Settings.new("org.gnome.nautilus.icon-view")
        captions = [c for c in settings.get_strv("captions") if c != DIMENSIONS]
        captions = (captions + ["none", "none", "none"])[:3]
        settings.set_strv("captions", [DIMENSIONS] + captions[:2])
        self._class(self.win, "vitrine-finder-dimensions")

        def undo():
            current = [c for c in settings.get_strv("captions") if c != DIMENSIONS]
            if current == captions[:2]:
                settings.set_strv("captions", captions)   # ninguém mexeu: volta igual
            else:  # o usuário mudou as legendas: só tiramos a nossa
                settings.set_strv("captions", (current + ["none", "none", "none"])[:3])

        self._later(undo)

    def _toolbar(self) -> None:
        header = self.header
        toolbar = find_by_type_name(self.win, "NautilusToolbar")
        # ← → do Nautilus (cabeçalho) e controles de visualização nativos: o Finder
        # tem os seus. O `visible` deles segue propriedades do NautilusToolbar.
        stack = find_first(header, lambda w: isinstance(w, Gtk.Stack)
                           and find_by_type_name(w, "NautilusHistoryControls") is not None)
        self._hide(stack, lambda: bool(toolbar.get_property("show-history-controls")))
        controls = find_by_type_name(header, "NautilusViewControls")
        self._hide(controls, lambda: bool(toolbar.get_property("show-view-controls")))
        # Botões Colunas/Pré-visualização da Vitrine: viram parte da barra do Finder.
        if self.ctl.btn_columns is not None:
            self._hide(self.ctl.btn_columns.get_parent())
        # Barra de caminho: no Finder, só o nome da pasta (a barra volta ao editar o
        # local com Ctrl+L ou ao pesquisar).
        switcher = find_first(header, lambda w: isinstance(w, Gtk.Stack)
                              and w.get_child_by_name("pathbar") is not None)
        search_toggle = None
        for w in walk(header):
            if isinstance(w, Gtk.ToggleButton) and w.get_action_name() == "slot.search-visible":
                search_toggle = w
        if search_toggle is not None:
            self._hide(search_toggle.get_parent() if isinstance(search_toggle.get_parent(), Gtk.Stack)
                       else search_toggle)

        self.toolbar = FinderToolbar(self.ctl, switcher)
        self.toolbar.attach(header, self._later)
        if switcher is not None:
            self._connect(switcher, "notify::visible-child-name",
                          lambda *_a: self.toolbar and self.toolbar.sync_title())
            self._later(lambda s=switcher: s.set_visible(True))

    # ── estado ──
    def sync(self) -> None:
        """Chamado pelo WindowController quando muda pasta, aba, modo ou Meu computador."""
        if self.active and self.toolbar is not None:
            self.toolbar.sync()
        if self.active and self.bottombar is not None:
            self.bottombar.update()
            # a lista nativa termina de carregar depois: confere a contagem de novo
            GLib.timeout_add(900, lambda: (self.bottombar and self.bottombar.update(), False)[1])


def describe(win) -> str:
    """Resumo para o log/autoteste."""
    return (f"classe={win.has_css_class('vitrine-finder')} css={css_loaded()} "
            f"janela={gtype_name(win)}")

__VITRINE_ARQUIVO_31__
mkdir -p "vitrine/finder"
cat > 'vitrine/finder/bottombar.py' <<'__VITRINE_ARQUIVO_32__'
"""Barras de baixo do estilo Finder (opcionais, desligadas de fábrica como no macOS):

  * barra de caminho: a hierarquia da pasta atual, clicável
    (Pasta pessoal › Projetos › nautilus-vitrine);
  * barra de status: quantidade de itens e espaço disponível no disco.
"""

from __future__ import annotations

import gettext
import os

from gi.repository import Gio, GLib, Gtk, Pango

from .. import native, util
from ..util import guarded


def _root_label() -> str:
    text = gettext.dgettext("gtk40", "Computer")
    return "Computador" if text == "Computer" else text


class FinderBottomBar(Gtk.Box):
    def __init__(self, ctl) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.add_css_class("vitrine-finder-bottombar")
        self.ctl = ctl
        self.path_row = Gtk.Box(spacing=2)
        self.path_row.add_css_class("vitrine-finder-pathbar")
        self.path_scroll = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER,
                                              hscrollbar_policy=Gtk.PolicyType.EXTERNAL,
                                              child=self.path_row)
        self.status = Gtk.Label(ellipsize=Pango.EllipsizeMode.END)
        self.status.add_css_class("vitrine-finder-status")
        self.append(self.path_scroll)
        self.append(self.status)
        self._cancel = Gio.Cancellable()
        self._free: str | None = None
        self._free_for: str | None = None
        self.apply_settings()

    def apply_settings(self) -> None:
        cfg = self.ctl.cfg
        self.path_scroll.set_visible(bool(cfg.get("path_bar")))
        self.status.set_visible(bool(cfg.get("status_bar")))
        self.set_visible(bool(cfg.get("path_bar")) or bool(cfg.get("status_bar")))

    # ── atualização ──
    def update(self) -> None:
        if not self.get_visible():
            return
        slot = self.ctl.active_slot()
        uri = None if (self.ctl.computer_visible() or self.ctl.tag_visible()) else native.slot_uri(slot)
        self._path(uri)
        self._status(uri, slot)

    def _path(self, uri: str | None) -> None:
        child = self.path_row.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.path_row.remove(child)
            child = nxt
        crumbs = self.crumbs(uri)
        for i, (label, icon, target) in enumerate(crumbs):
            if i:
                sep = Gtk.Image.new_from_icon_name("go-next-symbolic")
                sep.add_css_class("dim-label")
                sep.set_pixel_size(10)
                self.path_row.append(sep)
            content = Gtk.Box(spacing=4)
            if icon:
                content.append(Gtk.Image.new_from_icon_name(icon))
            content.append(Gtk.Label(label=label))
            btn = Gtk.Button(child=content)
            btn.add_css_class("flat")
            if target:
                btn.connect("clicked", lambda *_a, t=target: self.ctl.navigate(t))
            else:
                btn.set_sensitive(False)
            self.path_row.append(btn)

    def crumbs(self, uri: str | None) -> list[tuple[str, str | None, str | None]]:
        """(rótulo, ícone, destino) de cada parte do caminho."""
        if self.ctl.tag_visible():
            return [(self.ctl.tag_visible(), "vitrine-tag-symbolic", None)]
        if self.ctl.computer_visible() or not uri:
            return [("Meu computador", "computer-symbolic", None)]
        gfile = Gio.File.new_for_uri(uri)
        if gfile.get_path() is None:  # Lixeira, Recentes, Rede…
            title = self.ctl.style.toolbar.title.get_label() if (
                self.ctl.style and self.ctl.style.toolbar) else uri
            return [(title, None, None)]
        home = Gio.File.new_for_path(os.path.expanduser("~"))
        parts = []
        f = gfile
        while f is not None:
            if f.equal(home):
                parts.append((gettext.dgettext("nautilus", "Home"), "user-home-symbolic", f.get_uri()))
                break
            if f.get_parent() is None:
                parts.append((_root_label(), "drive-harddisk-symbolic", f.get_uri()))
                break
            parts.append((f.get_basename(), None, f.get_uri()))
            f = f.get_parent()
        return list(reversed(parts))

    def _status(self, uri: str | None, slot) -> None:
        if uri is None:
            self.status.set_label("")
            return
        if self.ctl.gallery_on and self.ctl.gallery is not None:
            count = len(self.ctl.gallery.items)
        else:
            model = native.find_model(slot)
            count = model.get_n_items() if model is not None else 0
        text = f"{count} {'item' if count == 1 else 'itens'}"
        if self._free is not None and self._free_for == uri:
            text += f", {self._free} disponíveis"
        self.status.set_label(text)
        if self._free_for != uri:
            self._query_free(uri)

    def _query_free(self, uri: str) -> None:
        self._cancel.cancel()
        self._cancel = Gio.Cancellable()
        self._free_for = uri
        self._free = None

        @guarded
        def done(f, res):
            try:
                info = f.query_filesystem_info_finish(res)
            except GLib.Error:
                return
            if info.has_attribute("filesystem::free") and self._free_for == uri:
                self._free = util.human_size(info.get_attribute_uint64("filesystem::free"))
                self.update()

        Gio.File.new_for_uri(uri).query_filesystem_info_async(
            "filesystem::free", GLib.PRIORITY_LOW, self._cancel, done)
__VITRINE_ARQUIVO_32__
mkdir -p "vitrine/finder"
cat > 'vitrine/finder/toolbar.py' <<'__VITRINE_ARQUIVO_33__'
"""Barra de ferramentas do estilo Finder, montada dentro do AdwHeaderBar do Nautilus:

    [← | →]  Título da pasta          [▦ ☰ ▥] [⇅ ⌄] [⇪] [⋯] [🔍 Pesquisar]

Os botões chamam as ações do próprio Nautilus (view.sort, view.new-folder,
view.properties…) sempre que existem: nada de arquivo é reimplementado aqui. Os rótulos
vêm da tradução oficial do Nautilus (gettext, domínio "nautilus"), para seguir os nomes
do GNOME no idioma do sistema.
"""

from __future__ import annotations

import gettext

from gi.repository import Gio, GLib, Gtk, Pango

from .. import native, util
from ..tagui import TagMenuButton
from ..util import guarded, log


def nt(msgid: str, fallback: str | None = None) -> str:
    """Texto da tradução do Nautilus, sem o sublinhado de atalho. Se o Nautilus não
    tiver esse texto traduzido, usa `fallback` (em português)."""
    text = gettext.dgettext("nautilus", msgid)
    if text == msgid and fallback is not None:
        text = fallback
    return text.replace("_", "")


# (rótulo, atributo, invertido) para a ação nativa view.sort, que recebe "(sb)".
SORTS = (
    (lambda: "A-Z", "name", False),
    (lambda: "Z-A", "name", True),
    (lambda: nt("Last Modified", "Última modificação"), "date_modified", True),
    (lambda: nt("First Modified", "Primeira modificação"), "date_modified", False),
    (lambda: nt("Size", "Tamanho"), "size", True),
    (lambda: nt("Type", "Tipo"), "type", False),
)

VIEWS = (
    ("grid", "view-grid-symbolic", lambda: nt("Grid View", "Ícones"), "Ctrl+2"),
    ("list", "view-list-symbolic", lambda: nt("List View", "Lista"), "Ctrl+1"),
    ("columns", "view-dual-symbolic", lambda: "Colunas", "Ctrl+3"),
    ("gallery", "view-paged-symbolic", lambda: "Galeria", "Ctrl+4"),
)


def _capsule(*children) -> Gtk.Box:
    box = Gtk.Box(valign=Gtk.Align.CENTER)
    box.add_css_class("vitrine-capsule")
    for c in children:
        box.append(c)
    return box


def _menu_button(icon: str, tooltip: str, menu: Gio.Menu, *, arrow: bool = False) -> Gtk.MenuButton:
    btn = Gtk.MenuButton(menu_model=menu, tooltip_text=tooltip, valign=Gtk.Align.CENTER)
    if arrow:
        content = Gtk.Box(spacing=4)
        content.append(Gtk.Image.new_from_icon_name(icon))
        content.append(Gtk.Image.new_from_icon_name("pan-down-symbolic"))
        btn.set_child(content)
    else:
        btn.set_icon_name(icon)
    btn.add_css_class("flat")
    return btn


class FinderToolbar:
    def __init__(self, ctl, switcher: Gtk.Stack | None) -> None:
        self.ctl = ctl
        self.switcher = switcher
        self.view_buttons: dict[str, Gtk.ToggleButton] = {}
        self._syncing = False
        self.title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=28,
                               valign=Gtk.Align.CENTER)
        self.title.add_css_class("vitrine-finder-title")
        self.actions = Gio.SimpleActionGroup()

    # ── montagem ──
    def attach(self, header, later) -> None:
        win = self.ctl.win
        self._install_actions()
        win.insert_action_group("vfinder", self.actions)
        later(lambda: win.insert_action_group("vfinder", None))

        start = [self._nav(), self.title]
        end = [self._search(), self._more(), _capsule(TagMenuButton(self.ctl)), self._share(),
               self._sort(), self._views()]
        for w in start:
            header.pack_start(w)
            later(lambda w=w: header.remove(w))
        for w in end:  # pack_end: o primeiro fica mais à direita
            header.pack_end(w)
            later(lambda w=w: header.remove(w))

    def _nav(self) -> Gtk.Widget:
        back = Gtk.Button(icon_name="go-previous-symbolic", action_name="vitrine.back",
                          tooltip_text=nt("Back", "Voltar"))
        fwd = Gtk.Button(icon_name="go-next-symbolic", action_name="vitrine.forward",
                         tooltip_text=nt("Forward", "Avançar"))
        box = _capsule(back, Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), fwd)
        box.add_css_class("vitrine-nav")
        return box

    def _views(self) -> Gtk.Widget:
        box = _capsule()
        box.add_css_class("vitrine-views")
        first = None
        for mode, icon, label, accel in VIEWS:
            btn = Gtk.ToggleButton(icon_name=icon, tooltip_text=f"{label()} ({accel})")
            if first is None:
                first = btn
            else:
                btn.set_group(first)
            btn.connect("toggled", self._on_view_toggled, mode)
            self.view_buttons[mode] = btn
            box.append(btn)
        return box

    def _sort(self) -> Gtk.Widget:
        menu = Gio.Menu()
        section = Gio.Menu()
        for label, attr, reverse in SORTS:
            item = Gio.MenuItem.new(label(), None)
            item.set_action_and_target_value("view.sort", GLib.Variant("(sb)", (attr, reverse)))
            section.append_item(item)
        menu.append_section("Ordenar por", section)
        from ..gallery import GROUPS
        groups = Gio.Menu()
        for value, label in GROUPS:
            item = Gio.MenuItem.new(label, None)
            item.set_action_and_target_value("vfinder.group", GLib.Variant("s", value))
            groups.append_item(item)
        menu.append_section("Agrupar na Galeria", groups)
        return _capsule(_menu_button("view-sort-descending-symbolic", "Ordenar e agrupar", menu,
                                     arrow=True))

    def _share(self) -> Gtk.Widget:
        menu = Gio.Menu()
        menu.append(nt("_Copy Location", "Copiar local"), "vfinder.copy-location")
        menu.append("Enviar por e-mail…", "view.send-email")
        if GLib.find_program_in_path("bluetooth-sendto"):
            menu.append("Enviar por Bluetooth…", "vfinder.send-bluetooth")
        if GLib.find_program_in_path("gnome-control-center"):
            menu.append("Compartilhamento na rede…", "vfinder.sharing-settings")
        return _capsule(_menu_button("send-to-symbolic", "Compartilhar", menu))

    def _more(self) -> Gtk.Widget:
        menu = Gio.Menu()
        new = Gio.Menu()
        new.append(nt("New _Folder…", "Nova pasta…"), "view.new-folder")
        new.append("Novo documento vazio", "view.template-empty")
        menu.append_section(None, new)
        files = Gio.Menu()
        files.append(nt("P_roperties", "Propriedades"), "view.properties")
        files.append(nt("Rena_me…", "Renomear…"), "view.rename")
        files.append(nt("C_ompress…", "Comprimir…"), "view.compress")
        files.append(nt("_Copy", "Copiar"), "view.copy")
        files.append(nt("_Paste", "Colar"), "view.paste")
        files.append(nt("Mo_ve to Trash", "Mover para a lixeira"), "view.move-to-trash")
        menu.append_section(None, files)
        view = Gio.Menu()
        view.append(nt("Show _Hidden Files", "Mostrar arquivos ocultos"), "view.show-hidden-files")
        view.append("Painel de pré-visualização", "vfinder.preview")
        view.append(nt("Search Everywhere", "Pesquisar em todos os lugares"), "slot.search-global")
        menu.append_section(None, view)
        btn = _menu_button("view-more-horizontal-symbolic", "Mais ações", menu)
        return _capsule(btn)

    def _search(self) -> Gtk.Widget:
        content = Gtk.Box(spacing=6)
        content.append(Gtk.Image.new_from_icon_name("system-search-symbolic"))
        label = Gtk.Label(label="Pesquisar", xalign=0, hexpand=True)
        content.append(label)
        btn = Gtk.Button(child=content, valign=Gtk.Align.CENTER,
                         tooltip_text=f"{nt('Search Current Folder', 'Pesquisar pasta atual')} (Ctrl+F)")
        btn.add_css_class("vitrine-search-pill")
        btn.connect("clicked", lambda *_a: self._start_search())
        return btn

    # ── ações próprias ──
    def _install_actions(self) -> None:
        def add(name, cb):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", lambda *_a: guarded(cb)())
            self.actions.add_action(act)

        add("copy-location", self._copy_location)
        add("send-bluetooth", self._send_bluetooth)
        add("sharing-settings", lambda: _spawn(["gnome-control-center", "sharing"]))
        preview = Gio.SimpleAction.new_stateful(
            "preview", None, GLib.Variant("b", bool(self.ctl.cfg.get("preview_visible"))))
        preview.connect("activate", lambda a, _p: self.ctl.set_preview_visible(
            not self.ctl.preview.get_visible()))
        self.actions.add_action(preview)
        group = Gio.SimpleAction.new_stateful(
            "group", GLib.VariantType.new("s"),
            GLib.Variant("s", self.ctl.cfg.get("gallery_group_by") or "date"))
        group.connect("activate", self._on_group)
        self.actions.add_action(group)

    @guarded
    def _on_group(self, action, value) -> None:
        action.set_state(value)
        self.ctl.cfg.set("gallery_group_by", value.get_string())
        if self.ctl.gallery is not None:
            self.ctl.gallery.reload()
        if not self.ctl.gallery_on:
            self.ctl.user_set_mode("gallery")  # agrupar só existe na Galeria

    def _selection_or_folder(self) -> list[str]:
        slot = self.ctl.active_slot()
        uris = native.selected_uris(self.ctl.model_watch.get())
        if not uris and slot is not None:
            uri = native.slot_uri(slot)
            uris = [uri] if uri else []
        return uris

    def _copy_location(self) -> None:
        uris = self._selection_or_folder()
        paths = [Gio.File.new_for_uri(u).get_path() or u for u in uris]
        if paths:
            util.copy_text_to_clipboard(self.ctl.win, "\n".join(paths))

    def _send_bluetooth(self) -> None:
        paths = [p for p in (Gio.File.new_for_uri(u).get_path()
                             for u in native.selected_uris(self.ctl.model_watch.get())) if p]
        if not paths:
            self.ctl.toast("Selecione os arquivos para enviar por Bluetooth")
            return
        _spawn(["bluetooth-sendto", *paths])

    def _start_search(self) -> None:
        slot = self.ctl.active_slot()
        if slot is not None:
            slot.activate_action("slot.search-visible", None)

    # ── estado ──
    @guarded
    def _on_view_toggled(self, btn, mode: str) -> None:
        if self._syncing or not btn.get_active():
            return
        if self.ctl.computer_visible():
            self.ctl.show_computer(False)
        self.ctl.user_set_mode(mode)

    def sync(self) -> None:
        self._syncing = True
        try:
            computer = self.ctl.computer_visible() or bool(self.ctl.tag_visible())
            slot = self.ctl.active_slot()
            # O modo pedido pela Vitrine vale antes do Nautilus terminar de trocar a visão.
            mode = "gallery" if self.ctl.gallery_on else "columns" if self.ctl.columns_on else (
                getattr(slot, "_vitrine_mode", None) or native.view_mode(slot) if slot else None)
            for name, btn in self.view_buttons.items():
                btn.set_active(name == mode and not computer)
            act = self.actions.lookup_action("preview")
            if act is not None and self.ctl.preview is not None:
                act.set_state(GLib.Variant("b", self.ctl.preview.get_visible()))
        finally:
            self._syncing = False
        self.sync_title()

    def sync_title(self) -> None:
        page = self.switcher.get_visible_child_name() if self.switcher is not None else "pathbar"
        editing = page in ("location", "search")
        if self.switcher is not None:
            self.switcher.set_visible(editing)
        self.title.set_visible(not editing)
        self.title.set_label(self._title_text())

    def _title_text(self) -> str:
        if self.ctl.tag_visible():
            return self.ctl.tag_visible()
        if self.ctl.computer_visible():
            return "Meu computador"
        slot = self.ctl.active_slot()
        if slot is None:
            return ""
        try:
            title = slot.get_property("title")
        except TypeError:
            title = None
        if title:
            return title
        uri = native.slot_uri(slot)
        return Gio.File.new_for_uri(uri).get_basename() if uri else ""


def _spawn(argv: list[str]) -> None:
    try:
        Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE)
    except GLib.Error as err:
        log(f"não foi possível abrir {argv[0]}: {err.message}")
__VITRINE_ARQUIVO_33__
mkdir -p "vitrine/schemas"
cat > 'vitrine/schemas/io.github.bispov19.NautilusVitrine.gschema.xml' <<'__VITRINE_ARQUIVO_34__'
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Preferências da Vitrine para Nautilus.

  O schema fica dentro da própria extensão e é carregado com
  Gio.SettingsSchemaSource.new_from_directory (não precisa de root). Para usar no
  terminal, aponte para esta pasta:

    gsettings &#45;&#45;schemadir ~/.local/share/nautilus-python/extensions/vitrine/schemas \
      set io.github.bispov19.NautilusVitrine window-style nautilus

  As regras por pasta continuam em ~/.config/nautilus-vitrine/folders.json (são dados,
  não preferências).
-->
<schemalist gettext-domain="nautilus-vitrine">
  <enum id="io.github.bispov19.NautilusVitrine.WindowStyle">
    <value nick="finder" value="0"/>
    <value nick="nautilus" value="1"/>
  </enum>

  <schema id="io.github.bispov19.NautilusVitrine" path="/io/github/bispov19/NautilusVitrine/">
    <key name="window-style" enum="io.github.bispov19.NautilusVitrine.WindowStyle">
      <default>'finder'</default>
      <summary>Estilo da janela</summary>
      <description>finder: visual e ferramentas inspirados no Finder do macOS. nautilus: o Nautilus padrão.</description>
    </key>

    <key name="preview-visible" type="b">
      <default>true</default>
      <summary>Painel de pré-visualização aberto</summary>
    </key>
    <key name="preview-width" type="i">
      <range min="180" max="1200"/>
      <default>320</default>
      <summary>Largura do painel de pré-visualização (px)</summary>
    </key>
    <key name="column-width" type="i">
      <range min="120" max="600"/>
      <default>230</default>
      <summary>Largura de cada coluna no modo Colunas (px)</summary>
    </key>
    <key name="max-visible-columns" type="i">
      <range min="1" max="10"/>
      <default>3</default>
      <summary>Colunas visíveis antes de começar a rolar</summary>
    </key>

    <key name="remember-per-folder" type="b">
      <default>true</default>
      <summary>Lembrar a visualização escolhida em cada pasta</summary>
    </key>
    <key name="auto-media-grid" type="b">
      <default>true</default>
      <summary>Abrir pastas de fotos e vídeos em ícones grandes</summary>
    </key>
    <key name="auto-media-zoom" type="s">
      <choices>
        <choice value="small"/><choice value="small-plus"/><choice value="medium"/>
        <choice value="large"/><choice value="extra-large"/>
      </choices>
      <default>'extra-large'</default>
      <summary>Zoom usado nas pastas de fotos e vídeos</summary>
    </key>
    <key name="auto-media-ratio" type="d">
      <range min="0.0" max="1.0"/>
      <default>0.6</default>
      <summary>Proporção mínima de mídia para considerar "pasta de fotos"</summary>
    </key>
    <key name="folder-discovery" type="b">
      <default>false</default>
      <summary>Descoberta automática de pastas</summary>
    </key>
    <key name="default-mode" type="s">
      <default>''</default>
      <summary>Visualização das pastas sem regra (list, grid, columns; vazio = do Nautilus)</summary>
    </key>
    <key name="default-grid-zoom" type="s">
      <default>''</default>
      <summary>Zoom padrão dos ícones (vazio = do Nautilus)</summary>
    </key>

    <key name="start-on-computer" type="b">
      <default>false</default>
      <summary>Abrir o Nautilus no Meu computador</summary>
    </key>
    <key name="computer-in-sidebar" type="b">
      <default>true</default>
      <summary>Entrada Meu computador na barra lateral</summary>
    </key>
    <key name="computer-sections" type="a{sb}">
      <default>{}</default>
      <summary>Seções do Meu computador ligadas/desligadas</summary>
    </key>
    <key name="computer-hidden" type="as">
      <default>[]</default>
      <summary>Itens ocultos do Meu computador</summary>
    </key>
    <key name="notify-new-devices" type="b">
      <default>true</default>
      <summary>Avisar quando um dispositivo for conectado</summary>
    </key>

    <key name="tags" type="a(ss)">
      <default>[('Vermelho', 'red'), ('Laranja', 'orange'), ('Amarelo', 'yellow'), ('Verde', 'green'), ('Azul', 'blue'), ('Roxo', 'purple')]</default>
      <summary>Etiquetas (nome, cor)</summary>
      <description>Cores: red, orange, yellow, green, blue, purple, gray. Os nomes ficam gravados nos arquivos (atributo user.xdg.tags).</description>
    </key>
    <key name="tags-in-sidebar" type="b">
      <default>true</default>
      <summary>Seção Etiquetas na barra lateral (estilo Finder)</summary>
    </key>
    <key name="tags-section-expanded" type="b">
      <default>true</default>
      <summary>Seção Etiquetas aberta na barra lateral</summary>
    </key>
    <key name="image-dimensions" type="b">
      <default>true</default>
      <summary>Mostrar as dimensões das imagens abaixo do nome (estilo Finder, visão em grade)</summary>
    </key>

    <key name="gallery-group-by" type="s">
      <choices>
        <choice value="none"/><choice value="date"/><choice value="type"/>
        <choice value="size"/><choice value="tags"/>
      </choices>
      <default>'date'</default>
      <summary>Agrupamento da Galeria</summary>
    </key>
    <key name="path-bar" type="b">
      <default>false</default>
      <summary>Barra de caminho embaixo (estilo Finder)</summary>
    </key>
    <key name="status-bar" type="b">
      <default>false</default>
      <summary>Barra de status embaixo (estilo Finder)</summary>
    </key>

    <key name="json-migrated" type="b">
      <default>false</default>
      <summary>As preferências antigas (settings.json) já foram importadas</summary>
    </key>
  </schema>
</schemalist>
__VITRINE_ARQUIVO_34__
mkdir -p "tools"
cat > 'tools/smoke_test.py' <<'__VITRINE_ARQUIVO_35__'
"""Teste rápido FORA do Nautilus: abre as colunas e o painel de preview numa janela
própria e salva uma captura em PNG; monta a página "Sobre" nos temas claro e escuro
(saida-sobre-claro.png / saida-sobre-escuro.png) e confere se a versão do .spec é a
mesma de vitrine/__init__.py. Uso:

    python3 tools/smoke_test.py [pasta] [arquivo-para-preview] [saida.png]
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Graphene", "1.0")
from gi.repository import Adw, Gio, GLib, Graphene, Gtk  # noqa: E402

from vitrine import __version__  # noqa: E402
from vitrine.about import build_about_page  # noqa: E402
from vitrine.columns import ColumnStrip  # noqa: E402
from vitrine.main import CSS  # noqa: E402
from vitrine.preview import PreviewPane  # noqa: E402
from vitrine.util import ASSETS  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

folder = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
target = sys.argv[2] if len(sys.argv) > 2 else None
out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/vitrine-smoke.png"
failures = []


def check_version() -> None:
    with open(os.path.join(ROOT, "packaging", "nautilus-vitrine.spec"), encoding="utf-8") as fh:
        spec = re.search(r"^Version:\s*(\S+)", fh.read(), re.M).group(1)
    ok = spec == __version__
    print(f"versão: spec={spec} __version__={__version__} {'ok' if ok else 'DIFERENTES'}")
    if not ok:
        failures.append("versão")


def save_png(widget, win, path, required=True) -> None:
    w, h = widget.get_width(), widget.get_height()
    paintable = Gtk.WidgetPaintable.new(widget).get_current_image()
    snap = Gtk.Snapshot()
    paintable.snapshot(snap, w, h)
    node = snap.to_node()
    if node is None:
        if required:
            failures.append(f"captura vazia: {path}")
        else:
            print(f"aviso: captura vazia (problema antigo, não bloqueia): {path}")
        return
    tex = win.get_renderer().render_texture(node, Graphene.Rect().init(0, 0, w, h))
    tex.save_to_png(path)
    print("png:", path)


def on_activate(app):
    win = Adw.ApplicationWindow(application=app, default_width=1200, default_height=700)
    Gtk.IconTheme.get_for_display(win.get_display()).add_search_path(ASSETS)
    prov = Gtk.CssProvider()
    prov.load_from_bytes(GLib.Bytes.new(CSS))
    Gtk.StyleContext.add_provider_for_display(win.get_display(), prov, 800)
    events = []
    strip = ColumnStrip(column_width=230, max_visible=3,
                        on_navigate=lambda u: events.append(("nav", u)),
                        on_reveal=lambda f, u: events.append(("reveal", f, u)))
    preview = PreviewPane(on_navigate=print, on_reveal=print, on_quicklook=lambda: None)
    middle = Gtk.Label(label="[lista nativa do Nautilus]", hexpand=True)
    box = Gtk.Box()
    box.append(strip)
    box.append(middle)
    paned = Gtk.Paned(start_child=box, end_child=preview, resize_end_child=False,
                      shrink_end_child=False)
    win.set_content(paned)
    win.present()
    strip.set_location(Gio.File.new_for_path(folder))
    preview.set_folder(Gio.File.new_for_path(folder).get_uri())
    preview.show_uris([Gio.File.new_for_path(target).get_uri()] if target else [])

    def shot():
        paned.set_position(win.get_width() - 330)
        save_png(paned, win, out, required=False)
        rows = []
        c = preview.info.get_first_child()
        while c is not None:
            rows.append(c.get_label())
            c = c.get_next_sibling()
        print("preview:", preview.media.get_visible_child_name(), "|", preview.title.get_text(),
              "|", preview.subtitle.get_text(), "|", rows)
        cols = [(c.folder.get_path(), c.selection.get_model().get_n_items(), c.highlight_uri)
                for c in strip.columns]
        print("colunas:", cols)
        print("eventos:", events)
        about_shots(app)
        return False

    GLib.timeout_add(2500, shot)


def about_shots(app) -> None:
    """Página Sobre no tema claro e depois no escuro."""
    win = Adw.ApplicationWindow(application=app, default_width=640, default_height=900)
    win.set_content(build_about_page())
    win.present()
    style = Adw.StyleManager.get_default()
    base = os.path.splitext(out)[0]
    schemes = [("claro", Adw.ColorScheme.FORCE_LIGHT), ("escuro", Adw.ColorScheme.FORCE_DARK)]

    def next_scheme():
        if not schemes:
            app.quit()
            return False
        name, scheme = schemes.pop(0)
        style.set_color_scheme(scheme)
        GLib.timeout_add(700, lambda: (save_png(win, win,
                                                f"{base}-sobre-{name}.png"), next_scheme())[1])
        return False

    GLib.timeout_add(300, next_scheme)


check_version()
app = Adw.Application(application_id="io.github.vitrine.SmokeTest",
                      flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", on_activate)
app.run([])
if failures:
    print("FALHAS:", failures)
    sys.exit(1)
__VITRINE_ARQUIVO_35__
mkdir -p "tools"
cat > 'tools/test_history.py' <<'__VITRINE_ARQUIVO_36__'
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
__VITRINE_ARQUIVO_36__
mkdir -p "tools"
cat > 'tools/test_config.py' <<'__VITRINE_ARQUIVO_37__'
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
__VITRINE_ARQUIVO_37__
mkdir -p "tools"
cat > 'tools/test_tags.py' <<'__VITRINE_ARQUIVO_38__'
"""Testes das etiquetas (user.xdg.tags) em arquivos temporários.

    python3 tools/test_tags.py

Precisa de um sistema de arquivos com atributos estendidos de usuário (ext4, btrfs,
xfs e o tmpfs dos kernels recentes têm).
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from vitrine import tags  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + (f"  ({detail})" if not ok and detail else ""))


class FakeCfg:
    def __init__(self):
        self.data = {"tags": list(tags.DEFAULT_TAGS)}

    def get(self, k):
        return self.data.get(k)

    def set(self, k, v):
        self.data[k] = v


def main() -> int:
    root = tempfile.mkdtemp(prefix="vitrine-tags-")
    a, b = os.path.join(root, "a.txt"), os.path.join(root, "b b.jpg")
    sub = os.path.join(root, "pasta")
    os.makedirs(os.path.join(sub, ".oculta"))
    hidden = os.path.join(sub, ".oculta", "c.txt")
    for p in (a, b, hidden):
        open(p, "w").close()
    try:
        os.setxattr(a, "user.test", b"1")
    except OSError as err:
        print(f"PULADO: este sistema de arquivos não aceita atributos estendidos ({err})")
        return 0
    ua, ub = tags.path_to_uri(a), tags.path_to_uri(b)

    notified = []
    store = tags.TagStore(FakeCfg(), index_path=os.path.join(root, "idx.json"),
                          on_files_changed=notified.extend)
    check("6 etiquetas padrão com os nomes em português",
          store.names() == ["Vermelho", "Laranja", "Amarelo", "Verde", "Azul", "Roxo"])

    applied = store.toggle([ua, ub], "Vermelho")
    check("aplicar etiqueta grava user.xdg.tags", applied and tags.read_tags(a) == ["Vermelho"]
          and tags.read_tags(b) == ["Vermelho"], str(tags.read_tags(a)))
    check("o Nautilus é avisado dos arquivos alterados", set(notified) == {ua, ub})
    store.add([ua], "Azul")
    check("várias etiquetas por arquivo (formato separado por vírgula)",
          os.getxattr(a, tags.XATTR) == b"Vermelho,Azul")
    check("arquivos com a etiqueta (índice)", store.files_with("Vermelho") == [ua, ub],
          str(store.files_with("Vermelho")))

    applied = store.toggle([ua, ub], "Vermelho")
    check("se todos já têm, alternar tira de todos", not applied and tags.read_tags(a) == ["Azul"]
          and tags.read_tags(b) == [])

    store.add([ua], "Verde")
    check("renomear etiqueta atualiza os arquivos", store.rename("Verde", "Projetos")
          and tags.read_tags(a) == ["Azul", "Projetos"] and "Projetos" in store.names(),
          str(tags.read_tags(a)))
    store.recolor("Projetos", "purple")
    check("trocar a cor", store.color_of("Projetos") == "purple")
    store.delete("Azul")
    check("apagar etiqueta tira dos arquivos", tags.read_tags(a) == ["Projetos"]
          and "Azul" not in store.names())
    check("nome repetido ou vazio não é criado", not store.create("Projetos")
          and not store.create("  ") and store.create("Viagem, 2026", "blue")
          and "Viagem  2026" in store.names())

    store.clear([ua])
    check("remover todas as etiquetas apaga o atributo",
          tags.read_tags(a) == [] and store.files_with("Projetos") == [])

    # Etiquetas postas por outro programa aparecem depois de uma busca
    os.setxattr(b, tags.XATTR, b"Laranja")
    os.setxattr(hidden, tags.XATTR, b"Laranja")
    other = tags.TagStore(FakeCfg(), index_path=os.path.join(root, "idx2.json"))
    found = other.scan(root)
    check("busca acha etiquetas de outros programas (pula pastas ocultas)",
          found == 1 and other.files_with("Laranja") == [ub], f"{found} {other.files_with('Laranja')}")
    os.remove(b)
    check("arquivo apagado sai do índice", other.files_with("Laranja") == [])

    print(f"\n{sum(results)}/{len(results)} verificações passaram")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
__VITRINE_ARQUIVO_38__
mkdir -p "tools"
cat > 'tools/test_gallery.py' <<'__VITRINE_ARQUIVO_39__'
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
__VITRINE_ARQUIVO_39__
mkdir -p "tools"
cat > 'tools/build_bootstrap.py' <<'__VITRINE_ARQUIVO_40__'
"""Gera `criar-vitrine.sh`: um único script bash que recria o projeto inteiro
(todos os arquivos) numa pasta e, se você quiser, já instala no Nautilus.

    python3 tools/build_bootstrap.py
"""

import os
import stat

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "criar-vitrine.sh")
INCLUDE = [
    "nautilus-vitrine.py",
    "vitrine",
    "tools/smoke_test.py",
    "tools/test_history.py",
    "tools/test_config.py",
    "tools/test_tags.py",
    "tools/test_gallery.py",
    "tools/build_bootstrap.py",
    "install.sh",
    "uninstall.sh",
    ".vscode",
    "README.md",
    "LICENSE",
    ".gitignore",
    "Makefile",
    "packaging",
    ".copr",
]
EXECUTABLE = {"install.sh", "uninstall.sh"}

HEADER = r'''#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  criar-vitrine.sh — cria o projeto "Vitrine para Nautilus" (Fedora / GNOME)
#
#  Uso:
#     bash criar-vitrine.sh                 # cria em ~/nautilus-vitrine
#     bash criar-vitrine.sh ~/Projetos/vit  # cria na pasta indicada
#     bash criar-vitrine.sh --instalar      # cria e já instala no Nautilus
#
#  Depois:  code ~/nautilus-vitrine   (abre no VS Code; Ctrl+Shift+B instala)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TARGET="$HOME/nautilus-vitrine"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --instalar|--install) INSTALL=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) TARGET="$arg" ;;
  esac
done

if [[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
  read -r -p "A pasta $TARGET já existe e não está vazia. Sobrescrever os arquivos da Vitrine? [s/N] " ans
  [[ "${ans:-N}" =~ ^[SsYy]$ ]] || { echo "Cancelado."; exit 1; }
fi
mkdir -p "$TARGET"
cd "$TARGET"
echo "Criando arquivos em $TARGET …"

'''

FOOTER = r'''
chmod +x install.sh uninstall.sh
echo "Projeto criado em $TARGET"

if [[ "$INSTALL" == 1 ]]; then
  ./install.sh
else
  echo
  echo "Próximos passos:"
  echo "  cd \"$TARGET\" && ./install.sh        # instala e reinicia o Nautilus"
  echo "  code \"$TARGET\"                      # abre no VS Code (Ctrl+Shift+B = instalar em modo dev)"
fi
'''


def collect() -> list[str]:
    files = []
    for entry in INCLUDE:
        path = os.path.join(ROOT, entry)
        if os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
                for name in sorted(filenames):
                    if name.endswith((".pyc", ".tmp", ".compiled")):
                        continue
                    files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
        elif os.path.exists(path):
            files.append(entry)
    return files


def main() -> None:
    parts = [HEADER]
    for i, rel in enumerate(collect()):
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            content = fh.read()
        delim = f"__VITRINE_ARQUIVO_{i}__"
        assert delim not in content
        if not content.endswith("\n"):
            content += "\n"
        d = os.path.dirname(rel)
        if d:
            parts.append(f'mkdir -p "{d}"\n')
        parts.append(f"cat > '{rel}' <<'{delim}'\n{content}{delim}\n")
    parts.append(FOOTER)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("".join(parts))
    os.chmod(OUT, os.stat(OUT).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"gerado: {OUT}")


if __name__ == "__main__":
    main()
__VITRINE_ARQUIVO_40__
cat > 'install.sh' <<'__VITRINE_ARQUIVO_41__'
#!/usr/bin/env bash
# Instala a Vitrine para o seu usuário (não precisa de root, exceto para o nautilus-python).
#
#   ./install.sh          copia os arquivos
#   ./install.sh --dev    cria links simbólicos (edite no VS Code e só reinicie o Nautilus)
#   ./install.sh --no-restart
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
MODE="copy"
RESTART=1
for arg in "$@"; do
  case "$arg" in
    --dev) MODE="link" ;;
    --no-restart) RESTART=0 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
  esac
done

if ! rpm -q nautilus-python >/dev/null 2>&1; then
  echo "O pacote nautilus-python não está instalado; ele é necessário para carregar extensões em Python."
  read -r -p "Instalar agora com 'sudo dnf install nautilus-python'? [S/n] " ans
  if [[ "${ans:-S}" =~ ^[SsYy]$ ]]; then
    sudo dnf install -y nautilus-python
  else
    echo "Instale depois com: sudo dnf install nautilus-python"
    exit 1
  fi
fi

if rpm -q nautilus-vitrine >/dev/null 2>&1; then
  echo "Aviso: o pacote RPM nautilus-vitrine também está instalado."
  echo "Só uma cópia fica ativa (a primeira que o Nautilus carregar)."
  echo "Para testar esta cópia de desenvolvimento: sudo dnf remove nautilus-vitrine"
fi

mkdir -p "$DEST"
rm -rf "$DEST/vitrine" "$DEST/nautilus-vitrine.py"
if [[ "$MODE" == "link" ]]; then
  ln -s "$HERE/vitrine" "$DEST/vitrine"
  ln -s "$HERE/nautilus-vitrine.py" "$DEST/nautilus-vitrine.py"
  echo "Links de desenvolvimento criados em $DEST"
else
  cp -r "$HERE/vitrine" "$DEST/vitrine"
  cp "$HERE/nautilus-vitrine.py" "$DEST/nautilus-vitrine.py"
  find "$DEST/vitrine" -name '__pycache__' -prune -exec rm -rf {} +
  echo "Arquivos copiados para $DEST"
fi

# Preferências em GSettings: o schema vem dentro da extensão e é compilado aqui
# (a Vitrine o carrega desta pasta; não precisa de root).
if command -v glib-compile-schemas >/dev/null; then
  glib-compile-schemas --strict "$DEST/vitrine/schemas"
else
  echo "Aviso: glib-compile-schemas não encontrado; a Vitrine compila o schema na primeira execução."
fi

if [[ "$RESTART" == 1 ]]; then
  echo "Reiniciando o Nautilus (janelas abertas do Arquivos serão fechadas)…"
  nautilus -q 2>/dev/null || true
  sleep 1
  (setsid nautilus >/dev/null 2>&1 &)
fi
echo "Pronto. Log: ${XDG_CACHE_HOME:-$HOME/.cache}/nautilus-vitrine/vitrine.log"
__VITRINE_ARQUIVO_41__
cat > 'uninstall.sh' <<'__VITRINE_ARQUIVO_42__'
#!/usr/bin/env bash
# Remove a Vitrine. Suas regras por pasta ficam em ~/.config/nautilus-vitrine
# (use --purge para apagá-las também).
set -euo pipefail
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
rm -rf "$DEST/vitrine" "$DEST/nautilus-vitrine.py"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/nautilus-vitrine" "${XDG_CACHE_HOME:-$HOME/.cache}/nautilus-vitrine"
fi
nautilus -q 2>/dev/null || true
echo "Vitrine removida. Abra o Arquivos de novo para voltar ao Nautilus original."
__VITRINE_ARQUIVO_42__
mkdir -p ".vscode"
cat > '.vscode/extensions.json' <<'__VITRINE_ARQUIVO_43__'
{
  "recommendations": ["ms-python.python", "ms-python.vscode-pylance"]
}
__VITRINE_ARQUIVO_43__
mkdir -p ".vscode"
cat > '.vscode/settings.json' <<'__VITRINE_ARQUIVO_44__'
{
  "python.defaultInterpreterPath": "/usr/bin/python3",
  "python.analysis.extraPaths": ["${workspaceFolder}"],
  "files.exclude": { "**/__pycache__": true },
  "editor.rulers": [100],
  "[python]": { "editor.tabSize": 4 }
}
__VITRINE_ARQUIVO_44__
mkdir -p ".vscode"
cat > '.vscode/tasks.json' <<'__VITRINE_ARQUIVO_45__'
{
  // Ctrl+Shift+P → "Tasks: Run Task" para ver estas tarefas.
  // Ctrl+Shift+B roda a tarefa padrão (instalar em modo dev + reiniciar o Nautilus).
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Vitrine: instalar (modo dev, com links) e reiniciar Nautilus",
      "type": "shell",
      "command": "./install.sh --dev",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "Vitrine: instalar (cópia definitiva)",
      "type": "shell",
      "command": "./install.sh",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: reiniciar Nautilus",
      "type": "shell",
      "command": "nautilus -q; sleep 1; (setsid nautilus >/dev/null 2>&1 &)",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: rodar Nautilus em modo depuração (log no terminal)",
      "type": "shell",
      "command": "nautilus -q; sleep 1; VITRINE_DEBUG=1 VITRINE_DUMP=1 nautilus",
      "isBackground": true,
      "problemMatcher": []
    },
    {
      "label": "Vitrine: autoteste dentro do Nautilus (resultado no log)",
      "type": "shell",
      "command": "rm -f ~/.cache/nautilus-vitrine/vitrine.log; nautilus -q; sleep 1; (VITRINE_SELFTEST=1 setsid nautilus --new-window \"$HOME\" >/dev/null 2>&1 &); timeout 60 bash -c 'until grep -q \"SELFTEST RESUMO\" ~/.cache/nautilus-vitrine/vitrine.log 2>/dev/null; do sleep 2; done'; grep SELFTEST ~/.cache/nautilus-vitrine/vitrine.log",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: acompanhar log",
      "type": "shell",
      "command": "mkdir -p ~/.cache/nautilus-vitrine && touch ~/.cache/nautilus-vitrine/vitrine.log && tail -n 80 -f ~/.cache/nautilus-vitrine/vitrine.log",
      "isBackground": true,
      "problemMatcher": []
    },
    {
      "label": "Vitrine: teste fora do Nautilus (colunas + preview)",
      "type": "shell",
      "command": "python3 -u tools/smoke_test.py \"$(xdg-user-dir PICTURES)\"",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: checar sintaxe",
      "type": "shell",
      "command": "python3 -m py_compile nautilus-vitrine.py vitrine/*.py tools/*.py && echo OK",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: gerar script único criar-vitrine.sh",
      "type": "shell",
      "command": "python3 tools/build_bootstrap.py",
      "problemMatcher": []
    },
    {
      "label": "Vitrine: desinstalar",
      "type": "shell",
      "command": "./uninstall.sh",
      "problemMatcher": []
    }
  ]
}
__VITRINE_ARQUIVO_45__
cat > 'README.md' <<'__VITRINE_ARQUIVO_46__'
<p align="center">
  <img src="vitrine/assets/nautilus-vitrine-logo.svg" width="96" alt="Logo da Vitrine para Nautilus">
</p>

# Vitrine para Nautilus

**Modo Colunas, painel de pré-visualização, visualização por pasta e "Meu computador" para o Arquivos (Nautilus) do GNOME, inspirados no Finder do macOS, sem perder nenhuma função nativa.**

![Nautilus 51](https://img.shields.io/badge/Nautilus-51-4a86cf)
![Fedora 45](https://img.shields.io/badge/Fedora-45-51a2da)
![Python](https://img.shields.io/badge/Python-3-3776ab)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-green)

<!-- Capturas de tela: salve as imagens em docs/ e descomente as linhas abaixo.
![Modo Colunas com pré-visualização](docs/colunas.png)
![Pasta Imagens em ícones grandes](docs/imagens.png)
-->

A Vitrine é uma extensão para o **Nautilus 51** (e, em princípio, o 50). Ela acrescenta ao gerenciador de arquivos do GNOME recursos que fazem falta para quem vem do macOS ou do Windows:

- 🗂️ **Modo Colunas**: navegue pelas pastas em colunas, como no Finder.
- 🖼️ **Painel de pré-visualização**: veja imagens, textos, vídeos, PDFs e pastas ao lado da lista, sem abrir nada.
- 📌 **Visualização por pasta**: cada pasta lembra se você prefere lista, ícones, ícones grandes ou colunas.
- 🍎 **Estilo Finder** (padrão): barra de ferramentas em cápsulas, título da pasta, seletor de visualização e barra lateral no estilo do Finder do macOS. Dá para voltar ao **Nautilus padrão** a qualquer momento.
- 💻 **Meu computador**: suas pastas, discos e dispositivos numa página só, com o espaço livre de cada um e aviso quando um pen drive é conectado.

A diferença em relação a outras soluções é o **modo híbrido**. A pasta atual continua sendo exibida pela **própria lista do Nautilus**, então menu de contexto, renomear, arrastar e soltar, recortar e colar, Desfazer, scripts e outras extensões funcionam exatamente como antes. A Vitrine só acrescenta coisas; não substitui nada.

---

## Recursos

### 🍎 Estilo da janela: Finder (macOS) ou Nautilus padrão

O estilo **Finder** vem ligado de fábrica. Troque em **☰ da linha Meu computador → Personalizar → Estilo da janela**; vale na hora, em todas as janelas.

- Barra de ferramentas: **← →** numa cápsula e o **nome da pasta** em negrito; à direita, **Visão em grade / Visão em lista / Colunas / Galeria**, **Ordenar e agrupar** (A-Z, Z-A, última e primeira modificação, tamanho, tipo; agrupar na Galeria), **Etiquetas**, **Compartilhar** (copiar local, enviar por e-mail, Bluetooth, compartilhamento na rede), **⋯** (nova pasta, documento vazio, propriedades, renomear, comprimir, copiar, colar, mover para a lixeira, arquivos ocultos, painel de pré-visualização, pesquisar em todos os lugares) e **Pesquisar**.
- A barra de caminho aparece ao editar o local (**Ctrl+L**) ou ao pesquisar.
- Opcionais (em *Personalizar → Estilo Finder*): **barra de caminho** embaixo, clicável, e **barra de status** com a quantidade de itens e o espaço disponível.
- Barra lateral com ícones na cor de destaque do sistema e seleção cinza arredondada.
- Os nomes seguem os do GNOME (a Vitrine usa a tradução do próprio Nautilus). Os botões de fechar, minimizar e maximizar ficam no padrão do GNOME.
- **Visão em grade:** dimensões das imagens (ex.: *1.066 × 1.599*) em azul abaixo do nome, seleção cinza arredondada. O nome longo já é truncado no meio pelo próprio Nautilus.
- **Visão em lista:** linhas alternadas suaves.
- **Nautilus padrão** remove tudo o que o estilo Finder acrescentou (CSS, botões, sinais). Colunas, pré-visualização e Meu computador continuam conforme as suas opções.


### 🖼️ Galeria

Ative com **Ctrl+4**, com o botão da Galeria (estilo Finder) ou em **Visualização desta pasta → Galeria**.

- Imagem grande do item selecionado, faixa de miniaturas rolável embaixo e painel com nome, tipo, tamanho, dimensões, datas e etiquetas.
- **Agrupar** a faixa por data de modificação (*Hoje, Ontem, Últimos 7 dias, Últimos 30 dias*, meses e anos), tipo, tamanho ou etiqueta, pelo menu *Ordenar e agrupar*.
- Setas navegam; **Enter** abre; **Espaço** abre a visualização rápida. A seleção vai para a lista nativa do Nautilus, então Propriedades, Renomear, Comprimir e Mover para a lixeira (clique direito ou menu ⋯) agem no item da Galeria.
- A escolha da Galeria é lembrada por pasta, como as outras visualizações.

### 🗂️ Modo Colunas

- Ative com **Ctrl+3** ou com o botão de colunas na barra superior.
- As pastas anteriores do caminho aparecem como colunas à esquerda, com o item do caminho destacado. A pasta atual fica na lista nativa do Nautilus, à direita.
- Clique numa pasta de qualquer coluna para ir até ela. Navegar com as setas do teclado funciona.
- Clique num arquivo de uma coluna anterior para abrir a pasta dele **já com o arquivo selecionado** na lista nativa, com todas as ações do Nautilus disponíveis.
- **Arraste e solte** entre colunas, da coluna para a lista e da lista para a coluna. Mover e copiar usam as operações do próprio Nautilus, com barra de progresso, diálogo de conflito e **Ctrl+Z**.
- Clique do meio numa pasta abre em nova janela. O clique direito traz Abrir, Abrir em nova janela, Mostrar na lista, Copiar caminho e Mover para a lixeira.
- Respeita a opção de **mostrar arquivos ocultos** do Nautilus.

### 🖼️ Painel de pré-visualização

Ative com **Ctrl+Shift+P** ou com o botão de painel. A largura pode ser ajustada arrastando a borda e fica salva.

| Seleção | O que o painel mostra |
|---|---|
| Imagem | A imagem com rotação EXIF correta, dimensões, tipo, tamanho e datas |
| Texto / código | O conteúdo, em fonte monoespaçada (até 400 linhas) |
| Vídeo, PDF, documentos | A miniatura do sistema (gerada na hora, se ainda não existir) |
| Pasta | A lista do conteúdo, com contagem de pastas e arquivos. Clique para entrar |
| Vários itens | A quantidade de itens e o tamanho total |
| Nada selecionado | As informações da pasta atual |

O botão **Abrir** usa o aplicativo padrão. O botão 👁 (ou a tecla **Espaço**) abre a visualização rápida do GNOME (Sushi).

**Rápido de verdade.** No Fedora 45 o carregador de imagens do sistema (glycin) abre um processo isolado para cada imagem. A Vitrine contorna isso:

- mostra a miniatura já existente na hora;
- decodifica JPEG, PNG e TIFF com o decodificador do GTK, lendo dimensões e rotação direto do cabeçalho;
- guarda em cache as imagens já vistas;
- pré-carrega as imagens vizinhas.

| Situação (medida no Nautilus 51) | Primeira imagem | Imagem nítida |
|---|---|---|
| Foto nova | ~40 ms | ~190 ms |
| Foto vizinha (pré-carregada) | ~38 ms | ~38 ms |
| Foto já vista | ~37 ms | ~37 ms |

### 📌 Visualização por pasta

- Trocou de visualização numa pasta, com **Ctrl+1** (lista), **Ctrl+2** (ícones), **Ctrl+3** (colunas), os botões ou o menu? A Vitrine **lembra a escolha para aquela pasta**. Pastas sem regra usam o seu padrão.
- O **zoom dos ícones também é salvo por pasta**: ícones gigantes em *Imagens*, ícones normais em *Downloads*.
- **Pastas de fotos e vídeos são detectadas automaticamente.** Se a maioria dos arquivos for imagem ou vídeo, a pasta abre em ícones grandes.
- **Descoberta automática de pastas** (opcional, desligada por padrão): olha o tipo dos arquivos de cada pasta e escolhe a visualização. Maioria de fotos/vídeos → ícones extra grandes; maioria de documentos e outros arquivos → lista; pasta mista ou vazia → o seu padrão. Só lê o nome/extensão de até 200 itens (rápido mesmo em pastas enormes) e guarda o resultado até a pasta mudar. Uma escolha feita à mão numa pasta sempre vence a descoberta. Ligue no menu **Visualização desta pasta** ou em **Personalizar** (menu ☰ da linha Meu computador).
- Na primeira execução, *Imagens* e *Vídeos* já vêm configuradas para ícones grandes, **incluindo as subpastas**.
- Navegando em colunas, as subpastas continuam em colunas.

Clique com o botão direito no **fundo de qualquer pasta** e escolha **Visualização desta pasta**:

- Lista · Ícones · Ícones grandes · Colunas
- Aplicar também às subpastas / Não aplicar às subpastas
- Esquecer esta pasta (usar o padrão)
- Ligar/desligar a descoberta automática de pastas
- Usar a visualização atual como padrão
- Mostrar/ocultar pré-visualização

### 🏷️ Etiquetas coloridas

Vermelho, Laranja, Amarelo, Verde, Azul e Roxo, além das que você criar.

- Gravadas no atributo estendido padrão **`user.xdg.tags`** (o mesmo de outros gerenciadores de arquivos, como o Dolphin): continuam valendo fora da Vitrine.
- **Aplicar:** clique direito → *Etiquetas*, botão de etiqueta na barra de ferramentas (estilo Finder) ou arrastando arquivos para a etiqueta na barra lateral. Vários arquivos e várias etiquetas por arquivo.
- **Ver:** bolinhas coloridas nos ícones (grade, lista e colunas), coluna **Etiquetas** na lista (ligue em *Colunas visíveis* do Nautilus) e a seção **Etiquetas** da barra lateral, que mostra os arquivos de cada etiqueta.
- **Todas as etiquetas…:** criar, renomear, trocar a cor e apagar. Renomear e apagar atualizam os arquivos que a Vitrine conhece.
- Arquivos etiquetados por outros programas aparecem depois de abertos no Nautilus, ou com *Procurar na pasta pessoal* na página da etiqueta.
- Pen drives FAT/exFAT e alguns compartilhamentos de rede não aceitam atributos estendidos; a Vitrine avisa.

### 💻 Meu computador

Abra pela entrada **Meu computador** no topo da barra lateral, com **Ctrl+Shift+C** ou pelo clique direito no fundo de uma pasta.

- **Pastas**: tudo o que está na barra lateral do Nautilus, com os mesmos nomes, numa grade única: primeiro a Pasta pessoal, depois Documentos, Downloads, Imagens, Músicas e Vídeos, em seguida as demais pastas fixadas em ordem alfabética e, por fim, Recentes, Favoritos, Rede e Lixeira. Fixou ou removeu uma pasta da barra lateral? O Meu computador acompanha.
- **Dispositivos e unidades**: disco do sistema, outros discos, pen drives, HDs externos, cartões de memória e celulares, cada um com **barra de uso** (azul, laranja acima de 80%, vermelha acima de 92%) e "X livres de Y · sistema de arquivos". O uso é atualizado a cada 10 segundos enquanto a página está aberta.
- **Rede**: compartilhamentos montados (SMB, SFTP, WebDAV…), quando houver.
- **Dispositivos não montados** aparecem também. Ao abrir, a Vitrine monta o dispositivo e pede a senha se ele for criptografado.
- **Remover com segurança**: botão ⏏ no card ou clique direito → *Remover com segurança* / *Desmontar*. Um aviso confirma quando já dá para tirar o dispositivo.
- **Selecionar o card** mostra o conteúdo do disco no painel de pré-visualização. Abrir segue o clique simples ou duplo configurado no Nautilus.
- Atalho para o app **Discos**, para formatar e particionar.

**Dispositivo novo conectado?** Assim que um pen drive, HD externo ou cartão é inserido, aparece um aviso na janela do Nautilus (*"Pen drive conectado — Abrir"*). O card dele ganha o selo **Novo**, fica destacado e já vem **selecionado** na página Meu computador.

A página fecha sozinha quando você navega para qualquer lugar: barra lateral, barra de caminho ou busca.

**Voltar e Avançar funcionam como num navegador.** O Meu computador entra no histórico de cada aba: Meu computador → Imagens → **Voltar** leva de volta ao Meu computador, e **Avançar** volta para Imagens. Vale para os botões ← →, **Alt+←** / **Alt+→** e os botões laterais do mouse. Se o Meu computador for o primeiro lugar da janela, o Voltar fica desativado enquanto ele estiver aberto. Cada aba tem o seu próprio histórico, e trocar de aba mostra o Meu computador se ele for o lugar atual daquela aba.

**Personalizar:** o menu ☰ na linha **Meu computador** da barra lateral (ou clique direito num item → *Personalizar…*) abre uma tela para:

- **Abrir o Nautilus no Meu computador**: ao abrir o Arquivos pelo menu de aplicativos ou numa janela nova (Ctrl+N), ele começa aqui. Se outro programa pedir uma pasta específica, ela é respeitada.
- Mostrar ou esconder a entrada **Meu computador na barra lateral**.
- Ligar ou desligar o **aviso de dispositivo novo**.
- Escolher quais **seções** aparecem: Pastas, Dispositivos e unidades, Rede e o atalho para o Discos.
- Escolher **item por item** o que aparece. Também dá para ocultar direto pelo clique direito → *Ocultar do Meu computador*.
- **Mostrar tudo de novo**, com um clique.

O mesmo menu ☰ tem **Sobre a Vitrine** (versão, link do repositório e créditos), que também aparece no clique direito no fundo de uma pasta.

---

## Instalação

### Requisitos

- **Nautilus 51** (GNOME 51, Fedora 45), versão em que a extensão foi testada. O Nautilus 50 (Fedora 44) tem a mesma estrutura de janela e deve funcionar, mas ainda não foi testado. Outras distribuições com essas versões também devem funcionar.
- `nautilus-python` (o instalador oferece instalar).

### Opção 1 (recomendada): clonar o repositório

```bash
git clone https://github.com/bispov19/nautilus-vitrine.git
```

```bash
cd nautilus-vitrine && ./install.sh
```

O `install.sh` instala o `nautilus-python` se faltar (pede sua senha), copia a extensão para `~/.local/share/nautilus-python/extensions/` e reinicia o Nautilus. Para atualizar depois: `git pull && ./install.sh`.

### Opção 2: script único

O arquivo `criar-vitrine.sh` contém o projeto inteiro. Baixe-o e rode:

```bash
bash criar-vitrine.sh --instalar
```

Ele cria a pasta `~/nautilus-vitrine` com todos os arquivos e já instala. Sem `--instalar`, só cria a pasta. Também dá para passar outro destino: `bash criar-vitrine.sh ~/Projetos/vitrine`.

### Em breve: pacote RPM pelo COPR

O pacote RPM já está pronto (`packaging/nautilus-vitrine.spec`), mas **ainda não foi publicado no COPR**. Quando estiver disponível, a instalação será:

```
sudo dnf copr enable bispov19/nautilus-vitrine
sudo dnf install nautilus-vitrine
```

Até lá, use a opção 1 ou 2, ou gere o RPM localmente (veja *Empacotamento*).

### Desinstalar

```bash
./uninstall.sh
```

O Nautilus volta exatamente ao original. Suas regras ficam guardadas; use `./uninstall.sh --purge` para apagar tudo.

> **Não é uma extensão do GNOME Shell.** A Vitrine roda dentro do Nautilus, via nautilus-python, e por isso não aparece no app Extensões nem no extensions.gnome.org. Ela é gerenciada pelos scripts acima.

---

## Atalhos

| Atalho | Ação |
|---|---|
| **Ctrl+3** | Modo Colunas |
| **Ctrl+4** | Galeria |
| **Ctrl+I** | Propriedades (com a aba Etiquetas) |
| **Ctrl+1** / **Ctrl+2** | Lista / Ícones (nativos do Nautilus, agora lembrados por pasta) |
| **Ctrl+Shift+P** | Mostrar/ocultar a pré-visualização |
| **Ctrl+Shift+C** | Abrir/fechar o Meu computador |
| **Alt+←** / **Alt+→** | Voltar / Avançar (incluindo o Meu computador) |
| Botões laterais do mouse | Voltar / Avançar |
| **Espaço** | Visualização rápida (Sushi) |
| **Ctrl + roda do mouse** | Zoom (salvo por pasta na visualização em ícones) |
| Clique do meio numa coluna | Abrir a pasta em nova janela |

---

## Configuração

Tudo funciona sem configurar nada. As preferências ficam no **GSettings** (schema `io.github.bispov19.NautilusVitrine`, que vem dentro da extensão) e valem na hora, até pelo terminal:

```bash
gsettings --schemadir ~/.local/share/nautilus-python/extensions/vitrine/schemas list-recursively io.github.bispov19.NautilusVitrine
```

```bash
gsettings --schemadir ~/.local/share/nautilus-python/extensions/vitrine/schemas set io.github.bispov19.NautilusVitrine window-style nautilus
```

Na primeira execução da versão com GSettings, o antigo `settings.json` é importado e guardado como `settings.json.importado`. Os nomes abaixo usam `-` no GSettings (ex.: `preview-visible`).

| Chave | Padrão | Descrição |
|---|---|---|
| `window_style` | `"finder"` | Estilo da janela: `finder` ou `nautilus` |

| `preview_visible` | `true` | Painel de pré-visualização aberto |
| `preview_width` | `320` | Largura do painel (px), salva ao arrastar a borda |
| `column_width` | `230` | Largura de cada coluna (px) |
| `max_visible_columns` | `3` | Colunas visíveis antes de começar a rolar |
| `remember_per_folder` | `true` | Lembrar a visualização escolhida em cada pasta |
| `auto_media_grid` | `true` | Abrir pastas de fotos/vídeos em ícones grandes |
| `auto_media_zoom` | `"extra-large"` | Zoom usado nessas pastas |
| `auto_media_ratio` | `0.6` | Proporção mínima de mídia para considerar "pasta de fotos" |
| `folder_discovery` | `false` | Descoberta automática de pastas (mídia → ícones extra grandes, documentos → lista). Usa também `auto_media_zoom` e `auto_media_ratio` |
| `default_mode` | do Nautilus | Visualização das pastas sem regra: `list`, `grid` ou `columns` |
| `default_grid_zoom` | do Nautilus | Zoom padrão dos ícones |
| `start_on_computer` | `false` | Abrir o Nautilus já no Meu computador (quando abre na pasta pessoal) |
| `computer_in_sidebar` | `true` | Entrada "Meu computador" no topo da barra lateral |
| `computer_sections` | `{}` | Seções desligadas, ex.: `{"network": false}` (`places`, `devices`, `network`, `disks_button`) |
| `computer_hidden` | `[]` | Itens ocultos: URIs de locais (`"trash:///"`) ou chaves de dispositivos |
| `notify_new_devices` | `true` | Avisar quando um pen drive, HD externo ou cartão for conectado |
| `tags` | 6 cores | Etiquetas: lista de (nome, cor); cores `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `gray` |
| `tags_in_sidebar` | `true` | Seção Etiquetas na barra lateral (estilo Finder) |
| `image_dimensions` | `true` | Dimensões das imagens abaixo do nome na grade (estilo Finder) |
| `gallery_group_by` | `"date"` | Agrupamento da Galeria: `none`, `date`, `type`, `size`, `tags` |
| `path_bar` | `false` | Barra de caminho embaixo (estilo Finder) |
| `status_bar` | `false` | Barra de status embaixo (estilo Finder) |

**`~/.config/nautilus-vitrine/folders.json`** guarda as regras por pasta:

```json
{
  "file:///home/voce/Imagens": { "mode": "grid", "zoom": "extra-large", "recursive": true },
  "file:///home/voce/Projetos": { "mode": "columns" }
}
```

Zooms válidos: `small`, `small-plus`, `medium`, `large`, `extra-large`.

---

## Como funciona

O Nautilus não tem API pública para novas visualizações ou painéis. Assim como o [My Computer for Nautilus](https://github.com/yannmasoch/nautilus-my-computer), a Vitrine roda dentro do processo do Nautilus (via nautilus-python) e insere seus widgets na janela em tempo de execução. Para quebrar o mínimo possível com atualizações do GNOME:

- **Poucos pontos de injeção.** Só o conteúdo do `AdwToolbarView` que contém as abas é envolvido por `[colunas | abas do Nautilus ou Meu computador] ‖ [pré-visualização]`. A entrada "Meu computador" entra na barra lateral pela API pública `AdwToolbarView.add_top_bar`, sem mover nenhum widget do Nautilus. O resto da janela fica intocado.
- **Dispositivos pelo GIO.** A página e os avisos usam o `Gio.VolumeMonitor` (o mesmo serviço que o Nautilus usa), e montar, desmontar e ejetar passam por `Gtk.MountOperation`, com o diálogo de senha do sistema.
- **Nada do Nautilus é reimplementado.** A pasta atual é sempre a lista nativa, e a seleção é lida do próprio `NautilusViewModel`.
- **Sem referências fortes.** Widgets e modelos do Nautilus nunca são mantidos vivos pela extensão; o modelo de seleção é acompanhado por *weak reference*.
- **Operações nativas.** Mover, copiar e lixeira passam pela API D-Bus `org.gnome.Nautilus.FileOperations2`, com progresso, conflitos e Desfazer.
- **Voltar/Avançar com o Meu computador.** O Meu computador fica *por cima* da lista do Nautilus, então o histórico nativo não sabe dele. Cada aba guarda um histórico próprio (`history.py`) em que cada entrada lembra em que ponto do histórico do Nautilus estava. Os botões ← →, os atalhos Alt+←/→ e os botões do mouse passam por esse histórico; quando o destino é uma pasta, a Vitrine pede ao Nautilus o Voltar/Avançar nativo, e quando é o Meu computador, só mostra a página.
- **Falha segura.** Se uma versão futura do Nautilus mudar a estrutura da janela, a Vitrine simplesmente não se injeta e registra o motivo no log. Exceções em callbacks também viram log, sem derrubar o Nautilus.

### Estrutura do código

```
nautilus-vitrine.py     ponto de entrada carregado pelo nautilus-python
vitrine/
  main.py               descobre as janelas, CSS, menu "Visualização desta pasta"
  window.py             injeção por janela, botões, atalhos, regras por pasta
  columns.py            Modo Colunas (Gtk.DirectoryList + ListView)
  preview.py            painel de pré-visualização
  imageload.py          carregamento rápido de imagens, cache e pré-carregamento
  computer.py           página Meu computador e monitor de dispositivos
  config.py             preferências (GSettings) e regras por pasta (JSON)
  finder/               estilo Finder: aplica e remove a camada visual (barra de ferramentas, barras de baixo)
  schemas/              schema GSettings da Vitrine
  tags.py               etiquetas (user.xdg.tags) e índice dos arquivos etiquetados
  gallery.py            visualização em Galeria (Ctrl+4)
  tagui.py              telas das etiquetas (barra, barra lateral, página, Todas as etiquetas…)
  history.py            Voltar/Avançar por aba incluindo o Meu computador (sem GTK)
  about.py              página "Sobre" do diálogo de personalização
  assets/               logo, ícone simbólico e CSS da página Sobre
  native.py             ponte com o Nautilus (slot, lista/grade, seleção)
  util.py               log, varredura de widgets, operações D-Bus
  selftest.py           autoteste dentro do Nautilus real
tools/
  smoke_test.py         colunas, preview e página Sobre fora do Nautilus
  test_history.py       testes do histórico de Voltar/Avançar
  test_config.py        testes das preferências (GSettings)
  test_tags.py          testes das etiquetas
  test_gallery.py       testes dos grupos de data da Galeria
  build_bootstrap.py    gera o criar-vitrine.sh
packaging/
  nautilus-vitrine.spec receita do pacote RPM
.copr/Makefile          build automático no COPR
```

---

## Desenvolvimento

```bash
./install.sh --dev
```

O modo dev usa links simbólicos: edite o código e só reinicie o Nautilus (`nautilus -q`).

O projeto inclui tarefas do **VS Code** (*Terminal → Run Task*):

| Tarefa | O que faz |
|---|---|
| **Ctrl+Shift+B** | Instala em modo dev e reinicia o Nautilus |
| Autoteste dentro do Nautilus | Verificações automáticas: injeção, colunas, preview, regras por pasta, zoom, tempo de carregamento das imagens, Meu computador (locais da barra lateral, uso de disco, aviso de dispositivo novo, personalização, página Sobre, abrir direto nele) e Voltar/Avançar. Roda com regras temporárias; as suas e o zoom são restaurados no fim |
| Rodar em modo depuração | `VITRINE_DEBUG=1 VITRINE_DUMP=1 nautilus` (inclui a árvore de widgets da janela no log) |
| Acompanhar log | `tail -f ~/.cache/nautilus-vitrine/vitrine.log` |
| Teste fora do Nautilus | Abre colunas, preview e a página Sobre numa janela própria |
| Gerar script único | Atualiza o `criar-vitrine.sh` |

Os testes do histórico de Voltar/Avançar rodam sem o Nautilus:

```bash
python3 tools/test_history.py
```

Para rodar o autoteste pelo terminal:

```bash
nautilus -q; VITRINE_SELFTEST=1 nautilus --new-window ~ &
```

Depois de alguns segundos, veja o resultado:

```bash
grep SELFTEST ~/.cache/nautilus-vitrine/vitrine.log
```

### Empacotamento (RPM / COPR)

```bash
sudo dnf install make rpm-build python3-devel
```

```bash
make rpm
```

O RPM sai em `dist/`; `make install-rpm` instala. A receita fica em `packaging/nautilus-vitrine.spec`.

O COPR gera o pacote direto deste repositório usando `.copr/Makefile`. Configuração única em [copr.fedorainfracloud.org](https://copr.fedorainfracloud.org):

1. Entre com a conta Fedora e crie o projeto `nautilus-vitrine`, marcando os *chroots* `fedora-45-x86_64` e `fedora-44-x86_64` (e outros que quiser).
2. Em **Packages → New package → SCM**: *Clone URL* `https://github.com/bispov19/nautilus-vitrine`, *Spec file* `packaging/nautilus-vitrine.spec`, *SRPM build method* **make srpm**.
3. Clique em **Rebuild**. Para gerar automaticamente a cada `git push`, ative o *webhook* do GitHub em **Settings → Integrations** do projeto COPR.

Para lançar uma versão nova: aumente `Version` e acrescente uma entrada no `%changelog` do `.spec`, mude `__version__` em `vitrine/__init__.py` para o mesmo número (o `smoke_test.py` avisa se ficarem diferentes), faça o commit e o push.

---

## Solução de problemas

- **Nada mudou no Nautilus:** confira se o `nautilus-python` está instalado (`rpm -q nautilus-python`), feche o Nautilus por completo (`nautilus -q`) e abra de novo.
- **Algo estranho aconteceu:** veja `~/.cache/nautilus-vitrine/vitrine.log`. A linha `janela injetada com sucesso` confirma que a extensão carregou. Se o log apontar que o TabView não foi encontrado, a estrutura do Nautilus mudou: abra uma *issue* com o log.
- **Quer voltar ao Nautilus original:** `./uninstall.sh`.

## Limitações conhecidas

- A extensão usa estruturas internas do Nautilus, que podem mudar a cada versão do GNOME. Foi testada no Nautilus 51.1 (Fedora 45).
- Nas colunas anteriores o menu de clique direito é reduzido. Para o menu completo, use **Mostrar na lista**.
- O zoom dos ícones é uma preferência global do Nautilus. Ao entrar numa pasta com zoom salvo, outras janelas abertas em ícones acompanham.
- Locais especiais (Recentes, Favoritos, Lixeira, Rede, Pesquisa) mantêm o comportamento padrão do Nautilus.
- A coluna **Etiquetas** não é ligada automaticamente: mudar as colunas padrão com a janela aberta derruba o Nautilus 51.1. Ligue em *Colunas visíveis*.
- O menu de clique direito das extensões só aceita texto: as etiquetas aparecem num submenu (com 🔴🟠🟡…), não como a linha de bolinhas do macOS.
- Sem desfoque de fundo ("vidro"): o GNOME não desfoca janelas de aplicativos.
- Agrupar com cabeçalhos ("Hoje", "Ontem"…) só existe na Galeria: a grade nativa do Nautilus não aceita cabeçalhos.
- A barra lateral nativa não tem seções recolhíveis; só a seção Etiquetas da Vitrine recolhe.
- Compartilhar usa e-mail, Bluetooth e o compartilhamento na rede do GNOME: o GNOME não tem um portal de compartilhamento como o do macOS.
- "Duplicar" não existe no GNOME e ficou de fora; "Obter informações" é **Propriedades** (Ctrl+I).
- O menu de histórico do botão ← (clique direito ou toque longo) é do Nautilus e não lista o Meu computador. Escolher um item ali funciona; a Vitrine se realinha sozinha.

## Próximos passos

- [x] Pacote RPM (`make rpm`)
- [ ] Publicação no COPR (`dnf copr enable`)
- [ ] Tocar vídeo e áudio direto no painel
- [ ] Folhear páginas de PDF no painel
- [ ] Dados EXIF da foto (câmera, lente, GPS)
- [x] Tela de personalização do Meu computador
- [ ] Tela de preferências geral (colunas, preview, regras por pasta)
- [x] Estilo Finder, etiquetas coloridas e Galeria
- [ ] Pastas inteligentes / pesquisas salvas na barra lateral
- [ ] Agrupar com cabeçalhos também na visão em grade (precisa de suporte do Nautilus)

Sugestões e *pull requests* são bem-vindos.

## Créditos

A técnica de injeção na janela foi inspirada no projeto **[My Computer for Nautilus](https://github.com/yannmasoch/nautilus-my-computer)**, de Yann Masoch (licença MIT).

## Licença

[MIT](LICENSE)
__VITRINE_ARQUIVO_46__
cat > 'LICENSE' <<'__VITRINE_ARQUIVO_47__'
MIT License

Copyright (c) 2026 Vitrine para Nautilus contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---
Inspired by "My Computer for Nautilus" (https://github.com/yannmasoch/nautilus-my-computer),
Copyright (c) 2026 Yann Masoch, MIT License.
__VITRINE_ARQUIVO_47__
cat > '.gitignore' <<'__VITRINE_ARQUIVO_48__'
__pycache__/
*.pyc
*.tmp
dist/
dist-build.log
gschemas.compiled
__VITRINE_ARQUIVO_48__
cat > 'Makefile' <<'__VITRINE_ARQUIVO_49__'
# Empacotamento local.  Requer: sudo dnf install make rpm-build python3-devel
#
#   make rpm        gera o RPM em dist/
#   make srpm       gera só o SRPM (o mesmo que o COPR usa)
#   make install-rpm  instala o RPM gerado (pede senha)
#   make clean

SPEC    := packaging/nautilus-vitrine.spec
VERSION := $(shell awk '/^Version:/ {print $$2}' $(SPEC))
DIST    := $(CURDIR)/dist
TARBALL := $(DIST)/nautilus-vitrine-$(VERSION).tar.gz
RPMDEFS := --define "_sourcedir $(DIST)" --define "_srcrpmdir $(DIST)" \
           --define "_rpmdir $(DIST)" --define "_builddir $(DIST)/build" \
           --define "_buildrootdir $(DIST)/buildroot"

.PHONY: tarball srpm rpm install-rpm clean

tarball:
	mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=nautilus-vitrine-$(VERSION)/ -o $(TARBALL) HEAD

srpm: tarball
	rpmbuild -bs $(SPEC) $(RPMDEFS)

rpm: tarball
	rpmbuild -bb $(SPEC) $(RPMDEFS)
	@find $(DIST) -name '*.noarch.rpm' -printf 'RPM: %p\n'

install-rpm:
	sudo dnf install -y $$(find $(DIST) -name 'nautilus-vitrine-$(VERSION)-*.noarch.rpm' | head -1)

clean:
	rm -rf $(DIST)
__VITRINE_ARQUIVO_49__
mkdir -p "packaging"
cat > 'packaging/nautilus-vitrine.spec' <<'__VITRINE_ARQUIVO_50__'
%global extdir %{_datadir}/nautilus-python/extensions

Name:           nautilus-vitrine
Version:        0.4.0
Release:        1%{?dist}
Summary:        Finder-style look, column and gallery views, tags and preview pane for GNOME Files

License:        MIT
URL:            https://github.com/bispov19/nautilus-vitrine
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  glib2

Requires:       nautilus >= 50
Requires:       nautilus-python >= 4
Requires:       python3-gobject
Requires:       gtk4
Requires:       libadwaita
Recommends:     gnome-desktop4
Recommends:     sushi

%description
Vitrine adds three Finder-inspired features to GNOME Files (Nautilus 50/51):

 * Column view: parent folders are shown as columns on the left while the
   current folder stays in Nautilus' own list view, so context menus, rename,
   drag and drop, undo, scripts and other extensions keep working.
 * Preview pane: images (fast loading with cache and prefetch), text, video
   and PDF thumbnails, folder contents and file details next to the list.
 * Per-folder views: each folder remembers list, icons, large icons or
   columns, including the icon zoom; photo folders open in large icons.

%prep
%autosetup -n %{name}-%{version}

%build
# Python puro: nada para compilar.

%install
install -d %{buildroot}%{extdir}/vitrine
install -p -m 0644 nautilus-vitrine.py %{buildroot}%{extdir}/
install -p -m 0644 vitrine/*.py %{buildroot}%{extdir}/vitrine/
install -d %{buildroot}%{extdir}/vitrine/assets
install -p -m 0644 vitrine/assets/* %{buildroot}%{extdir}/vitrine/assets/
install -d %{buildroot}%{extdir}/vitrine/schemas
install -p -m 0644 vitrine/schemas/*.gschema.xml %{buildroot}%{extdir}/vitrine/schemas/
glib-compile-schemas --strict %{buildroot}%{extdir}/vitrine/schemas
%py_byte_compile %{python3} %{buildroot}%{extdir}/vitrine

%files
%license LICENSE
%doc README.md
%{extdir}/nautilus-vitrine.py
%{extdir}/vitrine/

%changelog
* Tue Nov 24 2026 Vinicius Bispo - 0.4.0-1
- Estilo Finder (padrão) com volta ao Nautilus padrão; preferências em GSettings
- Etiquetas coloridas (user.xdg.tags): menu, barra, barra lateral, Propriedades
- Galeria (Ctrl+4) com agrupamento por data, tipo, tamanho e etiqueta
- Dimensões das imagens na grade, barra de caminho e barra de status opcionais
- Ctrl+I abre Propriedades

* Sun Nov 22 2026 Vinicius Bispo - 0.3.0-1
- Voltar/Avançar levam de volta ao Meu computador (histórico próprio por aba)
- Menu ☰ na linha "Meu computador" da barra lateral (Personalizar e Sobre)
- Página "Sobre" com logo, versão, links e créditos
- Logo e ícone simbólico da Vitrine

* Wed Nov 11 2026 Vinicius Bispo - 0.2.0-1
- Página "Meu computador" com pastas, discos e uso de espaço
- Aviso ao conectar pen drive, HD externo ou cartão, com botão Abrir
- Todos os locais da barra lateral (Recentes, Favoritos, Rede, Lixeira, marcadores)
- Personalização (seções, itens, entrada na barra lateral) e opção de abrir direto nele

* Wed Nov 11 2026 Vinicius Bispo - 0.1.0-1
- Primeira versão: modo Colunas, painel de pré-visualização e visualização por pasta
__VITRINE_ARQUIVO_50__
mkdir -p ".copr"
cat > '.copr/Makefile' <<'__VITRINE_ARQUIVO_51__'
# Usado pelo COPR (método "make srpm"): gera o SRPM direto do repositório git.
# O COPR chama:  make -f .copr/Makefile srpm outdir=<pasta> spec=<arquivo .spec>
SPEC := packaging/nautilus-vitrine.spec

srpm:
	dnf -y install git rpm-build
	git config --global --add safe.directory '*'
	$(eval VERSION := $(shell awk '/^Version:/ {print $$2}' $(SPEC)))
	mkdir -p $(outdir)
	git archive --format=tar.gz --prefix=nautilus-vitrine-$(VERSION)/ \
		-o $(outdir)/nautilus-vitrine-$(VERSION).tar.gz HEAD
	rpmbuild -bs $(SPEC) \
		--define "_sourcedir $(outdir)" \
		--define "_srcrpmdir $(outdir)"
__VITRINE_ARQUIVO_51__

chmod +x install.sh uninstall.sh
echo "Projeto criado em $TARGET"

if [[ "$INSTALL" == 1 ]]; then
  ./install.sh
else
  echo
  echo "Próximos passos:"
  echo "  cd \"$TARGET\" && ./install.sh        # instala e reinicia o Nautilus"
  echo "  code \"$TARGET\"                      # abre no VS Code (Ctrl+Shift+B = instalar em modo dev)"
fi
