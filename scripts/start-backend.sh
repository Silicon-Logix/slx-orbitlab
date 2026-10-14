#!/usr/bin/env bash
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
backend_home="${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}"
export PYTHONPATH="$project_root/backend${PYTHONPATH:+:$PYTHONPATH}"
exec "$backend_home/venv/bin/python" -m orbitlab.server --root "$project_root" "$@"
