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
