# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Exercise the real TCP service, operator ownership, replay and paired comparison."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, port):
        self.connection = socket.create_connection(("127.0.0.1", port), timeout=15)
        self.stream = self.connection.makefile("rwb")
        self.snapshot = {}

    def request(self, operation, request_id=None, **values):
        request_id = request_id or uuid.uuid4().hex
        self.stream.write(json.dumps({"op": operation, "request_id": request_id, **values}).encode() + b"\n")
        self.stream.flush()
        while True:
            line = self.stream.readline()
            if not line:
                raise RuntimeError("Mission service disconnected")
            message = json.loads(line)
            if message.get("type") == "snapshot":
                self.snapshot = message
            if message.get("type") == "reply" and (message.get("request_id") == request_id or message.get("request_id") is None):
                return message

    def ok(self, operation, **values):
        response = self.request(operation, **values)
        assert response["ok"], response
        return response["data"]

    def close(self):
        self.stream.close()
        self.connection.close()


def test_operator_protocol_replay_and_paired_comparison(tmp_path):
    service_root = tmp_path / "service-root"
    scenarios = service_root / "examples/scenarios"
    scenarios.mkdir(parents=True)
    scenario = json.loads((ROOT / "examples/scenarios/nominal.json").read_text())
    scenario["duration_s"] = 500
    (scenarios / "nominal.json").write_text(json.dumps(scenario))
    workspace = tmp_path / "evidence"
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    environment = {**os.environ, "PYTHONPATH": str(ROOT / "backend")}
    with (tmp_path / "service.log").open("w+") as log:
        process = subprocess.Popen([sys.executable, "-m", "orbitlab.server", "--root", str(service_root),
                                    "--workspace", str(workspace), "--port", str(port)],
                                   env=environment, stdout=log, stderr=subprocess.STDOUT)
        operator = viewer = None
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    operator = Client(port)
                    break
                except OSError:
                    assert process.poll() is None, "Backend exited during startup"
                    time.sleep(0.05)
            assert operator is not None, "Backend did not open its loopback endpoint"
            viewer = Client(port)
            hello = operator.ok("hello", role="operator")
            assert hello["role"] == "operator"
            assert Path(hello["workspace"]) == workspace.resolve()
            assert viewer.ok("hello", role="operator")["role"] == "viewer"
            assert not viewer.request("start")["ok"]
            assert not operator.request("speed", value=float("nan"))["ok"]
            assert operator.ok("status")["connected"]
            run = operator.ok("start", scenario="nominal", strategy="energy-aware")
            operator.ok("pause")
            assert operator.ok("status")["fprime_running"]
            assert operator.ok("step")["time_s"] >= 0
            assert not operator.request("command", name="OrbitLab.mission.DEPLOY", args=["invalid"])["ok"]
            first = operator.ok("command", request_id="repeatable-command", name="OrbitLab.cmdDisp.CMD_NO_OP", args=[])
            assert operator.ok("command", request_id="repeatable-command", name="OrbitLab.cmdDisp.CMD_NO_OP", args=[]) == first
            operator.ok("finish")
            manifest = workspace / "runs" / run["run_id"] / "MANIFEST.json"
            frozen = manifest.read_bytes()
            operator.ok("export")
            assert manifest.read_bytes() == frozen
            duration = operator.ok("replay", run_id=run["run_id"])["duration_s"]
            assert operator.ok("seek", time_s=duration + 100)["time_s"] == duration
            assert operator.ok("seek", time_s=-10)["time_s"] == 0
            assert not operator.request("step")["ok"]
            assert not operator.request("replay", run_id="abcdefabcdef")["ok"]
            assert operator.ok("status")["connected"]
            operator.ok("compare")
            deadline = time.monotonic() + 40
            while viewer.ok("status")["busy"]:
                assert time.monotonic() < deadline, "Paired strategy comparison did not finish"
                time.sleep(0.05)
            reports = viewer.ok("runs")
            paired = [report for report in reports if not report["aborted"]]
            assert {report["strategy"] for report in paired} == {"priority-first", "energy-aware"}
            assert len(paired) == 2 and all(report["completed_observations"] == 1 for report in paired)
            inputs = [json.loads((workspace / "runs" / report["run_id"] / "scenario.json").read_text()) for report in paired]
            assert inputs[0] == inputs[1]
            stimuli = inputs[0].pop("operator_stimuli")
            assert inputs[0] == scenario
            assert len(stimuli) == 1 and stimuli[0]["name"] == "OrbitLab.cmdDisp.CMD_NO_OP"
            assert viewer.snapshot["status"]["error"] == ""
            operator.ok("start", scenario="nominal", strategy="energy-aware", continuous=True)
            operator.ok("speed", value=1)
            operator.ok("pause")
            operator.ok("status")
            initial_time = operator.snapshot["snapshot"]["time_s"]
            operator.ok("resume")
            time.sleep(1.2)
            operator.ok("pause")
            operator.ok("status")
            assert 0 < operator.snapshot["snapshot"]["time_s"] - initial_time <= 2, "1x time scale must follow wall time, not UI ticks"
            operator.close()
            operator = None
            time.sleep(0.15)
            assert viewer.ok("hello", role="operator")["role"] == "operator"
            assert not viewer.ok("status")["playing"]
            viewer.ok("shutdown")
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            for client in (operator, viewer):
                if client:
                    client.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            if process.returncode:
                log.seek(0)
                print(log.read())
