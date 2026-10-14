# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Check attribution, English operator copy and the publication boundary."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

CODE = {".cpp", ".h", ".hpp", ".qml", ".py", ".ps1", ".sh", ".fpp", ".gd", ".rc", ".cmd", ".yml"}
TEXT = CODE | {".md", ".txt", ".json", ".ini", ".godot", ".tscn", ".svg", ".qrc", ".in"}
GENERATED = {"__pycache__", "build-artifacts", ".pytest_cache", ".godot"}
FORBIDDEN_DIRS = GENERATED | {"private", "build", "workspace", ".venv", "venv", ".idea", ".vscode", "previews", ".git"}
FORBIDDEN_SUFFIXES = {".blend", ".blend1", ".blend2", ".pdb", ".obj", ".o", ".lib", ".a", ".ilk", ".exp", ".map", ".dmp", ".log", ".sqlite", ".bak", ".tmp", ".orig", ".rej", ".import", ".pyc", ".lnk", ".pem", ".key", ".p12", ".pfx"}
SDK_FILES = {"sdk/windows-mingw/SiliconLogiX.OrbitLab.Core.dll", "sdk/windows-mingw/SiliconLogiX.OrbitLab.Core.dll.a", "sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so"}
LOCAL_PATH = re.compile(rb"(?:[A-Za-z]:[\\/]Users[\\/][^\s\x00]+|/mnt/[a-z]/Users/[^\s\x00]+|/home/(?!\$)[A-Za-z0-9_.-]+/)", re.I)
SECRETS = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
           re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|AKIA[A-Z0-9]{16})\b"),
           re.compile(rb"https?://[^\s/:]+:[^\s/@]+@[^\s]+")]
INTERNAL_NOTE = re.compile(r"^\s*(?://|#|/\*|\*|<!--)?\s*(?:TODO|FIXME|HACK|INTERNAL NOTE|NOTE TO CODEX)\b", re.M)
ITALIAN = re.compile(r"[àèìòù]|\b(?:avvia|avvio|avviata|missione|obiettivo|obiettivi|comando|comandi|sequenza|sequenze|sensore|batteria|puntamento|acquisizione|disponibile|insufficiente|aggiorna|registrazioni|registrazione|esegui|esecuzione|finestra|rapporto|apri|chiudi|mostra|scegli|seleziona|invia|riprova|errore|orbita|memoria|contatto|strumento|annulla|elimina|salva|carica|verifica|moduli|servizio|collegato|nominale|sospeso|temporaneamente|attivo|attiva|spento|assente|prova|durata|argomenti|risultato|riprendi|concludi|abilitato|disabilitato|riserva|rinviata|prepara|pannelli|segnalatore|latitudine|longitudine|impostazioni|confronto|confronti|confronta|ispezione|attuatore|manovra|manovre|modalità|iniziale|nessun|nessuna|riproduci|riproduzione|nuovo|nuova|interrompi|completato|completata|necessario|passo|gradi|radianti|produzione|consumi|ricevuti|ricevute|trasferimento|allineamento|inattiva|interrotta|spinta|validazione|interno|sviluppo|telemetria)\b", re.I)
LITERALS = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')


def publication_errors(relative, data, github=False):
    """Evaluate contents independently of ignore rules and tracked status."""
    name = relative.as_posix()
    errors = []
    approved_binary = name in SDK_FILES or name.startswith("runtime/godot/") and relative.suffix == ".exe"
    if any(part.lower() in FORBIDDEN_DIRS for part in relative.parts) or relative.suffix.lower() in FORBIDDEN_SUFFIXES and not approved_binary:
        errors.append(f"Private/generated artifact: {name}")
    if relative.name in {"CODEX_HANDOFF.md", "AGENTS.md"} or relative.name.startswith(".env"):
        errors.append(f"Internal configuration: {name}")
    if github and (approved_binary or "sdk" in relative.parts or "runtime" in relative.parts or relative.suffix.lower() in {".exe", ".dll", ".so", ".elf", ".bin", ".zip"}):
        errors.append(f"Binary/runtime content excluded from GitHub source: {name}")
    if LOCAL_PATH.search(data) or LOCAL_PATH.search(data.replace(b"\x00", b"")):
        errors.append(f"Developer-specific absolute path: {name}")
    if any(pattern.search(data) for pattern in SECRETS):
        errors.append(f"Possible credential or private key: {name}")
    if github and len(data) >= 100 * 1024 * 1024:
        errors.append(f"File exceeds GitHub's regular-file limit: {name}")
    if relative.suffix in TEXT or relative.name.startswith(".") or relative.name == "CMakeLists.txt":
        text = data.decode("utf-8-sig", errors="replace")
        if INTERNAL_NOTE.search(text):
            errors.append(f"Unfinished/internal note: {name}")
        if re.search(r"\bstruct\s+SlxMission\s*\{", text):
            errors.append(f"Proprietary mission implementation: {name}")
    return errors


