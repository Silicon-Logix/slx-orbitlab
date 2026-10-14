# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Actual F Prime/Basilisk scenarios, data delivery, fault recovery, repeatability and replay."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.mission import MissionRun, run_batch, validate_scenario
from orbitlab.evidence import Replay, digest

ROOT = Path(__file__).resolve().parents[1]


def scenario(name):
    value = json.loads((ROOT / "examples/scenarios" / (name + ".json")).read_text())
    value["duration_s"] = 500
    return value


@pytest.fixture(scope="module")
def campaign(tmp_path_factory):
    workspace = tmp_path_factory.mktemp("orbitlab-campaign")
    results = {name: run_batch(scenario(name), "energy-aware", workspace)
               for name in ("nominal", "low-energy", "sensor-outage")}
    return workspace, results


def frames(directory):
    with sqlite3.connect(directory / "mission.sqlite") as db:
        return [json.loads(row[0]) for row in db.execute("SELECT snapshot FROM frames ORDER BY time_s")]


def test_nominal_closes_the_mission_loop(campaign):
    workspace, reports = campaign
    result = reports["nominal"]
    directory = workspace / "runs" / result["run_id"]
    assert result["completed_observations"] == 1
    assert result["pointing_peak_deg"] < 0.5
    assert result["minimum_energy_j"] >= scenario("nominal")["capacity_j"] * 0.05
    products = list((directory / "products").glob("*.pgm"))
    assert len(products) == 1
    assert digest(products[0]) == digest(directory / "ground" / products[0].name)
    rows = frames(directory)
    assert {"Slew", "Acquire", "Store", "Downlink", "Complete"} <= {row["phase"] for row in rows}
    assert len(rows[-1]["channels"]) >= 11
    assert any(channel["name"].startswith("OrbitLab.cmdSeq.") for channel in rows[-1]["channels"])
    with sqlite3.connect(directory / "mission.sqlite") as db:
        commands = [json.loads(row[0]) for row in db.execute("SELECT payload FROM records WHERE kind='command'")]
        assert all(command["response"] == 0 and command["packet_hex"] for command in commands)
        assert db.execute("SELECT COUNT(*) FROM records WHERE kind='packet'").fetchone()[0] > 1000


def test_energy_changes_actual_decisions(campaign):
    workspace, reports = campaign
    result = reports["low-energy"]
    assert result["completed_observations"] == 0
    assert result["deferred_observations"] == 1
    rows = frames(workspace / "runs" / result["run_id"])
    blocked = [row for row in rows if row["reason"] == "ENERGY_RESERVE_LOW"]
    assert blocked and all(not row["capture"] for row in blocked)
    assert all(row["energy_j"] < row["required_energy_j"] for row in blocked)
    assert min(row["load_w"] for row in blocked) < 115


def test_sensor_outage_inhibits_capture_and_recovers(campaign):
    workspace, reports = campaign
    rows = frames(workspace / "runs" / reports["sensor-outage"]["run_id"])
    unavailable = [row for row in rows if 100 <= row["time_s"] < 220]
    assert unavailable and all(not row["attitude_valid"] for row in unavailable)
    assert all(row["phase"] == "Sensor hold" and not row["capture"] for row in unavailable)
    assert all(row["torque_body_nm"] == [0, 0, 0] for row in unavailable)
    assert any(row["time_s"] >= 220 and row["attitude_valid"] for row in rows)
    assert reports["sensor-outage"]["completed_observations"] == 1


def test_same_seed_and_mission_repeat_numerically(campaign, tmp_path):
    workspace, reports = campaign
    repeat = run_batch(scenario("nominal"), "energy-aware", tmp_path)
    assert repeat["completed_observations"] == reports["nominal"]["completed_observations"]
    assert repeat["final_energy_j"] == pytest.approx(reports["nominal"]["final_energy_j"], abs=1e-8)
    assert repeat["pointing_rms_deg"] == pytest.approx(reports["nominal"]["pointing_rms_deg"], abs=1e-10)
    first = frames(workspace / "runs" / reports["nominal"]["run_id"])
    second = frames(tmp_path / "runs" / repeat["run_id"])
    assert [frame["phase"] for frame in first] == [frame["phase"] for frame in second]


def test_replay_seek_and_integrity(campaign, tmp_path):
    import shutil
    workspace, reports = campaign
    original = workspace / "runs" / reports["nominal"]["run_id"]
    replay = Replay(original)
    try:
        state = replay.seek(230.7)
        assert state["time_s"] == 230.5
        assert state["mode"] == "REPLAY"
        assert all(event["time_s"] <= state["time_s"] for event in state["events"])
        assert state["trail_ecef_display"]
        assert state["presentation_history"][-1]["time_s"] <= state["time_s"]
        assert len(replay.seek(10)["trail_ecef_display"]) < len(state["trail_ecef_display"])
        assert replay.seek(10)["time_s"] == 10
    finally:
        replay.close()
    altered = tmp_path / "altered"
    shutil.copytree(original, altered)
    (altered / "scenario.json").write_text("{}")
    with pytest.raises(ValueError, match="integrity"):
        Replay(altered)


def test_native_command_rejection_and_idempotency(tmp_path):
    run = MissionRun(scenario("nominal"), "energy-aware", tmp_path)
    try:
        result = run.command("OrbitLab.mission.ADD_TARGET", [2, 0.2, 0.1, 50], "operator-1")
        count = len(run.bridge.commands)
        assert run.command("OrbitLab.mission.ADD_TARGET", [2, 0.2, 0.1, 50], "operator-1") == result
        assert len(run.bridge.commands) == count
        with pytest.raises(ValueError, match="reused"):
            run.command("OrbitLab.mission.ADD_TARGET", [3, 0.2, 0.1, 50], "operator-1")
        rejected = run.command("OrbitLab.mission.ADD_TARGET", [2, 0.2, 0.1, 50], "operator-2")
        assert rejected["response"] != 0
    finally:
        run.close(aborted=True)


def test_invalid_configuration_is_rejected_before_simulation():
    invalid = scenario("nominal")
    invalid["initial_soc"] = float("nan")
    with pytest.raises(ValueError, match="initial_soc"):
        validate_scenario(invalid)


@pytest.mark.skipif(not (Path.home() / ".cache/slx-orbitlab/embedded/firmware/eps.elf").is_file(), reason="Optional RTEMS toolchain is not installed")
def test_qualified_firmware_permissions_enter_the_physical_loop(tmp_path):
    configuration = scenario("nominal")
    configuration["initial_soc"] = 0.03
    run = MissionRun(configuration, "energy-aware", tmp_path, rtems=True)
    try:
        for _ in range(4):
            run.step()
        assert run.snapshot["eps"]["mode"] == "RTEMS / Renode"
        assert run.snapshot["eps"]["flags"] == 1
        assert run.snapshot["load_w"] == 18
        assert run.snapshot["consumed_w"] == 18
        assert run.snapshot["eps"]["heartbeat"] > 0
        assert not run.snapshot["capture"]
    finally:
        run.close(aborted=True)
