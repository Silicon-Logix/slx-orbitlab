# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Continuous operations, late commands, segment replay, bounded storage and crash recovery."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from orbitlab.mission import MissionRun, run_batch
from orbitlab.evidence import Replay, recover_recording


def continuous():
    value = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    value.update(continuous=True, duration_s=60, segment_duration_s=120)
    return value


def test_live_jobs_and_segmented_replay(tmp_path):
    run = MissionRun(continuous(), "energy-aware", tmp_path)
    try:
        while run.physics.time_s < 270:
            run.step()
        assert run.snapshot["completed"] == 1
        job = {"id": 2, "name": "Late observation", "latitude_deg": 41.9028,
               "longitude_deg": 12.4964, "priority": 70}
        run.schedule_target(job)
        assert run.command("OrbitLab.mission.SET_PRIORITY", [2, 90])["response"] == 0
        while run.physics.time_s <= 500:
            run.step()
        assert not run.closed and run.snapshot["continuous"] and run.snapshot["duration_s"] is None
        assert run.snapshot["completed"] == 2
        assert run.snapshot["queue_depth"] == 0 and run.snapshot["stored_bytes"] == 0
        assert run.snapshot["delivered_bytes"] == 2 * 65588
        assert run.command("OrbitLab.mission.REMOVE_TARGET", [2])["response"] == 0
        report = run.close()
        assert report["segments"] >= 4 and report["passed"]
    finally:
        run.close(aborted=True)
    replay = Replay(run.recording.directory)
    try:
        later = replay.seek(400)
        assert later["time_s"] == 400
        assert any(c["name"].endswith("SET_PRIORITY") for c in later["commands"])
        earlier = replay.seek(20)
        assert earlier["time_s"] == 20
        assert all(e["time_s"] <= 20 for e in earlier["events"])
        assert not any(c["name"].endswith("SET_PRIORITY") for c in earlier["commands"])
    finally:
        replay.close()
    # Replaying operator commands at the recorded boundary must preserve numerical results.
    from orbitlab.server import Service
    service = Service(ROOT, tmp_path)
    service.engine = run
    evaluation = service.evaluation_scenario(500)
    repeated = run_batch(evaluation, "energy-aware", tmp_path / "paired")
    assert repeated["completed_observations"] == report["completed_observations"]
    assert repeated["final_energy_j"] == pytest.approx(report["final_energy_j"], abs=1e-8)
    assert repeated["pointing_rms_deg"] == pytest.approx(report["pointing_rms_deg"], abs=1e-10)


def test_signed_coordinates_and_native_deadline(tmp_path):
    scenario = continuous()
    scenario["targets"].append({"id": 2, "name": "Southern target", "latitude_deg": -12.1,
                                "longitude_deg": -77.0, "priority": 100, "deadline_s": 2})
    run = MissionRun(scenario, "energy-aware", tmp_path)
    try:
        for _ in range(8):
            run.step()
        assert run.snapshot["expired"] == 1
        assert any(channel["name"].endswith("ExpiredTargets") and channel["value"] == 1 for channel in run.snapshot["channels"])
    finally:
        run.close(aborted=True)


def test_disk_quota_stops_recording_without_discarding_evidence(tmp_path):
    scenario = continuous()
    scenario["recording_quota_bytes"] = 1048576
    run = MissionRun(scenario, "energy-aware", tmp_path)
    try:
        with pytest.raises(RuntimeError, match="storage limit"):
            for _ in range(1000):
                run.step()
        report = run.close(aborted=True)
        assert report["finalized"] and (run.recording.directory / "checkpoint.json").is_file()
        replay = Replay(run.recording.directory)
        replay.close()
    finally:
        run.close(aborted=True)


def test_active_writer_cannot_be_recovered(tmp_path):
    run = MissionRun(continuous(), "energy-aware", tmp_path)
    try:
        with pytest.raises(ValueError, match="active writer"):
            recover_recording(run.recording.directory)
    finally:
        run.close(aborted=True)


def test_process_crash_recovers_only_committed_frames(tmp_path):
    script = """import json, os, sys
from pathlib import Path
from orbitlab.mission import MissionRun
scenario=json.loads(Path(sys.argv[1]).read_text())
scenario.update(continuous=True, duration_s=60, segment_duration_s=30)
run=MissionRun(scenario,'energy-aware',Path(sys.argv[2]))
for _ in range(175): run.step()
os._exit(0)
"""
    environment = {**os.environ, "PYTHONPATH": str(ROOT / "backend")}
    subprocess.run([sys.executable, "-c", script, str(ROOT / "examples/scenarios/nominal.json"), str(tmp_path)],
                   env=environment, check=True, timeout=20, capture_output=True)
    directory = next((tmp_path / "runs").iterdir())
    report = recover_recording(directory)
    assert report["recovered"] and report["aborted"] and report["finalized"]
    assert 80 <= report["duration_s"] <= 87.5
    replay = Replay(directory)
    try:
        assert replay.seek(100)["time_s"] == report["duration_s"]
    finally:
        replay.close()
