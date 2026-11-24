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
