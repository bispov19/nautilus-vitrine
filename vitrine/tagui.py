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
