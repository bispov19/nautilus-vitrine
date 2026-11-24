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
