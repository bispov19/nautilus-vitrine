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

    # ── modo Colunas: o nome tem prioridade ──
    deep = {}
    long_names = ("Proposta_Vegah_Salon_2026 (1).pdf", "Relatório de atividades do semestre.txt")

    def name_labels():
        cv = ctl._native_columnview()
        if cv is None:
            return []
        return [w for w in util.walk(cv) if isinstance(w, Gtk.Label) and w.get_mapped()
                and w.get_label() in long_names]

    def names_readable():
        labels = name_labels()
        return len(labels) == len(long_names) and not any(
            lb.get_layout().is_ellipsized() for lb in labels), [
            (lb.get_label(), lb.get_width(), lb.get_layout().is_ellipsized()) for lb in labels]

    @step
    def c1():
        root = tempfile.mkdtemp(prefix="vitrine-selftest-colunas-")
        path = root
        for name in ("Documentos de exemplo", "02_Estudos e cursos", "01_Cursos_LIVRES online",
                     "Programação para iniciantes"):
            path = os.path.join(path, name)
            os.makedirs(path)
        for name in long_names:
            open(os.path.join(path, name), "w").close()
        deep.update(root=root, leaf=Gio.File.new_for_path(path).get_uri(),
                    maximized=ctl.win.is_maximized(),
                    size=(ctl.win.get_width(), ctl.win.get_height()))
        ctl.set_preview_visible(True)
        ctl.navigate(deep["leaf"])

    @step
    def c2():
        ctl.user_set_mode("columns")

    @step
    def c3():
        ok, info = names_readable()
        check("colunas (janela grande): nome legível com o painel ligado", ok,
              f"{info} colunas={len(ctl.strip.columns)} painel={ctl.preview.get_visible()} "
              f"largura={ctl.paned.get_width()}")
        shot("colunas-janela-grande")
        ctl.win.unmaximize()
        ctl.win.set_default_size(860, 640)

    @step
    def c4():
        ok, info = names_readable()
        check("colunas (janela pequena): nome legível; painel cede espaço",
              ok and ctl.paned.get_width() < 900, f"{info} largura={ctl.paned.get_width()} "
              f"painel={ctl.preview.get_visible()} faixa={ctl.strip.visible_count}")
        check("colunas: recolher o painel não muda a preferência do usuário",
              bool(ctl.cfg.get("preview_visible")))
        header = ctl.style.header if ctl.style is not None else None
        hmin = header.measure(Gtk.Orientation.HORIZONTAL, -1)[0] if header is not None else 0
        sidebar_w = ctl.win.get_width() - (header.get_parent().get_width() if header is not None else 0)
        check("Finder: barra de ferramentas cabe na janela estreita (modo compacto)",
              header is None or (ctl.win.has_css_class("vitrine-compact")
                                 and hmin + sidebar_w <= ctl.win.get_width() + 1),
              f"barra mín={hmin} lateral={sidebar_w} janela={ctl.win.get_width()}")
        shot("colunas-janela-pequena")
        if deep["maximized"]:
            ctl.win.maximize()
        else:
            ctl.win.set_default_size(*deep["size"])

    @step
    def c5():
        ok, info = names_readable()
        check("colunas (janela grande de novo): painel volta sozinho",
              ok and ctl.preview.get_visible() and not ctl._preview_auto_hidden,
              f"{info} painel={ctl.preview.get_visible()} largura={ctl.paned.get_width()}")
        ctl.cfg.set("columns_prioritize_names", False)

    @step
    def c6():
        cv = ctl._native_columnview()
        restored = cv is not None and not getattr(cv, "_vitrine_hidden", None)
        check("opção Priorizar nomes desligada: colunas e painel como antes",
              restored and ctl.strip.visible_count is None and ctl.preview.get_visible())
        ctl.cfg.set("columns_prioritize_names", True)
        ctl.user_set_mode("list")
        cfg.forget(deep["leaf"])
        discovery.forget_manual(deep["leaf"])
        ctl.navigate(home)

    @step
    def c7():
        shutil.rmtree(deep["root"], ignore_errors=True)

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
