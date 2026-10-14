# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Operator examples match native argument types and diagnostic commands produce real events."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.mission import MissionRun

ROOT = Path(__file__).resolve().parents[1]


def test_dictionary_examples_and_actual_diagnostic_events(tmp_path):
    scenario = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    run = MissionRun(scenario, "energy-aware", tmp_path)
    try:
        catalogue = run.bridge.catalogue()
        assert len(catalogue) == len(run.bridge.dictionary.command_name)
        for command in catalogue:
            assert command["title"] and command["description"] and command["parameter_help"]
            assert len(command["example"]) == len(command["arguments"]) == len(command["argument_types"])
            run.bridge.encode_command(command["name"], command["example"])
        guides = {c["name"]: c for c in catalogue}
        counter = run.bridge.channels["OrbitLab.cmdDisp.CommandsDispatched"]
        assert counter["value"] > 0 and counter["valid"]
        assert guides["OrbitLab.mission.SET_BEACON"]["example"] == [1, 4]
        assert guides["OrbitLab.mission.MANEUVER"]["example"] == [3, 45]
        assert not guides["OrbitLab.mission.CONFIGURE"]["direct_enabled"]
        assert not guides["OrbitLab.cmdSeq.CS_RUN"]["direct_enabled"]
        for mnemonic, event, arguments in (("CMD_NO_OP_STRING", "NoOpStringReceived", ["OrbitLab test"]),
                                            ("CMD_TEST_CMD_1", "TestCmd1Args", [-10, 1.5, 3])):
            result = run.command("OrbitLab.cmdDisp." + mnemonic, arguments)
            assert result["response"] == 0 and result["accepted_s"] == run.snapshot["time_s"]
            assert any(e["name"].endswith(event) for e in run.bridge.events)
        assert run.physics.time_s == 0
        run.schedule_target({"id": 2, "name": "Paris", "latitude_deg": 48.8566, "longitude_deg": 2.3522, "priority": 80})
        assert run.snapshot["next_target_id"] == 3
        assert run.snapshot["targets"][-1]["name"] == "Paris"
    finally:
        run.close()
