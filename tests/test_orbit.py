# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Native finite burns, access prediction, safety and immutable acquired data."""
import copy
import json
import math
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.mission import MissionRun
from orbitlab.evidence import Replay

ROOT = Path(__file__).resolve().parents[1]


def scenario():
    result = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    result["duration_s"] = 500
    result["faults"] = []
    return result


def test_finite_native_burn_changes_physical_orbit_and_replay(tmp_path):
    baseline = MissionRun(scenario(), "energy-aware", tmp_path)
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        for current in (baseline, run):
            assert current.command("OrbitLab.mission.SET_PAYLOAD", [0])["response"] == 0
        before = copy.deepcopy(run.snapshot)
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 2, 0])["response"] == 0
        assert run.snapshot["position_eci_m"] == before["position_eci_m"]
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 1, 0])["response"] != 0
        assert run.command("OrbitLab.mission.MANEUVER", [1, 0])["response"] != 0
        seen = set()
        thrust_frames = 0
        for _ in range(850):
            reference = baseline.step()
            frame = run.step()
            seen.add(frame["orbit"]["burn_state"])
            if frame["applied_thrust_n"] > 0:
                thrust_frames += 1
                assert frame["attitude_valid"] and frame["actuator_valid"] and not frame["safety_active"]
                assert 0 <= frame["propellant_kg"] <= 1
        assert {1, 2, 3}.issubset(seen) and thrust_frames > 20
        assert math.isclose(frame["delivered_delta_v_mps"], 2, abs_tol=1e-8)
        assert math.isclose(1 - frame["propellant_kg"], 2 * 65 / (220 * 9.80665), abs_tol=1e-10)
        assert frame["orbit"]["apogee_altitude_m"] - reference["orbit"]["apogee_altitude_m"] > 1000
        assert np.linalg.norm(np.array(frame["position_eci_m"]) - reference["position_eci_m"]) > 100
        assert any(c["name"].endswith("DeliveredDeltaV") for c in frame["channels"])
        directory = run.recording.directory
        report = run.close()
        assert report["orbital_maneuvers"] == 1 and report["delivered_delta_v_mps"] > 1.99
        replay = Replay(directory)
        try:
            saved = replay.seek(frame["time_s"])
            assert saved["orbit"] == frame["orbit"]
            assert saved["propellant_kg"] == frame["propellant_kg"]
        finally:
            replay.close()
    finally:
        baseline.close()
        if not run.closed:
            run.close()


def test_burn_sensor_energy_guards_and_cancellation(tmp_path):
    source = scenario()
    source["faults"] = [{"kind": "attitude_sensor", "start_s": 0, "end_s": 30}]
    run = MissionRun(source, "energy-aware", tmp_path)
    try:
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 11, 0])["response"] != 0
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 2, 0])["response"] == 0
        for _ in range(40):
            frame = run.step()
            assert frame["orbit"]["burn_state"] == 5
            assert frame["delivered_delta_v_mps"] == 0
        assert run.command("OrbitLab.mission.CANCEL_BURN", [])["response"] == 0
        for _ in range(100):
            frame = run.step()
            assert frame["orbit"]["burn_state"] == 4 and frame["applied_thrust_n"] == 0
    finally:
        run.close()
    source = scenario()
    source["initial_soc"] = source["reserve_fraction"] + 0.01
    source["faults"] = [{"kind": "solar_generation", "start_s": 0, "end_s": 500}]
    run = MissionRun(source, "energy-aware", tmp_path)
    try:
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 2, 0])["response"] == 0
        for _ in range(40):
            frame = run.step()
            assert frame["orbit"]["burn_state"] == 5 and frame["delivered_delta_v_mps"] == 0
            assert frame["reason"] == "ORBIT_BURN_ENERGY_HOLD"
    finally:
        run.close()
    source["propellant_kg"] = 0
    run = MissionRun(source, "energy-aware", tmp_path)
    try:
        assert run.command("OrbitLab.mission.ORBIT_BURN", [0, 2, 0])["response"] != 0
    finally:
        run.close()


