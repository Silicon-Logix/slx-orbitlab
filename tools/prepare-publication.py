# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Prepare a fresh reviewed source tree, optionally with a separate evaluation SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from publication_audit import audit, GENERATED

ROOT = Path(__file__).resolve().parents[1]
TOP = ("CMakeLists.txt", "resources.qrc", "README.md", "LICENSE", "NOTICE.txt", "THIRD_PARTY_NOTICES.md", "Run-SLX-OrbitLab.cmd", ".gitignore", ".gitattributes", ".clang-format")
DIRECTORIES = {
    "src": {".cpp", ".h"}, "qml": {".qml"}, "core/include": {".h"},
    "assets": {".json", ".png", ".ico", ".svg", ".md", ".in"},
    "docs": {".md"}, "licenses": {".txt"}, "examples/scenarios": {".json"},
    "firmware": {".cpp"}, "backend/orbitlab": {".py"},
    "backend/fprime": {".cpp", ".hpp", ".fpp", ".txt", ".ini", ".py"},
    "tests": {".cpp", ".py"}, ".github/workflows": {".yml"},
}
SCRIPTS = ("build-windows.ps1", "build-backend.sh", "bootstrap-backend.sh", "bootstrap-viewer.ps1", "bootstrap-rtems.sh", "build-firmware.sh", "start-backend.sh", "start-orbitlab.ps1", "make-icon.cpp", "verify-all.ps1", "export-public.ps1")
TOOLS = ("audit-source.py", "publication_audit.py", "prepare-publication.py", "check-desktop-runtime.py", "console-request.py", "qualify-rtems.py", "run-verification.py", "capture-console.py", "check-binary-sdk.py", "probe-backend.py")
ASSET_FILES = ("project.godot", "README.md", "GODOT_INTEGRATION.md", "scene/asset_manifest.json", "assets/branding/Silicon_LogiX_logo_cropped.png", "assets/earth/SOURCES.md", "assets/earth/earth_surface_2048.png", "godot/viewer.gd", "godot/viewer.gd.uid", "godot/viewer.tscn", "godot/mission_client.gd", "godot/mission_client.gd.uid", "godot/test_mission.gd", "godot/test_mission.gd.uid")


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()


def copy_file(relative, destination):
    source = ROOT / relative
    if source.is_symlink() or not source.is_file():
        raise ValueError(f"Missing or unreviewed source: {relative}")
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def prepare(output, include_sdk=False, distribution="Ubuntu-22.04", initialize_repository=False):
    destination = (ROOT / output).resolve()
    if not destination.is_relative_to(ROOT / "dist") or destination == ROOT / "dist":
        raise ValueError("Publication output must be a new directory inside dist/")
    if destination.exists():
        raise ValueError("Choose a new output directory; existing exports are never overwritten")
    if include_sdk and initialize_repository:
        raise ValueError("Initialize only the source-only publication repository")
    source_audit = audit(ROOT)
    if not source_audit["passed"]:
        raise ValueError("Source audit failed: " + "; ".join(source_audit["errors"]))
    destination.mkdir(parents=True)
    for relative in TOP:
        copy_file(Path(relative), destination)
    for directory, suffixes in DIRECTORIES.items():
        for source in sorted((ROOT / directory).rglob("*")):
            if source.is_file() and source.suffix in suffixes and not any(part in GENERATED for part in source.relative_to(ROOT).parts):
                copy_file(source.relative_to(ROOT), destination)
    for directory, names in (("scripts", SCRIPTS), ("tools", TOOLS)):
        for name in names:
            copy_file(Path(directory) / name, destination)
    for name in ASSET_FILES:
        copy_file(Path("SLX_OrbitLab_3D") / name, destination)
    models = sorted((ROOT / "SLX_OrbitLab_3D/exports").glob("*.glb"))
    if len(models) != 16:
        raise ValueError("Expected the sixteen approved GLB exports")
    for model in models:
        copy_file(model.relative_to(ROOT), destination)
    for name in ("README.md", "release-0.7.0.json", "rtems-renode.json"):
        copy_file(Path("validation") / name, destination)
    if include_sdk:
        sdk_dir = destination / "sdk/windows-mingw"
        sdk_dir.mkdir(parents=True)
        binary_dir = ROOT / "build/windows-mingw"
        for name in ("SiliconLogiX.OrbitLab.Core.dll", "SiliconLogiX.OrbitLab.Core.dll.a"):
            shutil.copy2(binary_dir / name, sdk_dir / name)
        strip = shutil.which("strip") or "C:/Qt/Tools/mingw1310_64/bin/strip.exe"
        run(strip, "--strip-unneeded", str(sdk_dir / "SiliconLogiX.OrbitLab.Core.dll"))
        linux_core = run("wsl", "-d", distribution, "--", "bash", "-lc", 'printf %s "${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}/build/lib/Linux/SiliconLogiX.OrbitLab.Core.so"')
        windows_core = run("wsl", "-d", distribution, "--", "wslpath", "-w", linux_core)
        target = destination / "sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so"
        target.parent.mkdir(parents=True)
        shutil.copy2(windows_core, target)
        linux_target = run("wsl", "-d", distribution, "--", "wslpath", "-a", "-u", target.as_posix())
        run("wsl", "-d", distribution, "--", "strip", "--strip-unneeded", linux_target)
        identity = {str(p.relative_to(destination)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in (sdk_dir / "SiliconLogiX.OrbitLab.Core.dll", sdk_dir / "SiliconLogiX.OrbitLab.Core.dll.a", target)}
        (destination / "sdk/IDENTITY.json").write_text(json.dumps({"abi": 2, "minimum_core_version": "0.6.0", "stripped": True, "sha256": identity}, indent=2) + "\n", encoding="utf-8")
    result = audit(destination, public=True, github=not include_sdk, private_reference=ROOT / "private")
    if not result["passed"]:
        raise ValueError("Publication audit failed: " + "; ".join(result["errors"]))
    if initialize_repository:
        run("git", "-C", str(destination), "init", "--initial-branch=main")
        run("git", "-C", str(destination), "add", "--all")
        result = audit(destination, public=True, github=True, private_reference=ROOT / "private", check_git=True)
        if not result["passed"]:
            raise ValueError("Git index/history audit failed: " + "; ".join(result["errors"]))
    return destination, result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("dist/SLX-OrbitLab-0.7.0-github"))
    parser.add_argument("--sdk", action="store_true")
    parser.add_argument("--distribution", default="Ubuntu-22.04")
    parser.add_argument("--git", action="store_true")
    args = parser.parse_args()
    destination, result = prepare(args.output, args.sdk, args.distribution, args.git)
    print(json.dumps({"output": str(destination), "audit": result}, indent=2))