def git_audit(root, github=False):
    """Inspect indexed bytes and historical blobs, including ignored tracked files."""
    errors = []
    if not (root / ".git").exists():
        return {"available": False, "tracked_files": 0, "history_blobs": 0}, errors
    def git(*args, binary=False):
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, check=True)
        return result.stdout if binary else result.stdout.decode("utf-8")
    entries = git("ls-files", "--stage", "-z").split("\0")
    tracked = 0
    for entry in filter(None, entries):
        metadata, name = entry.split("\t", 1)
        mode, oid, stage = metadata.split()
        tracked += 1
        if mode == "120000" or mode == "160000" or stage != "0":
            errors.append(f"Unreviewed Git entry: {name}")
            continue
        errors.extend(publication_errors(Path(name), git("cat-file", "blob", oid, binary=True), github))
    objects = git("rev-list", "--objects", "--all").splitlines()
    historical = 0
    for entry in objects:
        oid, separator, name = entry.partition(" ")
        if not separator or git("cat-file", "-t", oid).strip() != "blob":
            continue
        historical += 1
        errors.extend("History: " + error for error in publication_errors(Path(name), git("cat-file", "blob", oid, binary=True), github))
    return {"available": True, "tracked_files": tracked, "history_blobs": historical}, errors


def audit(root, public=False, github=False, private_reference=None, check_git=False):
    errors, count = [], 0
    root = root.resolve()
    directories = ["src", "qml", "core", "private", "backend", "firmware", "scripts", "tools", "tests", "assets/brand", ".github"]
    files = [path for name in directories for path in (root / name).rglob("*") if path.is_file()]
    files += [root / name for name in ("CMakeLists.txt", "Run-SLX-OrbitLab.cmd", ".clang-format", ".gitignore", ".gitattributes", "resources.qrc")]
    files += list((root / "SLX_OrbitLab_3D/godot").glob("*.gd"))
    files += [root / "SLX_OrbitLab_3D/project.godot"]
    for path in files:
        relative = path.relative_to(root)
        if any(part in GENERATED for part in relative.parts):
            continue
        if path.suffix not in CODE and path.name not in ("CMakeLists.txt", ".clang-format", ".gitignore", ".gitattributes", "resources.qrc", "orbitlab-icon.svg", "project.godot") and not path.name.endswith(".rc.in"):
            continue
        text = path.read_text(encoding="utf-8-sig")
        prefix = "\n".join(text.splitlines()[:12])
        for required in ("Silicon LogiX / SLX OrbitLab", "Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).", "Author: Marco Pezzullo", "License:"):
            if required not in prefix:
                errors.append(f"Missing authored header: {relative}: {required}")
        if path.suffix in {".cpp", ".h", ".hpp"} and ("@file" not in prefix or "@brief" not in prefix):
            errors.append(f"Missing file-purpose documentation: {relative}")
        if "\ufffd" in text:
            errors.append(f"Damaged UTF-8 text: {relative}")
        count += 1
    for node in ET.parse(root / "resources.qrc").iter("file"):
        if not node.text or not (root / node.text).is_file():
            errors.append("Missing embedded resource: " + str(node.text))
    documents = [root / "README.md", root / "THIRD_PARTY_NOTICES.md", *sorted((root / "docs").glob("*.md")), *sorted((root / "SLX_OrbitLab_3D").glob("*.md")), root / "validation/README.md"]
    for path in documents:
        text = path.read_text(encoding="utf-8")
        if "Silicon LogiX / SLX OrbitLab" not in "\n".join(text.splitlines()[:5]):
            errors.append("Missing document attribution: " + str(path.relative_to(root)))
        for link in re.findall(r"\]\(([^)]+)\)", text):
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", link):
                continue
            target = link.split("#", 1)[0]
            if target and not (path.parent / target).exists():
                errors.append(f"Missing document link: {path.name}: {target}")
    language_files = [*(root / "qml").glob("*.qml"), *sorted((root / "src").glob("*.cpp")), *sorted((root / "backend/orbitlab").glob("*.py")), root / "SLX_OrbitLab_3D/godot/viewer.gd"]
    for path in language_files:
        text = path.read_text(encoding="utf-8-sig")
        for match in LITERALS.finditer(text):
            if ITALIAN.search(match.group()[1:-1]):
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"Non-English operator text: {path.relative_to(root)}:{line}: {match.group()[:120]}")
    if public:
        hashes = {hashlib.sha256(p.read_bytes()).digest() for p in private_reference.rglob("*") if p.is_file()} if private_reference else set()
        for path in root.rglob("*"):
            relative = path.relative_to(root)
            if relative.parts[0] == ".git":
                continue
            if path.is_symlink():
                errors.append(f"Unreviewed symbolic link: {relative}")
            elif path.is_file():
                data = path.read_bytes()
                errors.extend(publication_errors(relative, data, github))
                if hashlib.sha256(data).digest() in hashes:
                    errors.append(f"Private source copied under another name: {relative}")
    catalogue = json.loads((root / "assets/capabilities.json").read_text())
    if catalogue.get("kind") != "custom-development-services":
        errors.append("The service catalogue must identify developments on commission")
    git_state = {"checked": False}
    if check_git:
        git_state, git_errors = git_audit(root, github)
        git_state["checked"] = True
        errors.extend(git_errors)
    return {"schema": "slx.orbitlab.source-audit/2", "passed": not errors, "authored_files": count, "public": public, "github_source": github, "language": "en", "git": git_state, "errors": sorted(set(errors))}
