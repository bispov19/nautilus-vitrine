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
