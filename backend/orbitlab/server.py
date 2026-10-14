# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Local JSON-line mission service with an operator lease, replay and comparison jobs."""
import argparse
import asyncio
import copy
from contextlib import suppress
from datetime import datetime, timezone
import importlib.metadata
import json
import math
import os
from pathlib import Path
import signal
import time
import threading
from collections import deque
from .mission import MissionRun, run_batch, validate_scenario
from .evidence import Replay, recover_recording, read_rows
from .verification import run_campaign


class Service:
    def __init__(self, root, workspace):
        self.root, self.workspace = Path(root), Path(workspace)
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.engine = None
        self.replay = None
        self.playing = False
        self.speed = 60.0
        self.clients = {}
        self.operator = None
        self.comparison = []
        self.busy = False
        self.last_error = ""
        self.replay_time = 0.0
        self.replay_snapshot = {}
        self.history = deque(maxlen=720)
        self.campaign = {}
        self.job_cancel = threading.Event()
        self.last_tick_speed = 0.0
        self.compare_task = None
        self.stop = asyncio.Event()
        self.scenarios = {path.stem: validate_scenario(json.loads(path.read_text()))
                          for path in (self.root / "examples/scenarios").glob("*.json")}
        firmware = Path(os.environ.get("SLX_BACKEND_HOME", Path.home() / ".cache/slx-orbitlab")) / "embedded/firmware/eps.elf"
        self.rtems_available = firmware.is_file() and (self.root / "validation/rtems-renode.json").is_file()

    def runs(self):
        paths = sorted((self.workspace / "runs").glob("*/report.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        return [{**json.loads(path.read_text()),
                 "recorded_utc": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}
                for path in paths[:40]]

    def recoverable_runs(self):
        paths = sorted((self.workspace / "runs").glob("*/checkpoint.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        return [{"run_id": p.parent.name, **json.loads(p.read_text(encoding="utf-8"))} for p in paths[:40]
                if not (p.parent / "MANIFEST.json").exists() and
                (not self.engine or p.parent.name != self.engine.run_id or self.engine.closed)]

    def status(self):
        return {"schema": "slx.orbitlab.service/1", "connected": True, "playing": self.playing, "speed": self.speed,
                "busy": self.busy, "error": self.last_error,
                "actual_time_scale": self.last_tick_speed,
                "fprime_running": bool(self.engine and not self.engine.closed and self.engine.bridge.process.poll() is None),
                "basilisk_running": bool(self.engine and not self.engine.closed),
                "versions": {name: importlib.metadata.version(name) for name in ("bsk", "fprime-gds")},
                "rtems_available": self.rtems_available,
                "rtems": "RTEMS 5.0 / LEON3 running" if self.engine and self.engine.eps and not self.engine.closed else "Qualified optional controller" if self.rtems_available else "Not configured",
                "renode": "1.16.1 running" if self.engine and self.engine.eps and not self.engine.closed else "Not active",
                "mode": "REPLAY" if self.replay else "LIVE"}

    def presentation(self):
        snapshot = self.replay_snapshot if self.replay else self.engine.presentation() if self.engine else {}
        return {"type": "snapshot", "snapshot": snapshot, "status": self.status(),
                "comparison": self.comparison,
                "campaign": self.campaign,
                "history": snapshot.get("presentation_history", []) if self.replay else list(self.history)}

    async def send(self, writer, message):
        payload = json.dumps(message, allow_nan=False, separators=(",", ":")).encode() + b"\n"
        writer.write(payload)
        await asyncio.wait_for(writer.drain(), timeout=2)

    async def broadcast(self):
        message = self.presentation()
        for writer in list(self.clients):
            try:
                await self.send(writer, message)
            except (ConnectionError, asyncio.TimeoutError):
                writer.close()

    def stop_current(self):
        self.playing = False
        if self.engine and not self.engine.closed:
            self.engine.close(aborted=not self.engine.scenario.get("continuous") and
                              self.engine.physics.time_s < self.engine.scenario["duration_s"])
        if self.replay:
            self.replay.close()
            self.replay = None

    async def compare(self, scenario):
        try:
            results = []
            for strategy in ("priority-first", "energy-aware"):
                result = await asyncio.to_thread(run_batch, copy.deepcopy(scenario), strategy, self.workspace,
                                                 bool(self.engine and self.engine.rtems_enabled), None, self.job_cancel)
                if self.job_cancel.is_set():
                    break
                results.append(result)
                self.comparison = results
                await self.broadcast()
        except Exception as error:
            self.last_error = str(error)
        finally:
            self.busy = False
            await self.broadcast()

    async def verify(self, seed_count):
        loop = asyncio.get_running_loop()
        def progress(value):
            loop.call_soon_threadsafe(self._campaign_progress, value)
        try:
            self.campaign = await asyncio.to_thread(run_campaign, copy.deepcopy(self.scenarios),
                                  self.workspace, seed_count, self.job_cancel, progress)
        except Exception as error:
            self.last_error = str(error)
            self.campaign = {**self.campaign, "status": "failed", "passed": False, "error": str(error)}
        finally:
            self.busy = False
            await self.broadcast()

    def _campaign_progress(self, value):
        self.campaign = value

    def evaluation_scenario(self, duration):
        if not self.engine:
            raise ValueError("Load a mission before comparing strategies")
        scenario = copy.deepcopy(self.engine.scenario)
        if scenario.get("continuous"):
            scenario["continuous"] = False
        scenario["duration_s"] = duration
        if not self.engine.closed:
            self.engine.recording.db.commit()
        scenario["faults"] = [f for f in scenario["faults"] if f["start_s"] < duration]
        for row in read_rows(self.engine.recording.directory,
                             "SELECT time_s,kind,payload FROM records WHERE kind IN ('fault_injection','operator_stimulus') AND time_s<=? ORDER BY time_s,sequence", (duration,)):
            time_s, kind, raw = row
            item = json.loads(raw)
            if kind == "fault_injection":
                scenario["faults"].append(item)
            else:
                if item["name"] != "OrbitLab.mission.SET_STRATEGY":
                    scenario.setdefault("operator_stimuli", []).append({"time_s": time_s, **item})
        for fault in scenario["faults"]:
            fault["end_s"] = min(fault["end_s"], duration)
        return validate_scenario(scenario)

    async def handle(self, writer, request):
        operation = request.get("op")
        if operation == "hello":
            role = request.get("role", "viewer")
            if role == "operator" and self.operator in (None, writer):
                self.operator = writer
                self.clients[writer] = "operator"
            else:
                self.clients[writer] = "viewer"
            return {"role": self.clients[writer], "workspace": str(self.workspace.resolve()), "scenarios": list(self.scenarios.values()), "runs": self.runs(),
                    "catalogue": self.engine.bridge.catalogue() if self.engine else [], "recoverable": self.recoverable_runs()}
        if operation in ("status", "runs", "recordings"):
            return self.status() if operation == "status" else self.runs() if operation == "runs" else self.recoverable_runs()
        if self.operator is not writer:
            raise ValueError("An active operator lease is required")
        if self.busy and operation not in ("pause", "export", "cancel_job", "shutdown"):
            raise ValueError("A verification job is running")
        if operation == "start":
            scenario_id = request.get("scenario", "nominal")
            if scenario_id not in self.scenarios:
                raise ValueError("Unknown scenario")
            scenario = copy.deepcopy(self.scenarios[scenario_id])
            if request.get("continuous", False):
                scenario["continuous"] = True
                scenario["duration_s"] = None
            if "target" in request:
                scenario["targets"] = [request["target"]]
            validate_scenario(scenario)
            self.stop_current()
            self.engine = MissionRun(scenario, request.get("strategy", "energy-aware"), self.workspace, rtems=bool(request.get("rtems", False)))
            self.history.clear()
            self.comparison = []
            self.last_error = ""
            self.playing = True
            return {"run_id": self.engine.run_id, "catalogue": self.engine.bridge.catalogue()}
        if operation == "pause":
            self.playing = False
            return self.status()
        if operation == "resume":
            if not self.replay and (not self.engine or self.engine.closed):
                raise ValueError("Load a mission or recording first")
            self.playing = True
            return self.status()
        if operation == "speed":
            speed = float(request["value"])
            if not math.isfinite(speed) or not 1 <= speed <= 600:
                raise ValueError("Simulation speed must be 1 to 600")
            self.speed = speed
            return self.status()
        if operation == "replay":
            run_id = request["run_id"]
            if not isinstance(run_id, str) or len(run_id) != 12 or any(char not in "0123456789abcdef" for char in run_id):
                raise ValueError("Invalid recording identifier")
            self.stop_current()
            self.replay = Replay(self.workspace / "runs" / run_id)
            self.replay_time = 0
            self.replay_snapshot = self.replay.seek(0)
            self.history.clear()
            return {"duration_s": self.replay.duration_s}
        if operation == "seek":
            value = float(request["time_s"])
            if not self.replay or not math.isfinite(value):
                raise ValueError("Load a recording and supply a finite simulation time")
            self.playing = False
            self.replay_snapshot = self.replay.seek(value)
            self.replay_time = self.replay_snapshot["time_s"]
            return {"time_s": self.replay_snapshot["time_s"]}
        if operation == "compare":
            if not self.engine:
                raise ValueError("Load a mission before comparing strategies")
            self.playing = False
            self.busy = True
            self.comparison = []
            self.last_error = ""
            duration = float(request.get("duration_s") or self.engine.scenario.get("duration_s") or 6000)
            if not math.isfinite(duration) or not 1 <= duration <= 604800:
                self.busy = False
                raise ValueError("Comparison requires a finite interval of one second to seven days")
            try:
                scenario = self.evaluation_scenario(duration)
            except Exception:
                self.busy = False
                raise
            self.job_cancel.clear()
            self.compare_task = asyncio.create_task(self.compare(scenario))
            return {"status": "running"}
        if operation == "campaign":
            seeds = request.get("seed_count", 1)
            if not isinstance(seeds, int) or not 1 <= seeds <= 8:
                raise ValueError("Choose one to eight deterministic seeds")
            if not all(key in self.scenarios for key in ("nominal", "low-energy", "sensor-outage")):
                raise ValueError("The three reference scenarios are required for a campaign")
            self.playing = False
            self.busy = True
            self.last_error = ""
            self.job_cancel.clear()
            self.campaign = {"status": "running", "total": 9 * seeds, "cases": [], "passed": None}
            self.compare_task = asyncio.create_task(self.verify(seeds))
            return {"status": "running"}
        if operation == "cancel_job":
            self.job_cancel.set()
            return {"status": "cancellation requested"}
        if operation == "recover":
            run_id = request.get("run_id", "")
            if len(run_id) != 12 or any(c not in "0123456789abcdef" for c in run_id):
                raise ValueError("Invalid recording identifier")
            if self.engine and self.engine.run_id == run_id and not self.engine.closed:
                raise ValueError("Finalize the active recording instead")
            report = recover_recording(self.workspace / "runs" / run_id)
            return {"report": report, "runs": self.runs()}
        if operation == "export":
            if not self.engine:
                raise ValueError("No live run to export")
            self.playing = False
            if not self.engine.closed:
                self.engine.recording.report()
            return {"path": str(self.engine.recording.directory / "report.html"), "runs": self.runs()}
        if operation == "finish":
            if not self.engine or self.engine.closed:
                raise ValueError("An active recording is required")
            self.playing = False
            self.engine.close(aborted=not self.engine.scenario.get("continuous") and
                              self.engine.physics.time_s < self.engine.scenario["duration_s"])
            return {"runs": self.runs()}
        if operation == "shutdown":
            self.playing = False
            self.job_cancel.set()
            self.stop.set()
            return {"status": "stopping"}
        if self.replay or not self.engine or self.engine.closed:
            raise ValueError("An active live mission is required")
        if operation == "step":
            self.playing = False
            self.engine.step()
            return {"time_s": self.engine.snapshot["time_s"]}
        if operation == "command":
            return self.engine.command(request["name"], request.get("args", []), request["request_id"])
        if operation == "sequence":
            return self.engine.sequence()
        if operation == "prepare_sequence":
            return self.engine.prepare_sequence(request.get("name"), request.get("steps"))
        if operation == "run_sequence":
            result = self.engine.run_sequence(request.get("id"), request.get("mode", "auto"))
            if result.get("mode") == "auto" and result["status"] != "failed":
                self.playing = True
            return result
        if operation == "control_sequence":
            result = self.engine.control_sequence(request.get("action"))
            if request.get("action") in ("start", "step"):
                self.playing = True
            return result
        if operation == "join_sequence":
            result = self.engine.join_sequence()
            if result.get("mode") == "auto":
                self.playing = True
            return result
        if operation == "fault":
            duration = float(request.get("duration_s", 30))
            return self.engine.inject_fault(request.get("kind", "attitude_sensor"), duration)
        if operation == "schedule_target":
            target = copy.deepcopy(request["target"])
            target.setdefault("id", self.engine.next_target_id)
            return self.engine.schedule_target(target)
        raise ValueError("Unknown operation")

    async def client(self, reader, writer):
        self.clients[writer] = "viewer"
        try:
            await self.send(writer, self.presentation())
            while not reader.at_eof():
                line = await reader.readline()
                if not line:
                    break
                request_id = None
                try:
                    def reject_constant(value):
                        raise ValueError("Non-finite JSON number: " + value)
                    request = json.loads(line, parse_constant=reject_constant)
                    if not isinstance(request, dict):
                        raise ValueError("Request must be an object")
                    request_id = request.get("request_id")
                    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 80:
                        raise ValueError("A bounded request identifier is required")
                    result = await self.handle(writer, request)
                    await self.send(writer, {"type": "reply", "request_id": request_id, "ok": True, "op": request["op"], "data": result})
                    if request["op"] not in ("status", "runs", "recordings"):
                        await self.broadcast()
                except (ValueError, KeyError, TypeError, RuntimeError, OSError) as error:
                    await self.send(writer, {"type": "reply", "request_id": request_id, "ok": False, "error": str(error)})
        except (ConnectionError, asyncio.TimeoutError, ValueError):
            pass
        finally:
            self.clients.pop(writer, None)
            if self.operator is writer:
                self.operator = None
                self.playing = False
            writer.close()
            with suppress(ConnectionError, asyncio.TimeoutError):
                await writer.wait_closed()

    async def tick(self):
        last_broadcast = 0.0
        previous_wall = time.monotonic()
        credit_s = 0.0
        previous_run = None
        previous_speed = self.speed
        rates = deque(maxlen=30)
        while not self.stop.is_set():
            started = time.monotonic()
            elapsed = min(0.5, max(0, started - previous_wall))
            previous_wall = started
            current_run = ("replay", id(self.replay)) if self.replay else ("live", self.engine.run_id if self.engine else None)
            if current_run != previous_run or self.speed != previous_speed:
                credit_s = elapsed = 0
                rates.clear()
                previous_run, previous_speed = current_run, self.speed
            if self.playing and not self.busy:
                try:
                    if self.replay:
                        self.replay_time = min(self.replay_time + self.speed * elapsed, self.replay.duration_s)
                        self.replay_snapshot = self.replay.seek(self.replay_time)
                        if self.replay_time >= self.replay.duration_s:
                            self.playing = False
                    elif self.engine and not self.engine.closed:
                        # Fractional wall-time credit is essential at 1x: a 0.5-second
                        # physical step must not execute on every 0.1-second UI tick.
                        credit_s = min(self.speed * 0.5, credit_s + self.speed * elapsed)
                        count = min(120, int((credit_s + 1e-9) / self.engine.physics.dt))
                        initial_sim_time = self.engine.physics.time_s
                        for _ in range(count):
                            self.engine.step()
                            credit_s = max(0, credit_s - self.engine.physics.dt)
                            if not self.engine.scenario.get("continuous") and self.engine.physics.time_s > self.engine.scenario["duration_s"]:
                                self.engine.close()
                                self.playing = False
                                break
                            if time.monotonic() - started > 0.08:
                                break
                        if self.engine.physics.time_s > initial_sim_time:
                            state = self.engine.snapshot
                            self.history.append({"time_s": state["time_s"], "soc_percent": state["soc_percent"],
                                                 "pointing_error_deg": state["truth_pointing_error_deg"] if state["phase_id"] in (4, 5) else None,
                                                 "generation_w": state["generation_w"], "consumed_w": state["consumed_w"],
                                                 "orbit_position_ecef_display": state["visual"]["orbit_position_ecef_display"],
                                                 "latitude_deg": state["visual"]["latitude_deg"],
                                                 "longitude_deg": state["visual"]["longitude_deg"]})
                    if self.playing:
                        sim_time = self.replay_time if self.replay else self.engine.physics.time_s
                        rates.append((started, sim_time))
                        while len(rates) > 2 and rates[0][0] < started - 2:
                            rates.popleft()
                        if len(rates) > 1:
                            self.last_tick_speed = (sim_time - rates[0][1]) / max(0.001, started - rates[0][0])
                except Exception as error:
                    self.last_error = str(error)
                    self.playing = False
            else:
                credit_s = 0
                rates.clear()
                self.last_tick_speed = 0
            # Idle clients need a heartbeat, not repeated copies of an unchanged history.
            if self.clients and (self.playing and not self.busy or started - last_broadcast >= 1):
                await self.broadcast()
                last_broadcast = started
            await asyncio.sleep(max(0.01, 0.1 - (time.monotonic() - started)))

    async def run(self, port):
        server = await asyncio.start_server(self.client, "127.0.0.1", port, limit=65536)
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self.stop.set)
        ticker = asyncio.create_task(self.tick())
        print(f"SLX OrbitLab service ready at 127.0.0.1:{port}", flush=True)
        async with server:
            await self.stop.wait()
        ticker.cancel()
        await asyncio.gather(ticker, return_exceptions=True)
        if self.compare_task:
            await self.compare_task
        self.stop_current()
        for writer in list(self.clients):
            writer.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--batch", choices=["nominal", "low-energy", "sensor-outage"])
    parser.add_argument("--strategy", choices=["priority-first", "energy-aware"], default="energy-aware")
    parser.add_argument("--rtems", action="store_true", help="Use the separately qualified RTEMS/Renode EPS node")
    args = parser.parse_args()
    workspace = args.workspace or args.root / "workspace"
    service = Service(args.root, workspace)
    if args.batch:
        print(json.dumps(run_batch(service.scenarios[args.batch], args.strategy, workspace, rtems=args.rtems), indent=2))
    else:
        asyncio.run(service.run(args.port))


if __name__ == "__main__":
    main()
