# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Prove the exported F Prime deployment executes the approved binary core with no private source."""
import argparse
import copy
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sdk", type=Path, required=True)
parser.add_argument("--workspace", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if (args.sdk / "private").exists():
    raise RuntimeError("The public SDK must not contain private implementation sources")
sys.path.insert(0, str(args.sdk / "backend"))
from orbitlab.mission import run_batch
from orbitlab.evidence import atomic_json, digest

scenario = json.loads((args.sdk / "examples/scenarios/nominal.json").read_text(encoding="utf-8"))
scenario["duration_s"] = 500
report = run_batch(scenario, "energy-aware", args.workspace)
orbital_scenario = copy.deepcopy(scenario)
orbital_scenario["operator_stimuli"] = [
    {"time_s": 0, "boundary": "before_frame", "name": "OrbitLab.mission.SET_PAYLOAD", "args": [0]},
    {"time_s": 0, "boundary": "before_frame", "name": "OrbitLab.mission.ORBIT_BURN", "args": [0, 2, 0]},
]
orbital = run_batch(orbital_scenario, "energy-aware", args.workspace)
expected = digest(args.sdk / "sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so")
result = {"schema": "slx.orbitlab.binary-sdk-check/1", "private_sources_present": False,
          "core_abi": 2, "core_sha256": expected, "run_id": report["run_id"],
          "delivered": report["completed_observations"], "pointing_rms_deg": report["pointing_rms_deg"],
          "orbit_run_id": orbital["run_id"], "delivered_delta_v_mps": orbital["delivered_delta_v_mps"],
          "final_propellant_kg": orbital["final_propellant_kg"],
          "passed": report["passed"] and report["completed_observations"] == 1 and report["identity"]["core_binary_sha256"] == expected
              and orbital["passed"] and abs(orbital["delivered_delta_v_mps"] - 2) < 1e-7
              and orbital["identity"]["core_binary_sha256"] == expected}
atomic_json(args.output, result)
print(json.dumps(result, indent=2))
raise SystemExit(0 if result["passed"] else 1)
