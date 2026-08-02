#!/usr/bin/env python3
"""Turn the native frames of an Android ANR/crash dump into function names.

Androids Beendigungs-Historie liefert bei einem ANR einen Thread-Dump, und
`ExitInfoRepository` legt dessen Haupt-Thread-Abschnitt in `error_reports`
ab (Issue #147). Die Frames darin sehen so aus:

    native: #00 pc 00984478  base.apk (offset 9c0000)

Ohne Übersetzung ist das eine Sackgasse — genau daran ist die Auswertung in
Issue #151 zunächst gescheitert. Sie ist aber keine: Native Bibliotheken
liegen unkomprimiert und seitenausgerichtet in der APK, `(offset …)` ist
ihre Position darin, und Flutter veröffentlicht zu jedem Engine-Build eine
ungestrippte `libflutter.so`. Aus einem Release-Tag und dem Dump lässt sich
der Name also nachträglich herleiten, ohne dass wir vorher irgendetwas
aufheben mussten.

    python3 tool/symbolize_anr.py v1.32.0 dump.txt
    gh issue view 151 | python3 tool/symbolize_anr.py v1.32.0
    python3 tool/symbolize_anr.py --self-test

Grenze, die man kennen muss: `libapp.so` — unser eigener Dart-Code — trägt
im Release-Build gar keine Funktionssymbole, nur die vier Snapshot-Blobs.
Frames dort bleiben unbenannt, solange der Build nicht mit
`--split-debug-info` gebaut wird (dann landet die Zuordnung in einer
Seitendatei). Für Engine-Frames braucht es das nicht.
"""
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import urllib.request
import zipfile

# Wo heruntergeladene APKs und Symbol-Archive liegen bleiben: eine APK ist
# ~70 MB, ein Symbolarchiv ~40 MB, und beim Nachbohren ruft man das Skript
# mehrmals mit demselben Tag auf.
CACHE_DIR = os.path.join(
    os.environ.get("TMPDIR", "/tmp"), "pilzbuddy-symbolize")

ENGINE_VERSION_URL = (
    "https://raw.githubusercontent.com/flutter/flutter/{flutter}/"
    "bin/internal/engine.version")
SYMBOLS_URL = (
    "https://storage.googleapis.com/flutter_infra_release/flutter/{engine}/"
    "{platform}/symbols.zip")

# `pc <hex>` … `(offset <hex>)`. Beide Schreibweisen kommen vor, mit und
# ohne 0x, mit vollem /data/app-Pfad oder nur "base.apk".
FRAME_RE = re.compile(
    r"pc\s+(?:0x)?([0-9a-fA-F]+)\s+(\S+)(?:\s+\(offset\s+(?:0x)?([0-9a-fA-F]+)\))?")


class Frame:
    def __init__(self, pc: int, path: str, offset: int | None):
        self.pc = pc
        self.path = path
        self.offset = offset

    def __repr__(self) -> str:
        off = "–" if self.offset is None else f"0x{self.offset:x}"
        return f"Frame(pc=0x{self.pc:x}, path={self.path}, offset={off})"


def parse_frames(dump: str) -> list[Frame]:
    """Alle nativen Frames eines Dumps, in Dump-Reihenfolge.

    Bewusst zeilenweise und tolerant: Der Text kommt aus einem
    GitHub-Kommentar, aus `gh issue view` oder direkt aus der Datenbank und
    ist mal eingerückt, mal in einen Codeblock gepackt.
    """
    frames = []
    for line in dump.splitlines():
        match = FRAME_RE.search(line)
        if not match:
            continue
        pc, path, offset = match.groups()
        frames.append(
            Frame(int(pc, 16), path, int(offset, 16) if offset else None))
    return frames


