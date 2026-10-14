# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Run reference campaigns or a bounded multi-orbit stress test against genuine F Prime/Basilisk."""
import argparse
import copy
import json
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from orbitlab.evidence import atomic_json
from orbitlab.mission import run_batch
from orbitlab.physics import Physics, EARTH_RATE, rotate_z
from orbitlab.verification import run_campaign


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, choices=range(1, 9), default=1)
    parser.add_argument("--soak-duration", type=float)
    parser.add_argument("--workspace", type=Path, default=ROOT / "workspace/verification")
    parser.add_argument("--output", type=Path, default=ROOT / "validation/continuous-campaign.json")
    args = parser.parse_args()
    scenarios = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in (ROOT / "examples/scenarios").glob("*.json")}
    if args.soak_duration is None:
        result = run_campaign(scenarios, args.workspace, args.seeds,
                              progress=lambda value: print(f"Verified {len(value['cases'])}/{value['total']}", flush=True))
    else:
        if not 6000 <= args.soak_duration <= 604800:
            parser.error("Stress-test duration must cover at least one orbit and at most seven simulated days")
        scenario = copy.deepcopy(scenarios["nominal"])
        scenario.update(continuous=True, duration_s=None, segment_duration_s=1800)
        physics = Physics(scenario)
        sample = physics.measurement()
        r, v = np.array(sample["position_eci_m"]), np.array(sample["velocity_eci_mps"])
        radius = np.linalg.norm(r)
        rate = np.sqrt(3.986004418e14 / radius ** 3)
        tangent = v / np.linalg.norm(v)
        for index, time_s in enumerate(np.arange(6000, args.soak_duration - 200, 5800), 2):
            if index > 16:
                break
            location = rotate_z(r * np.cos(rate * time_s) + tangent * radius * np.sin(rate * time_s), -EARTH_RATE * time_s)
            latitude = np.arctan2(location[2], np.hypot(location[0], location[1]))
            scenario["targets"].append({"id": index, "name": f"Stress target {index}", "priority": 70,
                "latitude_deg": float(np.rad2deg(latitude)), "longitude_deg": float(np.rad2deg(np.arctan2(location[1], location[0])))})
        scenario["faults"] = [{"kind": "attitude_sensor", "start_s": 5500, "end_s": 5530},
                              {"kind": "reaction_wheel", "start_s": 7000, "end_s": 7030}] if args.soak_duration > 7030 else []
        result = run_batch(scenario, "energy-aware", args.workspace, evaluation_s=args.soak_duration)
        result["stress_test"] = {"evaluation_s": args.soak_duration, "targets": len(scenario["targets"]),
                                 "passed": result["passed"] and result["duration_s"] >= args.soak_duration and result["segments"] >= 4}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    atomic_json(args.output, result)
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result.get("passed") and result.get("stress_test", {"passed": True})["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
