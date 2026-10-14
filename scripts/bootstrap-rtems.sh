#!/usr/bin/env bash
# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Optional platform qualification tools, isolated from the primary mission deployment.
set -euo pipefail
backend_home="${SLX_BACKEND_HOME:-$HOME/.cache/slx-orbitlab}"
mkdir -p "$backend_home/embedded"
cd "$backend_home/embedded"
if [[ ! -d rcc-1.3.2-gcc ]]; then
    curl -fL --retry 2 https://download.gaisler.com/anonftp/rcc/rcc-1.3/1.3.2/sparc-rtems-5-gcc-10.5.0-1.3.2-linux.txz -o rcc.txz
    tar -xJf rcc.txz
fi
if [[ ! -d renode ]]; then
    curl -fL --retry 2 https://github.com/renode/renode/releases/download/v1.16.1/renode-1.16.1.linux-portable-dotnet.tar.gz -o renode.tar.gz
    mkdir renode
    tar -xzf renode.tar.gz --strip-components=1 -C renode
fi
printf 'Embedded tools ready: %s\n' "$backend_home/embedded"
