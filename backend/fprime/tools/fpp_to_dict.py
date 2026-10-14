#!/usr/bin/env python3
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Invoke the official FPP dictionary generator with optional imports and version metadata."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--executable", required=True)
parser.add_argument("--cmake-bin-dir", required=True)
parser.add_argument("--jsonVersionFile", type=Path, required=True)
parser.add_argument("-i")
parser.add_argument("sources", nargs="+")
args = parser.parse_args()
versions = json.loads(args.jsonVersionFile.read_text(encoding="utf-8"))
command = [args.executable, "--directory", args.cmake_bin_dir,
           "--projectVersion", versions["project_version"],
           "--frameworkVersion", versions["framework_version"]]
libraries = ",".join(f"{name}@{version}" for name, version in versions.get("library_versions", {}).items())
if libraries:
    command += ["--libraryVersions", libraries]
if args.i:
    command += ["--imports", args.i]
raise SystemExit(subprocess.call(command + args.sources))