def apk_libraries(apk_path: str) -> list[tuple[int, str, int]]:
    """(Datei-Offset, Name, Größe) jeder .so in der APK, nach Offset sortiert.

    Der Offset ist der der *Daten*, nicht der des lokalen Kopfes — nur
    ersterer steht im ANR-Dump. Er ergibt sich aus dem lokalen Kopf, dessen
    Namens- und Extrafeld-Längen von denen im zentralen Verzeichnis
    abweichen dürfen (die Ausrichtung auf Seitengrenzen steckt genau dort).
    """
    entries = []
    with zipfile.ZipFile(apk_path) as archive, open(apk_path, "rb") as raw:
        for info in archive.infolist():
            if not info.filename.endswith(".so"):
                continue
            raw.seek(info.header_offset)
            header = struct.unpack("<IHHHHHIIIHH", raw.read(30))
            name_len, extra_len = header[9], header[10]
            data = info.header_offset + 30 + name_len + extra_len
            entries.append((data, info.filename, info.file_size))
    return sorted(entries)


def library_for_offset(libraries, offset: int) -> tuple[str, int] | None:
    """(Name, Größe) der Bibliothek, die an genau diesem Offset beginnt."""
    for data_offset, name, size in libraries:
        if data_offset == offset:
            return name, size
    return None


