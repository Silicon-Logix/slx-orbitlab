# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Native vehicle commands must move physics, affect loads and preserve data-delivery guards."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from orbitlab.mission import MissionRun
from orbitlab.evidence import digest


def scenario():
    value = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    value.update(continuous=True, duration_s=None)
    return value


def command(run, name, args):
    response = run.command("OrbitLab.mission." + name, args)
    assert response["response"] == 0
    return response


def test_native_slew_panels_beacon_and_safety(tmp_path):
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        initial = np.asarray(run.snapshot["truth_quaternion_body_to_eci"])
        time_s = run.snapshot["time_s"]
        command(run, "MANEUVER", [3, 45])
        assert run.snapshot["time_s"] == time_s
        run.step()
        initial_error = run.snapshot["pointing_error_deg"]
        for _ in range(80):
            run.step()
        assert run.snapshot["vehicle"]["maneuver_mode"] == 3
        assert run.snapshot["pointing_error_deg"] < initial_error
        assert abs(np.dot(initial, run.snapshot["truth_quaternion_body_to_eci"])) < 0.999
        command(run, "DEPLOY", [0])
        for _ in range(12):
            run.step()
        assert run.snapshot["visual"]["pivots_native_deg"]["Solar_Left_Fold"] > 0
        command(run, "SET_BEACON", [1, 4])
        observed = set()
        for _ in range(12):
            run.step()
            on = bool(run.snapshot["vehicle"]["beacon_on"])
            observed.add(on)
            assert run.snapshot["load_w"] == 55 + 2*on
            assert run.snapshot["visual"]["beacon_on"] == on
        assert observed == {True, False}
        assert run.bridge.channels["OrbitLab.mission.ManeuverMode"]["value"] == 3
        command(run, "MANEUVER", [0, 0])
    finally:
        run.close()
    low = scenario()
    low["initial_soc"] = 0.02
    run = MissionRun(low, "energy-aware", tmp_path / "low")
    try:
        command(run, "MANEUVER", [3, 45])
        command(run, "SET_BEACON", [1, 4])
        run.step()
        assert run.snapshot["safety_active"] == 1
        assert run.snapshot["vehicle"]["beacon_on"] == 0
        assert not run.snapshot["capture"] and not run.snapshot["downlink"]
    finally:
        run.close()


def test_optical_disable_and_verified_earth_image(tmp_path):
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        command(run, "SET_PAYLOAD", [0])
        for _ in range(10):
            run.step()
        assert run.snapshot["attitude_valid"]
        assert run.snapshot["reason"] == "OPTICAL_PAYLOAD_DISABLED"
        assert run.snapshot["acquired"] == 0
        command(run, "SET_PAYLOAD", [1])
        command(run, "SET_DOWNLINK", [0])
        for _ in range(800):
            run.step()
            if run.snapshot["acquired"]:
                break
        assert run.snapshot["acquired"] == 1
        assert run.snapshot["completed"] == 0
        product = run.snapshot["products"][0]
        assert product["geometry"]["earth_pixels_percent"] > 95
        assert len(product["geometry"]["footprint_deg"]) == 4
        directory = run.recording.directory
        preview = Image.open(directory / "products" / product["preview_filename"])
        assert preview.size == (512, 384)
        assert np.asarray(Image.open(directory / "products" / product["filename"])).std() > 3
        command(run, "SET_DOWNLINK", [1])
        for _ in range(100):
            run.step()
            if run.snapshot["completed"]:
                break
        assert run.snapshot["completed"] == 1
        assert digest(directory / "products" / product["filename"]) == digest(directory / "ground" / product["filename"])
        assert (directory / "ground" / product["preview_filename"]).is_file()
    finally:
        run.close()


def test_native_command_validation(tmp_path):
    run = MissionRun(scenario(), "energy-aware", tmp_path)
    try:
        for name, args in [("MANEUVER", [9, 45]), ("MANEUVER", [3, 181]),
                           ("SET_PAYLOAD", [2]), ("SET_DOWNLINK", [2]), ("SET_BEACON", [1, 0])]:
            assert run.command("OrbitLab.mission." + name, args)["response"] != 0
        run.step()
        assert run.snapshot["vehicle"]["maneuver_mode"] == 0
        assert run.snapshot["vehicle"]["beacon_enabled"] == 0
    finally:
        run.close()
