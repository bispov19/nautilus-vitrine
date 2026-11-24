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
