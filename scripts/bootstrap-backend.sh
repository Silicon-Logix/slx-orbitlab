#!/usr/bin/env bash
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Install pinned numerical and flight-software tools in an isolated Linux cache.
set -euo pipefail
backend_home="${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}"
mkdir -p "$backend_home"
if [[ ! -f "$backend_home/venv/bin/python" ]]; then
    python3 -m venv "$backend_home/venv"
fi
"$backend_home/venv/bin/python" -m pip install --disable-pip-version-check \
    'bsk==2.12.0' 'Pillow>=10,<13'
if [[ ! -d "$backend_home/fprime/.git" ]]; then
    git clone --branch v4.3.0 --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/nasa/fprime.git "$backend_home/fprime"
fi
"$backend_home/venv/bin/python" -m pip install --disable-pip-version-check \
    -r "$backend_home/fprime/requirements.txt"
printf 'Backend tools ready: %s\n' "$backend_home"
