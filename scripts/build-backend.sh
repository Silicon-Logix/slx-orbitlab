#!/usr/bin/env bash
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Build outside the Windows mount while retaining the authored source checkout.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export SLX_BACKEND_HOME="${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}"
export PATH="$SLX_BACKEND_HOME/venv/bin:$PATH"
cmake -S "$project_root/backend/fprime" -B "$SLX_BACKEND_HOME/build" -G Ninja \
    -DFPRIME_FRAMEWORK_PATH="$SLX_BACKEND_HOME/fprime" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SLX_BACKEND_HOME/build" --parallel 4
if [[ ! -f "$project_root/private/core/mission.cpp" && -f "$project_root/sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so" ]]; then
    mkdir -p "$SLX_BACKEND_HOME/build/lib/Linux"
    cmake -E copy_if_different "$project_root/sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so" "$SLX_BACKEND_HOME/build/lib/Linux/"
fi