def elf_function_symbols(data: bytes) -> list[tuple[int, int, str]]:
    """(Adresse, Größe, Name) aller Funktionssymbole, nach Adresse sortiert.

    Eigener Mini-Parser statt llvm-nm: Auf einem Mac liegt kein ELF-fähiges
    nm, und die Alternative wäre eine NDK-Installation für 60 Zeilen.
    """
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError("not a 64-bit ELF file")
    (shoff,) = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    sections = []
    for i in range(shnum):
        fields = struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize)
        sections.append({"name": fields[0], "off": fields[4],
                         "size": fields[5], "link": fields[6]})
    shstr = sections[shstrndx]

    def section_name(offset: int) -> str:
        start = shstr["off"] + offset
        return data[start:data.index(b"\0", start)].decode()

    by_name = {section_name(s["name"]): s for s in sections}
    symtab = by_name.get(".symtab") or by_name.get(".dynsym")
    if symtab is None:
        return []
    strtab = sections[symtab["link"]]
    symbols = []
    for i in range(symtab["size"] // 24):
        name, info, _other, _shndx, value, size = struct.unpack_from(
            "<IBBHQQ", data, symtab["off"] + i * 24)
        # STT_FUNC; Adresse 0 heißt „nicht in dieser Datei definiert".
        if value and (info & 0xF) == 2:
            start = strtab["off"] + name
            symbols.append((value, size,
                            data[start:data.index(b"\0", start)]
                            .decode(errors="replace")))
    symbols.sort()
    return symbols


def containing_symbol(symbols, address: int):
    """Das Symbol, dessen [Adresse, Adresse+Größe) die Adresse enthält.

    Nur echte Treffer: Das nächstgelegene Symbol *davor* zurückzugeben wäre
    bequem und irreführend — in einer gestrippten Bibliothek liegt das
    hunderte Kilobyte entfernt und benennt eine völlig andere Funktion.
    """
    low, high = 0, len(symbols) - 1
    best = None
    while low <= high:
        mid = (low + high) // 2
        if symbols[mid][0] <= address:
            best = symbols[mid]
            low = mid + 1
        else:
            high = mid - 1
    if best and best[0] <= address < best[0] + max(best[1], 1):
        return best
    return None


def demangle(name: str) -> str:
    """Itanium-C++-Namen lesbar machen, wenn ein c++filt zur Hand ist.

    Apples c++filt erwartet einen zusätzlichen Unterstrich, GNU/LLVM nicht —
    deshalb beide Formen probieren, statt auf eine Plattform zu wetten.
    """
    if not shutil.which("c++filt"):
        return name
    for candidate in (name, "_" + name):
        try:
            out = subprocess.run(["c++filt", candidate], capture_output=True,
                                 text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return name
        if out and out != candidate:
            return out
    return name


def _download(url: str, target: str) -> str:
    if os.path.exists(target):
        return target
    os.makedirs(os.path.dirname(target), exist_ok=True)
    print(f"  ↓ {url}", file=sys.stderr)
    with urllib.request.urlopen(url) as response, \
            open(target + ".part", "wb") as out:
        shutil.copyfileobj(response, out)
    os.replace(target + ".part", target)
    return target


def fetch_apk(tag: str) -> str:
    target = os.path.join(CACHE_DIR, tag, "app.apk")
    if os.path.exists(target):
        return target
    os.makedirs(os.path.dirname(target), exist_ok=True)
    subprocess.run(["gh", "release", "download", tag, "-p", "*.apk",
                    "-D", os.path.dirname(target), "--clobber"], check=True)
    downloaded = [f for f in os.listdir(os.path.dirname(target))
                  if f.endswith(".apk")]
    if not downloaded:
        raise SystemExit(f"No APK asset on release {tag}.")
    os.replace(os.path.join(os.path.dirname(target), downloaded[0]), target)
    return target


def flutter_version_at(tag: str) -> str:
    """Die in CI gepinnte Flutter-Version, wie sie zu diesem Tag galt.

    Aus dem Workflow im Tag selbst statt aus einer eigenen Notiz: Die Datei
    hat den Build gemacht, sie kann also nicht danebenliegen.
    """
    workflow = subprocess.run(
        ["git", "show", f"{tag}:.github/workflows/release.yml"],
        capture_output=True, text=True, check=True).stdout
    match = re.search(r"flutter-version:\s*(\S+)", workflow)
    if not match:
        raise SystemExit(f"No pinned flutter-version in release.yml at {tag}.")
    return match.group(1)


def engine_symbols(flutter_version: str, platform: str) -> list:
    engine = urllib.request.urlopen(
        ENGINE_VERSION_URL.format(flutter=flutter_version)).read().decode().strip()
    print(f"  Flutter {flutter_version} → engine {engine}", file=sys.stderr)
    archive = _download(
        SYMBOLS_URL.format(engine=engine, platform=platform),
        os.path.join(CACHE_DIR, "engine", engine, f"{platform}.zip"))
    with zipfile.ZipFile(archive) as zf:
        return elf_function_symbols(zf.read("libflutter.so"))


# Welche Engine-Variante zu welcher ABI in der APK gehört.
PLATFORM_FOR_ABI = {
    "arm64-v8a": "android-arm64-release",
    "armeabi-v7a": "android-arm-release",
    "x86_64": "android-x64-release",
}


def symbolize(tag: str, dump: str) -> int:
    frames = parse_frames(dump)
    if not frames:
        print("No native frames found in the input.", file=sys.stderr)
        return 1

    apk = fetch_apk(tag)
    libraries = apk_libraries(apk)
    symbol_cache: dict[str, list] = {}
    unresolved = 0

    for index, frame in enumerate(frames):
        print(f"#{index:02d} pc 0x{frame.pc:x}  {frame.path}", end="")
        if frame.offset is None:
            print("  → no APK offset in this frame, cannot map to a library")
            unresolved += 1
            continue
        print(f" (offset 0x{frame.offset:x})")

        hit = library_for_offset(libraries, frame.offset)
        if hit is None:
            print("      no library starts at that offset in this APK — "
                  "wrong release tag?")
            unresolved += 1
            continue
        name, size = hit
        abi = name.split("/")[1] if "/" in name else "?"
        print(f"      library: {name} ({size:,} bytes)")
        if frame.pc >= size:
            print("      pc lies beyond the end of that library — "
                  "the offset does not belong to this frame")
            unresolved += 1
            continue

        if name.endswith("libflutter.so"):
            platform = PLATFORM_FOR_ABI.get(abi)
            if platform is None:
                print(f"      no engine symbols known for ABI {abi}")
                unresolved += 1
                continue
            if platform not in symbol_cache:
                symbol_cache[platform] = engine_symbols(
                    flutter_version_at(tag), platform)
            symbols = symbol_cache[platform]
        else:
            if name not in symbol_cache:
                with zipfile.ZipFile(apk) as zf:
                    symbol_cache[name] = elf_function_symbols(zf.read(name))
            symbols = symbol_cache[name]

        if not symbols:
            print("      that library ships without function symbols "
                  "(libapp.so needs --split-debug-info at build time)")
            unresolved += 1
            continue

        found = containing_symbol(symbols, frame.pc)
        if found is None:
            print("      no symbol covers this address")
            unresolved += 1
            continue
        address, symbol_size, symbol = found
        print(f"      → {demangle(symbol)}")
        print(f"        (0x{address:x} + 0x{symbol_size:x}, "
              f"hit at +0x{frame.pc - address:x})")

    if unresolved:
        print(f"\n{unresolved} of {len(frames)} frames unresolved.",
              file=sys.stderr)
    return 0


def self_test() -> None:
    """Parsing und Symbolsuche ohne Netz, ohne APK, ohne gh."""
    dump = """
    "main" prio=5 tid=1 Native
      | group="main" sCount=1 ucsCount=0 flags=1
      native: #00 pc 00984478  base.apk (offset 9c0000)
      native: #01 pc 00984c2c  /data/app/~~abc==/base.apk (offset 0x9c0000)
      native: #02 pc 0x00012345  /system/lib64/libc.so
      at some.java.Frame(Unknown Source:0)
    """
    frames = parse_frames(dump)
    assert len(frames) == 3, frames
    assert frames[0].pc == 0x984478 and frames[0].offset == 0x9C0000, frames[0]
    # Mit und ohne 0x, kurzer und langer Pfad — dieselbe Bibliothek.
    assert frames[1].offset == frames[0].offset, frames[1]
    # Ein Frame ohne (offset …) darf nicht stillschweigend geschluckt werden,
    # sonst verschiebt sich die Nummerierung gegenüber dem Dump.
    assert frames[2].offset is None, frames[2]
    print(f"parse ok: {frames}")

    libraries = [(0x98000, "lib/arm64-v8a/libapp.so", 9438128),
                 (0x9C0000, "lib/arm64-v8a/libflutter.so", 11316480)]
    assert library_for_offset(libraries, 0x9C0000)[0].endswith("libflutter.so")
    assert library_for_offset(libraries, 0x98000)[0].endswith("libapp.so")
    # Kein „nächstgelegenes" Raten: ein unbekannter Offset ist unbekannt.
    assert library_for_offset(libraries, 0x9C0001) is None
    print("offset → library ok")

    symbols = [(0x1000, 0x100, "_ZN1A1bEv"), (0x2000, 0x40, "_ZN1C1dEv"),
               (0x3000, 0, "_ZN1E1fEv")]
    assert containing_symbol(symbols, 0x1000)[2] == "_ZN1A1bEv"
    assert containing_symbol(symbols, 0x10FF)[2] == "_ZN1A1bEv"
    # Genau hinter dem Ende: gehört nicht mehr dazu, auch wenn es das
    # nächstgelegene Symbol davor ist.
    assert containing_symbol(symbols, 0x1100) is None
    assert containing_symbol(symbols, 0x2039)[2] == "_ZN1C1dEv"
    assert containing_symbol(symbols, 0x2040) is None
    # Größe 0 kommt vor; ein solches Symbol deckt genau seine Adresse ab.
    assert containing_symbol(symbols, 0x3000)[2] == "_ZN1E1fEv"
    assert containing_symbol(symbols, 0x3001) is None
    assert containing_symbol(symbols, 0x0FFF) is None
    print("symbol lookup ok")

    demangled = demangle("_ZN4dart14MarkingVisitor22ProcessOldMarkingStackEl")
    print(f"demangle: {demangled}")
    print("\nself-test passed (no network, nothing downloaded)")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) > 1:
        tag = sys.argv[1]
        if len(sys.argv) > 2:
            with open(sys.argv[2], encoding="utf-8") as f:
                text = f.read()
        else:
            text = sys.stdin.read()
        sys.exit(symbolize(tag, text))
    else:
        print(__doc__)
        sys.exit(2)
