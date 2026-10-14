# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
"""Readiness probe for actual F Prime and Basilisk execution, with no numerical fallback."""
import json
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.mission import MissionRun

root = Path(__file__).resolve().parents[1]
scenario = json.loads((root / "examples/scenarios/nominal.json").read_text())
with tempfile.TemporaryDirectory(prefix="slx-orbitlab-readiness-") as workspace:
    run = MissionRun(scenario, "energy-aware", workspace)
    try:
        for _ in range(4):
            snapshot = run.step()
        print(json.dumps({"schema": "slx.orbitlab.readiness/1", "passed": True,
                          "time_s": snapshot["time_s"], "energy_j": snapshot["energy_j"],
                          "position_eci_m": snapshot["position_eci_m"],
                          "native_commands": len(run.bridge.catalogue()),
                          "native_channels": len(run.bridge.channels),
                          "events": len(run.bridge.events)}, indent=2))
    finally:
        run.close()
