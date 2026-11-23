"""Testes das etiquetas (user.xdg.tags) em arquivos temporários.

    python3 tools/test_tags.py

Precisa de um sistema de arquivos com atributos estendidos de usuário (ext4, btrfs,
xfs e o tmpfs dos kernels recentes têm).
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from vitrine import tags  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(f"{'PASSOU' if ok else 'FALHOU'}: {name}" + (f"  ({detail})" if not ok and detail else ""))


class FakeCfg:
    def __init__(self):
        self.data = {"tags": list(tags.DEFAULT_TAGS)}

    def get(self, k):
        return self.data.get(k)

    def set(self, k, v):
        self.data[k] = v


def main() -> int:
    root = tempfile.mkdtemp(prefix="vitrine-tags-")
    a, b = os.path.join(root, "a.txt"), os.path.join(root, "b b.jpg")
    sub = os.path.join(root, "pasta")
    os.makedirs(os.path.join(sub, ".oculta"))
    hidden = os.path.join(sub, ".oculta", "c.txt")
    for p in (a, b, hidden):
        open(p, "w").close()
    try:
        os.setxattr(a, "user.test", b"1")
    except OSError as err:
        print(f"PULADO: este sistema de arquivos não aceita atributos estendidos ({err})")
        return 0
    ua, ub = tags.path_to_uri(a), tags.path_to_uri(b)

    notified = []
    store = tags.TagStore(FakeCfg(), index_path=os.path.join(root, "idx.json"),
                          on_files_changed=notified.extend)
    check("6 etiquetas padrão com os nomes em português",
          store.names() == ["Vermelho", "Laranja", "Amarelo", "Verde", "Azul", "Roxo"])

    applied = store.toggle([ua, ub], "Vermelho")
    check("aplicar etiqueta grava user.xdg.tags", applied and tags.read_tags(a) == ["Vermelho"]
          and tags.read_tags(b) == ["Vermelho"], str(tags.read_tags(a)))
    check("o Nautilus é avisado dos arquivos alterados", set(notified) == {ua, ub})
    store.add([ua], "Azul")
    check("várias etiquetas por arquivo (formato separado por vírgula)",
          os.getxattr(a, tags.XATTR) == b"Vermelho,Azul")
    check("arquivos com a etiqueta (índice)", store.files_with("Vermelho") == [ua, ub],
          str(store.files_with("Vermelho")))

    applied = store.toggle([ua, ub], "Vermelho")
    check("se todos já têm, alternar tira de todos", not applied and tags.read_tags(a) == ["Azul"]
          and tags.read_tags(b) == [])

    store.add([ua], "Verde")
    check("renomear etiqueta atualiza os arquivos", store.rename("Verde", "Projetos")
          and tags.read_tags(a) == ["Azul", "Projetos"] and "Projetos" in store.names(),
          str(tags.read_tags(a)))
    store.recolor("Projetos", "purple")
    check("trocar a cor", store.color_of("Projetos") == "purple")
    store.delete("Azul")
    check("apagar etiqueta tira dos arquivos", tags.read_tags(a) == ["Projetos"]
          and "Azul" not in store.names())
    check("nome repetido ou vazio não é criado", not store.create("Projetos")
          and not store.create("  ") and store.create("Viagem, 2026", "blue")
          and "Viagem  2026" in store.names())

    store.clear([ua])
    check("remover todas as etiquetas apaga o atributo",
          tags.read_tags(a) == [] and store.files_with("Projetos") == [])

    # Etiquetas postas por outro programa aparecem depois de uma busca
    os.setxattr(b, tags.XATTR, b"Laranja")
    os.setxattr(hidden, tags.XATTR, b"Laranja")
    other = tags.TagStore(FakeCfg(), index_path=os.path.join(root, "idx2.json"))
    found = other.scan(root)
    check("busca acha etiquetas de outros programas (pula pastas ocultas)",
          found == 1 and other.files_with("Laranja") == [ub], f"{found} {other.files_with('Laranja')}")
    os.remove(b)
    check("arquivo apagado sai do índice", other.files_with("Laranja") == [])

    print(f"\n{sum(results)}/{len(results)} verificações passaram")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