def test_access_for_new_york_update_and_initial_orbit(tmp_path):
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        run.schedule_target({"id": 2, "name": "New York", "latitude_deg": 40.7128,
                             "longitude_deg": -74.0060, "priority": 90})
        run.command("OrbitLab.mission.REPLAN", [])
        frame = run.step()
        windows = {w["target_id"]: w for w in frame["access_windows"]}
        assert windows[1]["start_s"] >= 0
        assert windows[2]["start_s"] > windows[1]["start_s"]
        assert frame["orbit"]["prediction_horizon_s"] == 86400
        result = run.command("OrbitLab.mission.UPDATE_TARGET", [2, math.radians(48.8566), math.radians(2.3522)])
        assert result["response"] == 0
        assert math.isclose(run.snapshot["targets"][1]["latitude_deg"], 48.8566)
        assert run.command("OrbitLab.mission.SET_STRATEGY", [0])["response"] == 0
        assert run.step()["strategy"] == "priority-first"
        assert run.command("OrbitLab.mission.SET_STRATEGY", [3])["response"] != 0
    finally:
        run.close()


def test_extended_native_sequence_join_wait_and_dispatcher_maintenance(tmp_path):
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        steps = [
            {"name": "OrbitLab.mission.SCHEDULE_TARGET", "args": [2, 0.710572, -1.291648, 90, 0, 0]},
            {"name": "OrbitLab.mission.UPDATE_TARGET", "args": [2, 0.852709, 0.041054]},
            {"name": "OrbitLab.mission.SET_PRIORITY", "args": [2, 75]},
            {"name": "OrbitLab.mission.SET_STRATEGY", "args": [0]},
            {"name": "OrbitLab.mission.ORBIT_BURN", "args": [0, 1, 0]},
            {"name": "OrbitLab.mission.CANCEL_BURN", "args": [], "delay_s": 3},
            {"name": "OrbitLab.cmdDisp.CMD_NO_OP_STRING", "args": ["Customer verification"]},
            {"name": "OrbitLab.cmdDisp.CMD_TEST_CMD_1", "args": [-10, 1.5, 3]},
            {"name": "OrbitLab.mission.REPLAN", "args": []},
        ]
        plan = run.prepare_sequence("Full operations", steps)
        run.run_sequence(plan["id"], "auto")
        run.join_sequence()
        for _ in range(24):
            frame = run.step()
        assert frame["sequence"]["status"] == "completed"
        assert frame["sequence"]["completed_steps"] == len(steps)
        assert frame["sequence"]["join_wait"]["status"] == "confirmed"
        assert frame["sequence"]["join_wait"]["response"] == 0
        assert frame["strategy"] == "priority-first"
        job = next(t for t in frame["targets"] if t["id"] == 2)
        assert job["priority"] == 75 and math.isclose(job["latitude_deg"], math.degrees(0.852709))
        assert frame["orbit"]["burn_state"] == 4
        reset = run.command("OrbitLab.cmdDisp.CMD_CLEAR_TRACKING", [])
        assert reset["probe_response"] == 0 and reset["status"] in ("OK", "VERIFIED_BY_PROBE")
        assert run.command("OrbitLab.cmdDisp.CMD_NO_OP", [])["response"] == 0
    finally:
        run.close()


def test_initial_orbit_overflight_new_york(tmp_path):
    source = scenario()
    source["targets"][0].update(name="New York", latitude_deg=40.7128, longitude_deg=-74.0060)
    run = MissionRun(source, "energy-aware", tmp_path)
    try:
        assert 200 < run.snapshot["window_start_s"] < 300
        for _ in range(850):
            frame = run.step()
        assert frame["acquired"] == 1
        assert run.recent_products[0]["target_name"] == "New York"
    finally:
        run.close()
