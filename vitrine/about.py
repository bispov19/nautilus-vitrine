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
