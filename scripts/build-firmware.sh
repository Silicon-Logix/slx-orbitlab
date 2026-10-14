#!/usr/bin/env bash
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
backend_home="${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}"
compiler="$backend_home/embedded/rcc-1.3.2-gcc/bin/sparc-gaisler-rtems5-g++"
mkdir -p "$backend_home/embedded/firmware"
"$compiler" -std=gnu++17 -O2 -mcpu=leon3 -qbsp=leon3 -Wall -Wextra \
    "$project_root/firmware/eps/main.cpp" -o "$backend_home/embedded/firmware/eps.elf"
"$backend_home/embedded/rcc-1.3.2-gcc/bin/sparc-gaisler-rtems5-size" "$backend_home/embedded/firmware/eps.elf"
