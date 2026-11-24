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
