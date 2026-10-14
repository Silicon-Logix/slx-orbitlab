# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Real native sequencer timing, manual stepping, cancellation and replay evidence."""
import json
import copy
from pathlib import Path
import sqlite3
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.mission import MissionRun, run_batch
from orbitlab.evidence import Replay

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def mission(tmp_path):
    scenario = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    run = MissionRun(scenario, "energy-aware", tmp_path)
    try:
        yield run
    finally:
        run.close()


def step(name, args, delay=0):
    return {"name": "OrbitLab.mission." + name, "args": args, "delay_s": delay}


def test_native_relative_times_and_replay(mission):
    plan = mission.prepare_sequence("Beacon and maneuver", [step("SET_BEACON", [1, 4], 2),
        step("MANEUVER", [3, -30], 3), step("SET_BEACON", [0, 4], 2), step("MANEUVER", [0, 0])])
    assert plan["validated"] and plan["sha256"] and plan["delay_total_s"] == 7
    assert any(e["name"].endswith("CS_SequenceValid") and plan["file_name"] in e["text"] for e in mission.bridge.events)
    mission.run_sequence(plan["id"], "auto")
    assert mission.sequence_status["completed_steps"] == 0
    for _ in range(20):
        frame = mission.step()
        if frame["time_s"] < 2:
            assert not frame["vehicle"]["beacon_enabled"]
        if 2 <= frame["time_s"] < 7:
            assert frame["vehicle"]["beacon_enabled"]
    state = mission.sequence_status
    assert state["status"] == "completed"
    assert [r["executed_s"] for r in state["steps"]] == [2, 5, 7, 7]
    assert all(r["response"] == 0 for r in state["steps"])
    assert any(e["name"].endswith("CS_SequenceComplete") for e in mission.bridge.events)
    result = mission.close()
    assert result["sequences_completed"] == 1
    assert result["sequences"][0]["sha256"] == plan["sha256"]
    assert "SET_BEACON" in (mission.recording.directory / "sequence-commands.csv").read_text()
    with sqlite3.connect(mission.recording.directory / "mission.sqlite") as db:
        records = list(db.execute("SELECT time_s,payload FROM records WHERE kind='operator_stimulus' ORDER BY sequence"))
        stimuli = [json.loads(r[1]) for r in records]
        original = [json.loads(r[0]) for r in db.execute("SELECT snapshot FROM frames ORDER BY time_s")]
    assert [s["args"] for s in stimuli] == [[1, 4], [3, -30], [0, 4], [0, 0]]
    assert all(s["boundary"] == "before_frame" for s in stimuli)
    replay = Replay(mission.recording.directory)
    try:
        assert replay.seek(4)["sequence"]["completed_steps"] == 1
        assert replay.seek(9)["sequence"]["status"] == "completed"
    finally:
        replay.close()
    scenario = copy.deepcopy(mission.scenario)
    scenario["operator_stimuli"] = [{"time_s": timestamp, **json.loads(raw)} for timestamp, raw in records]
    workspace = mission.recording.directory.parents[1] / "paired"
    paired = run_batch(scenario, "energy-aware", workspace, evaluation_s=9.5)
    with sqlite3.connect(workspace / "runs" / paired["run_id"] / "mission.sqlite") as db:
        repeated = [json.loads(r[0]) for r in db.execute("SELECT snapshot FROM frames ORDER BY time_s")]
    assert len(repeated) == len(original)
    for actual, expected in zip(repeated, original):
        assert actual["time_s"] == expected["time_s"]
        assert actual["energy_j"] == pytest.approx(expected["energy_j"], abs=1e-8)
        assert actual["truth_quaternion_body_to_eci"] == pytest.approx(expected["truth_quaternion_body_to_eci"], abs=1e-10)


def test_manual_execution_and_cancellation(mission):
    plan = mission.prepare_sequence("Manuale", [step("SET_PAYLOAD", [0]), step("SET_PAYLOAD", [1], 2)])
    mission.run_sequence(plan["id"], "manual")
    assert mission.sequence_status["status"] == "loaded"
    for _ in range(4):
        assert mission.step()["vehicle"]["payload_enabled"]
    mission.control_sequence("start")
    assert mission.sequence_status["completed_steps"] == 1
    assert mission.sequence_status["status"] == "waiting_step"
    assert not mission.step()["vehicle"]["payload_enabled"]
    mission.control_sequence("step")
    with pytest.raises(ValueError):
        mission.control_sequence("step")
    for _ in range(6):
        mission.step()
    assert mission.sequence_status["completed_steps"] == 2
    assert mission.snapshot["vehicle"]["payload_enabled"]
    assert mission.sequence_status["status"] == "completed"
    waiting = mission.prepare_sequence("Annullamento", [step("SET_PAYLOAD", [0], 20)])
    mission.run_sequence(waiting["id"], "auto")
    mission.control_sequence("cancel")
    assert mission.sequence_status["status"] == "canceled"
    for _ in range(45):
        assert mission.step()["vehicle"]["payload_enabled"]
    assert mission.sequence_status["completed_steps"] == 0
    mission.run_sequence(waiting["id"], "manual")
    mission.control_sequence("cancel")
    assert mission.sequence_status["status"] == "canceled"


def test_preflight_and_native_checksum_rejection(mission):
    for steps in ([], [step("CONFIGURE", [1, 2])], [step("DEPLOY", [2])],
                  [step("MANEUVER", [3, 181])], [step("SET_BEACON", [1, 0])],
                  [step("SET_PAYLOAD", [0], -1)], [step("SET_PAYLOAD", [float("nan")])]):
        with pytest.raises(ValueError):
            mission.prepare_sequence("Invalid", steps)
    plan = mission.prepare_sequence("Integrity", [step("DEPLOY", [1])])
    path = mission.recording.directory / plan["file_name"]
    raw = bytearray(path.read_bytes())
    raw[-1] ^= 1
    path.write_bytes(raw)
    with pytest.raises(ValueError, match="validation"):
        mission.run_sequence(plan["id"], "auto")
    ack = mission.bridge.command("OrbitLab.cmdSeq.CS_VALIDATE", [path.name])
    mission.bridge.synchronize()
    assert ack["response"] != 0
    assert any(e["name"].endswith("CS_FileCrcFailure") for e in mission.bridge.events)
