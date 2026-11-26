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
        # Barra compacta em janela estreita: confere a largura a cada quadro (só compara
        # um número; o callback sai junto com a camada Finder).
        tick = header.add_tick_callback(self._on_tick)
        self._later(lambda: header.remove_tick_callback(tick))
        self._later(lambda: self.win.remove_css_class("vitrine-compact"))
        if switcher is not None:
            self._connect(switcher, "notify::visible-child-name",
                          lambda *_a: self.toolbar and self.toolbar.sync_title())
            self._later(lambda s=switcher: s.set_visible(True))

    def _on_tick(self, _widget, _clock) -> bool:
        if self.toolbar is not None:
            self.toolbar.set_compact(self.win.get_width() < self.toolbar.COMPACT_BELOW)
        return True

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

