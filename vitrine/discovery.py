"""Descoberta automática de pastas: olha uma amostra dos arquivos (tipo MIME pela
extensão, sem ler o conteúdo) e diz se a pasta é de mídia, de documentos ou mista.

    "media"      maioria de fotos/vídeos      → ícones extra grandes
    "documents"  maioria de outros arquivos   → lista
    None         mista, vazia ou poucos itens → visualização padrão

O resultado fica em cache e vale enquanto a pasta não mudar (data de modificação).
Escolhas manuais feitas nesta sessão têm prioridade sobre a descoberta."""

from __future__ import annotations

from gi.repository import Gio, GLib

SAMPLE = 200          # itens lidos no máximo, mesmo em pastas enormes
MIN_FILES = 4         # menos arquivos que isso do tipo predominante → sem palpite
CACHE_MAX = 500
_ATTRS = "standard::name,standard::type,standard::fast-content-type,standard::is-hidden"

_CACHE: dict[str, tuple[int, str | None]] = {}   # uri → (mtime, tipo)
_MANUAL: dict[str, tuple[str, str | None]] = {}  # uri → (modo, zoom) escolhidos à mão


def is_media_type(content_type: str) -> bool:
    return content_type.startswith(("image/", "video/"))


def classify(content_types: list[str], ratio: float) -> str | None:
    """Tipo predominante entre os arquivos amostrados (só arquivos, sem pastas)."""
    total = len(content_types)
    if total == 0:
        return None
    media = sum(1 for t in content_types if is_media_type(t))
    other = total - media
    if media >= MIN_FILES and media / total >= ratio:
        return "media"
    if other >= MIN_FILES and other / total >= ratio:
        return "documents"
    return None


def _fast_type(info: Gio.FileInfo) -> str:
    ctype = info.get_attribute_string("standard::fast-content-type")
    if not ctype or ctype == "application/x-zerosize":  # arquivo vazio: vale a extensão
        ctype, _uncertain = Gio.content_type_guess(info.get_name(), None)
    return ctype or ""


def _store(uri: str, mtime: int, kind: str | None) -> None:
    if len(_CACHE) >= CACHE_MAX:
        _CACHE.pop(next(iter(_CACHE)))
    _CACHE[uri] = (mtime, kind)


def discover(uri: str, ratio: float, callback) -> None:
    """Assíncrono: chama `callback(tipo)` com "media", "documents" ou None."""
    gfile = Gio.File.new_for_uri(uri)
    mtime = [None]

    def on_info(f, res):
        try:
            mtime[0] = f.query_info_finish(res).get_attribute_uint64("time::modified")
        except GLib.Error:
            mtime[0] = None
        hit = _CACHE.get(uri)
        if hit is not None and mtime[0] is not None and hit[0] == mtime[0]:
            callback(hit[1])
            return
        f.enumerate_children_async(_ATTRS, Gio.FileQueryInfoFlags.NONE,
                                   GLib.PRIORITY_DEFAULT, None, on_enum)

    def on_enum(f, res):
        try:
            en = f.enumerate_children_finish(res)
        except GLib.Error:
            callback(None)
            return
        en.next_files_async(SAMPLE, GLib.PRIORITY_DEFAULT, None, on_files)

    def on_files(en, res):
        try:
            infos = en.next_files_finish(res)
        except GLib.Error:
            infos = []
        en.close_async(GLib.PRIORITY_LOW, None, None)
        types = [_fast_type(i) for i in infos
                 if i.get_file_type() == Gio.FileType.REGULAR and not i.get_is_hidden()]
        kind = classify(types, ratio)
        if mtime[0] is not None:
            _store(uri, mtime[0], kind)
        callback(kind)

    gfile.query_info_async("time::modified", Gio.FileQueryInfoFlags.NONE,
                           GLib.PRIORITY_DEFAULT, None, on_info)


# ── escolhas manuais (valem nesta sessão, mesmo sem "lembrar por pasta") ──
def remember_manual(uri: str, mode: str, zoom: str | None) -> None:
    _MANUAL[uri] = (mode, zoom)


def manual_choice(uri: str) -> tuple[str, str | None] | None:
    return _MANUAL.get(uri)


def forget_manual(uri: str) -> None:
    _MANUAL.pop(uri, None)
