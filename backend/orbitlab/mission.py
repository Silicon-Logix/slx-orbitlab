# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Coordinate real flight software and physical simulation; persist and verify synthetic products."""
import copy
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import uuid
from collections import deque, OrderedDict
import numpy as np
from Basilisk.utilities import RigidBodyKinematics as rbk
from fprime_gds.common.tools.seqgen import generateSequence
from .fprime_bridge import FPrimeBridge
from .physics import Physics, PHASES, EARTH_RATE, ecef_point, rotate_z
from .evidence import Recording, digest
from .optics import EarthCamera
from .sequences import validate_steps, compile_steps


def validate_scenario(scenario):
    if scenario.get("schema") != "slx.orbitlab.scenario/1":
        raise ValueError("Unsupported scenario schema")
    continuous = scenario.get("continuous", False)
    if not isinstance(continuous, bool):
        raise ValueError("Continuous mode must be boolean")
    if not continuous and (not isinstance(scenario.get("duration_s"), (int, float)) or
                           not math.isfinite(scenario["duration_s"]) or not 1 <= scenario["duration_s"] <= 604800):
        raise ValueError("Invalid scenario parameter: duration_s")
    for key, low, high in (("step_s", 0.1, 2),
                           ("altitude_m", 200000, 1500000), ("capacity_j", 10000, 1e8),
                           ("initial_soc", 0, 1), ("reserve_fraction", 0.02, 0.5), ("propellant_kg", 0, 1)):
        value = scenario.get(key, 1.0 if key == "propellant_kg" else None)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError("Invalid scenario parameter: " + key)
    if not isinstance(scenario.get("seed"), int) or not 0 <= scenario["seed"] <= 2147483647:
        raise ValueError("Invalid random seed")
    if not 1 <= len(scenario.get("targets", [])) <= 16:
        raise ValueError("The mission requires one to sixteen targets")
    seen = set()
    for target in scenario["targets"] + [scenario["ground_station"]]:
        for key, low, high in (("latitude_deg", -90, 90), ("longitude_deg", -180, 180)):
            value = target.get(key)
            if not isinstance(value, (float, int)) or not math.isfinite(value) or not low <= value <= high:
                raise ValueError("Invalid geographic coordinate")
        if "priority" in target:
            if not isinstance(target["priority"], int) or not 0 <= target["priority"] <= 100:
                raise ValueError("Invalid target priority")
            if not isinstance(target["id"], int) or not 0 < target["id"] <= 4294967295 or target["id"] in seen:
                raise ValueError("Invalid or duplicate target identifier")
            seen.add(target["id"])
            for field in ("repeat_s", "deadline_s"):
                value = target.get(field, 0)
                if not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 1e12:
                    raise ValueError("Invalid target " + field)
            if 0 < target.get("repeat_s", 0) < 60:
                raise ValueError("Repeat interval must be at least sixty seconds")
            if not isinstance(target.get("name", "Target"), str) or len(target.get("name", "Target")) > 80:
                raise ValueError("Target name must contain at most eighty characters")
    for fault in scenario.get("faults", []):
        if (fault["kind"] not in ("attitude_sensor", "solar_generation", "reaction_wheel", "ground_link") or
            not all(isinstance(fault.get(key), (int, float)) and math.isfinite(fault[key]) for key in ("start_s", "end_s")) or
            not 0 <= fault["start_s"] < fault["end_s"] or
            (not continuous and fault["end_s"] > scenario["duration_s"])):
            raise ValueError("Invalid fault interval")
    for key, default, low, high in (("storage_capacity_bytes", 2097152, 65588, 1073741824),
                                   ("recording_quota_bytes", 2147483648, 1048576, 68719476736),
                                   ("segment_duration_s", 1800, 10, 86400)):
        value = scenario.get(key, default)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError("Invalid scenario parameter: " + key)
    return copy.deepcopy(scenario)


class MissionRun:
    def __init__(self, scenario, strategy, workspace, backend_home=None, rtems=False):
        self.scenario = validate_scenario(scenario)
        if strategy not in ("priority-first", "energy-aware"):
            raise ValueError("Unknown mission strategy")
        self.strategy = strategy
        self.run_id = uuid.uuid4().hex[:12]
        versions = {name: importlib.metadata.version(name) for name in ("bsk", "fprime-gds", "fprime-tools")}
        versions["core"] = "0.6.0 / ABI 2"
        self.recording = Recording(Path(workspace) / "runs" / self.run_id,
                                   {"run_id": self.run_id, "strategy": strategy, "scenario": self.scenario,
                                    "versions": versions})
        self.products = deque()
        self.faults = copy.deepcopy(self.scenario["faults"])
        self.recent_products = deque(maxlen=64)
        self.targets = copy.deepcopy(self.scenario["targets"])
        self.next_target_id = max(t["id"] for t in self.targets) + 1
        for target in self.targets:
            target.update(status="pending", acquired=0, delivered=0, last_capture_s=None)
        self.product_serial = self.delivered_bytes = 0
        self.stored_ack = self.delivered_ack = 0
        self.storage_capacity = self.scenario.get("storage_capacity_bytes", 2097152)
        self.command_ids = OrderedDict()
        self.snapshot = {}
        self.prepared_sequence = {}
        self.sequence_status = {}
        self._in_step = False
        self.closed = False
        self.bridge = None
        self.eps = None
        self.rtems_enabled = rtems
        try:
            self.bridge = FPrimeBridge(backend_home, self._native_record, self.recording.directory)
            self.physics = Physics(self.scenario)
            ground = self.scenario["ground_station"]
            preparation = [("OrbitLab.mission.CONFIGURE", [self.scenario["capacity_j"], self.scenario["reserve_fraction"],
                math.radians(ground["latitude_deg"]), math.radians(ground["longitude_deg"]), int(strategy == "energy-aware")])]
            for target in self.scenario["targets"]:
                preparation.append(("OrbitLab.mission.SCHEDULE_TARGET", [target["id"], math.radians(target["latitude_deg"]),
                    math.radians(target["longitude_deg"]), target["priority"], target.get("repeat_s", 0), target.get("deadline_s", 0)]))
            preparation.append(("OrbitLab.mission.DEPLOY", [1]))
            self.sequence("deployment", preparation)
            if rtems:
                from .eps import EpsController
                self.eps = EpsController(backend_home)
                qualification = Path(__file__).resolve().parents[2] / "validation/rtems-renode.json"
                qualified = json.loads(qualification.read_text())
                if not qualified.get("passed") or qualified["identity"]["firmware_sha256"] != self.eps.identity["firmware_sha256"]:
                    raise ValueError("Run tools/qualify-rtems.py for this firmware before enabling integration")
                self.recording.record("eps_identity", self.eps.identity)
            metadata = json.loads(self.recording.db.execute("SELECT value FROM metadata WHERE key='run'").fetchone()[0])
            metadata["rtems_enabled"] = rtems
            metadata["identity"] = {"flight_binary_sha256": digest(self.bridge.home / "build/bin/Linux/OrbitLab"),
                                    "dictionary_sha256": digest(self.bridge.dictionary_path),
                                    "core_binary_sha256": digest(self.bridge.home / "build/lib/Linux/SiliconLogiX.OrbitLab.Core.so")}
            if self.eps:
                metadata["identity"]["eps"] = self.eps.identity
            self.recording.db.execute("UPDATE metadata SET value=? WHERE key='run'", (json.dumps(metadata, allow_nan=False),))
            self.step(advance=False)
        except Exception:
            if self.bridge:
                self.bridge.close()
            if self.eps:
                self.eps.close()
            self.recording.close(aborted=True)
            raise

    def command(self, name, args, command_id=None):
        if name.startswith("OrbitLab.cmdSeq."):
            raise ValueError("Use the F Prime sequences page to validate the plan and manage execution.")
        if name.endswith("CMD_CLEAR_TRACKING") and self.sequence_status.get("status") in ("running", "loaded", "waiting_step"):
            raise ValueError("Cancel the sequence before resetting dispatcher tracking.")
        if command_id and command_id in self.command_ids:
            previous = self.command_ids[command_id]
            if previous["name"] != name or previous["args"] != args:
                raise ValueError("Command identifier reused with different arguments")
            return previous
        if name.endswith("CONFIGURE") and self.snapshot:
            raise ValueError("Use the Mission page to configure and start a new session.")
        if name.endswith(("ADD_TARGET", "SCHEDULE_TARGET")) and self.snapshot:
            active = [t for t in self.targets if t["status"] not in ("retired", "expired", "acquired", "delivered")]
            if len(active) >= 16:
                raise ValueError("Sixteen active jobs are already scheduled")
        if name.endswith("CMD_CLEAR_TRACKING"):
            if args:
                raise ValueError("Reset accepts no parameters.")
            result = self.bridge.clear_tracking(command_id)
        else:
            result = self.bridge.command(name, args, command_id)
        result["accepted_s"] = self.recording.time_s
        if command_id:
            self.command_ids[command_id] = result
            if len(self.command_ids) > 1024:
                self.command_ids.popitem(last=False)
        if result["response"] != 0:
            return result
        if self.snapshot:
            self.recording.record("operator_stimulus", {"name": name, "args": args,
                "boundary": "before_frame" if self.physics.time_s == self.snapshot["time_s"] else "after_frame"})
        self._apply_command_metadata(name, args)
        self._refresh_catalogue()
        return result

    def _apply_command_metadata(self, name, args):
        if name.endswith(("ADD_TARGET", "SCHEDULE_TARGET")) and self.snapshot:
            self.targets = [t for t in self.targets if t["status"] not in ("retired", "expired", "acquired", "delivered")]
            target = {"id": args[0], "name": "Target T" + str(args[0]), "latitude_deg": math.degrees(args[1]),
                      "longitude_deg": math.degrees(args[2]), "priority": args[3],
                      "repeat_s": args[4] if len(args) > 4 else 0, "deadline_s": args[5] if len(args) > 5 else 0,
                      "status": "pending", "acquired": 0, "delivered": 0, "last_capture_s": None}
            self.targets.append(target)
            self.next_target_id = max(self.next_target_id, target["id"] + 1)
            self.recording.record("scenario_change", {"operation": "add_target", "target": target})
        elif name.endswith("UPDATE_TARGET"):
            for target in self.targets:
                if target["id"] == args[0]:
                    target.update(latitude_deg=math.degrees(args[1]), longitude_deg=math.degrees(args[2]))
            self.recording.record("scenario_change", {"operation": "coordinates", "args": args})
        elif name.endswith("SET_STRATEGY"):
            self.strategy = "energy-aware" if args[0] else "priority-first"
            self.recording.record("strategy_change", {"strategy": self.strategy})
        elif name.endswith("SET_PRIORITY"):
            for target in self.targets:
                if target["id"] == args[0]:
                    target["priority"] = args[1]
            self.recording.record("scenario_change", {"operation": "priority", "args": args})
        elif name.endswith("REMOVE_TARGET") or name.endswith("ABORT"):
            for target in self.targets:
                if name.endswith("ABORT") or target["id"] == args[0]:
                    target["status"] = "retired"
            self.recording.record("scenario_change", {"operation": "retire", "args": args})

    def _refresh_catalogue(self):
        # A native acknowledgement confirms job metadata while physics can remain paused.
        # No sensor read, physical step or file-transfer quantum is caused by a GUI command.
        if self.snapshot:
            self.snapshot["targets"] = self._target_status(self.snapshot["time_s"])
            self.snapshot["next_target_id"] = self.next_target_id
            self.recording.frame(self.snapshot)

    def schedule_target(self, target):
        candidate = copy.deepcopy(self.scenario)
        candidate["targets"] = [target]
        validate_scenario(candidate)
        result = self.command("OrbitLab.mission.SCHEDULE_TARGET", [target["id"],
            math.radians(target["latitude_deg"]), math.radians(target["longitude_deg"]), target["priority"],
            target.get("repeat_s", 0), target.get("deadline_s", 0)])
        if result["response"]:
            raise ValueError("F Prime rejected the observation job")
        self.targets[-1]["name"] = target.get("name", "Operator target")
        self.recording.record("job_label", {"target": self.targets[-1]})
        self._refresh_catalogue()
        return result

    def sequence(self, name="panel-deployment", commands=None):
        if self.sequence_status.get("status") in ("running", "loaded", "waiting_step"):
            raise ValueError("Complete or cancel the active sequence before running another.")
        commands = commands or [("OrbitLab.mission.DEPLOY", [1]), ("OrbitLab.cmdDisp.CMD_NO_OP", [])]
        text = "; Silicon LogiX / SLX OrbitLab operational sequence\n"
        for mnemonic, args in commands:
            # GDS 4.3's text grammar has unsigned number literals. Quoted signed values
            # are converted by its dictionary-driven argument types without patching GDS.
            text += "R00:00:00 " + mnemonic + " " + " ".join(
                json.dumps(str(value)) if isinstance(value, (int, float)) and value < 0 else json.dumps(value)
                for value in args) + "\n"
        source = self.recording.directory / (name + ".seq")
        binary = self.recording.directory / (name + ".bin")
        source.write_text(text, encoding="utf-8")
        generateSequence(str(source), str(binary), str(self.bridge.dictionary_path), 0xFFFF)
        self.recording.record("sequence", {"name": name, "commands": commands, "timing": "immediate", "block": "BLOCK"})
        mode = self.bridge.command("OrbitLab.cmdSeq.CS_AUTO", [])
        if mode["response"]:
            raise ValueError("F Prime did not accept automatic mode.")
        result = self.bridge.command("OrbitLab.cmdSeq.CS_RUN", [binary.name, "BLOCK"])
        if result["response"] != 0:
            raise RuntimeError("F Prime rejected the prepared operational sequence")
        if self.snapshot:
            for mnemonic, args in commands:
                self.recording.record("operator_stimulus", {"name": mnemonic, "args": args,
                    "boundary": "before_frame" if self.physics.time_s == self.snapshot["time_s"] else "after_frame"})
        return result

    def _native_record(self, kind, item):
        self.recording.record(kind, item)
        state = self.sequence_status
        if kind == "command" and state.get("join_wait", {}).get("sequence") == item.get("sequence"):
            state["join_wait"].update(status="confirmed" if item["response"] == 0 else "rejected",
                                      response=item["response"], confirmed_s=self.recording.time_s)
            self.recording.record("sequence_join_result", state["join_wait"])
        if not state or "finished_s" in state or state.get("status") not in ("running", "loaded", "waiting_step", "failed"):
            return
        if kind == "sequence_command":
            index = state["completed_steps"]
            if index >= len(state["steps"]):
                return
            row = state["steps"][index]
            template = self.bridge.dictionary.command_name[row["name"]]
            if item["opcode"] != template.get_op_code():
                raise RuntimeError("Native sequence response does not match the prepared step")
            row.update(response=item["response"], executed_s=item["time_s"],
                       status="accepted" if item["response"] == 0 else "rejected")
            if item["response"] == 0:
                state["completed_steps"] += 1
                state["status"] = "waiting_step" if state["mode"] == "manual" else "running"
                self.recording.record("operator_stimulus", {"name": row["name"], "args": row["args"],
                    "boundary": "before_frame" if self._in_step or self.physics.time_s == self.snapshot.get("time_s") else "after_frame"})
                self._apply_command_metadata(row["name"], row["args"])
            else:
                state["status"] = "failed"
            self.recording.record("sequence_step", {"sequence_id": state["id"], "name": row["name"],
                "args": row["args"], "index": index + 1, **item})
        elif kind == "event" and state["file_name"] in item["text"]:
            event = item["name"].rsplit(".", 1)[-1]
            if event == "CS_SequenceComplete":
                state["status"] = "completed"
            elif event == "CS_SequenceCanceled":
                state["status"] = "canceled"
            elif event in ("CS_CommandError", "CS_SequenceTimeout", "CS_RecordInvalid", "CS_FileInvalid"):
                state["status"] = "failed"
            if state["status"] in ("completed", "canceled", "failed"):
                state["finished_s"] = item["time_s"]
                self.recording.record("sequence_result", copy.deepcopy(state))

    def _publish_sequence(self):
        if self.snapshot:
            self.snapshot["sequence"] = copy.deepcopy(self.sequence_status)
            self.recording.frame(self.snapshot)

    def prepare_sequence(self, name, steps):
        if self.sequence_status.get("status") in ("running", "loaded", "waiting_step"):
            raise ValueError("Complete or cancel the active sequence before validating another.")
        if not isinstance(name, str) or not name.strip() or len(name) > 64:
            raise ValueError("The sequence name must contain 1 to 64 characters.")
        steps = validate_steps(self.bridge, steps)
        identifier = "sequence-" + uuid.uuid4().hex[:12]
        source, binary = compile_steps(self.bridge, self.recording.directory, identifier, steps)
        result = self.bridge.command("OrbitLab.cmdSeq.CS_VALIDATE", [binary.name])
        self.bridge.synchronize()
        if result["response"] != 0:
            raise ValueError("Native F Prime sequence validation failed.")
        self.prepared_sequence = {"id": identifier, "run_id": self.run_id, "name": name.strip(),
            "steps": steps, "file_name": binary.name, "sha256": digest(binary),
            "dictionary_sha256": digest(self.bridge.dictionary_path), "size_bytes": binary.stat().st_size,
            "delay_total_s": sum(s["delay_s"] for s in steps), "validated": True}
        self.recording.record("sequence_prepared", self.prepared_sequence)
        self.sequence_status = {**copy.deepcopy(self.prepared_sequence), "status": "validated", "completed_steps": 0}
        self._publish_sequence()
        return copy.deepcopy(self.prepared_sequence)

    def run_sequence(self, identifier, mode):
        if identifier != self.prepared_sequence.get("id") or mode not in ("auto", "manual"):
            raise ValueError("Validate the sequence and choose automatic or manual execution.")
        if self.sequence_status.get("status") in ("running", "loaded", "waiting_step"):
            raise ValueError("A sequence is already active.")
        plan = self.prepared_sequence
        if digest(self.recording.directory / plan["file_name"]) != plan["sha256"]:
            raise ValueError("The sequence changed after validation: validate it again.")
        result = self.bridge.command("OrbitLab.cmdSeq.CS_AUTO" if mode == "auto" else "OrbitLab.cmdSeq.CS_MANUAL", [])
        if result["response"]:
            raise ValueError("F Prime did not accept the execution mode.")
        self.sequence_status = {**copy.deepcopy(plan), "mode": mode, "started_s": self.snapshot["time_s"],
                                "status": "running" if mode == "auto" else "loaded", "completed_steps": 0}
        for row in self.sequence_status["steps"]:
            row["status"] = "pending"
        self.recording.record("sequence_started", self.sequence_status)
        result = self.bridge.command("OrbitLab.cmdSeq.CS_RUN", [plan["file_name"], "NO_BLOCK"])
        self.bridge.synchronize()
        if result["response"]:
            self.sequence_status["status"] = "failed"
        self._publish_sequence()
        return copy.deepcopy(self.sequence_status)

    def control_sequence(self, operation):
        state = self.sequence_status
        previous_status = state.get("status")
        if state.get("status") not in ("running", "loaded", "waiting_step"):
            raise ValueError("There is no active sequence.")
        allowed = {"cancel": "CS_CANCEL"}
        if state.get("mode") == "manual":
            if state["status"] == "loaded":
                allowed["start"] = "CS_START"
            elif state["status"] == "waiting_step":
                allowed["step"] = "CS_STEP"
        if operation not in allowed:
            raise ValueError("Wait for the current step's response before advancing.")
        if operation != "cancel":
            state["status"] = "running"
        result = self.bridge.command("OrbitLab.cmdSeq." + allowed[operation], [])
        self.bridge.synchronize()
        if operation == "cancel" and previous_status == "loaded" and result["response"] == 0:
            state.update(status="canceled", finished_s=self.snapshot["time_s"])
            self.recording.record("sequence_result", copy.deepcopy(state))
        self._publish_sequence()
        if result["response"]:
            raise ValueError("The F Prime sequencer rejected the command.")
        return copy.deepcopy(state)

    def join_sequence(self):
        state = self.sequence_status
        if state.get("status") not in ("running", "waiting_step"):
            raise ValueError("Start a sequence before waiting for completion.")
        if state.get("join_wait", {}).get("status") == "waiting":
            raise ValueError("A sequence completion wait is already active.")
        item = self.bridge.submit_command("OrbitLab.cmdSeq.CS_JOIN_WAIT", [])
        state["join_wait"] = {"sequence": item["sequence"], "status": "waiting", "response": None}
        self.bridge.synchronize()
        self.recording.record("sequence_join_wait", state["join_wait"])
        self._publish_sequence()
        return copy.deepcopy(state)

    def _store(self, sample, control):
        directory = self.recording.directory / "products"
        directory.mkdir(exist_ok=True)
        index = control["target_id"]
        camera = EarthCamera()
        pixels, geometry = camera.acquire(sample)
        data = b"P5\n# SLX OrbitLab synthetic observation\n256 256\n255\n" + pixels.tobytes()
        self.product_serial += 1
        source = directory / f"observation-{index}-{self.product_serial:06d}.pgm"
        source.write_bytes(data)
        target = next(target for target in self.targets if target["id"] == index)
        preview = source.with_suffix(".png")
        camera.preview(preview, pixels, target, geometry, sample["time_s"])
        product = {"product_id": self.product_serial, "target_id": index, "path": source,
                   "filename": source.name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                   "sent_bytes": 0, "capture_s": sample["time_s"], "status": "stored",
                   "preview_filename": preview.name, "target_name": target["name"], "geometry": geometry,
                   "target_latitude_deg": target["latitude_deg"], "target_longitude_deg": target["longitude_deg"]}
        self.products.append(product)
        self.recent_products.append(product)
        self.stored_ack = index
        for target in self.targets:
            if target["id"] == index:
                target["acquired"] += 1
                target["last_capture_s"] = sample["time_s"]
                target["status"] = "cooldown" if target.get("repeat_s", 0) else "acquired"
        self.recording.record("product_stored", {key: value for key, value in product.items() if key != "path"})

    def _transfer(self):
        ground = self.recording.directory / "ground"
        ground.mkdir(exist_ok=True)
        product = self.products[0]
        destination = ground / product["filename"]
        count = min(int(8192 * self.scenario["step_s"]), product["size"] - product["sent_bytes"])
        with product["path"].open("rb") as source, destination.open("ab" if product["sent_bytes"] else "wb") as receiver:
            source.seek(product["sent_bytes"])
            receiver.write(source.read(count))
        product["sent_bytes"] += count
        self.delivered_bytes += count
        product["status"] = "downlink"
        if product["sent_bytes"] == product["size"]:
            if hashlib.sha256(destination.read_bytes()).hexdigest() != product["sha256"]:
                raise RuntimeError("Ground data checksum mismatch")
            product["status"] = "delivered"
            from PIL import Image
            received = np.asarray(Image.open(destination))
            EarthCamera().preview(destination.with_suffix(".png"), received,
                {"name": product["target_name"], "latitude_deg": product["target_latitude_deg"],
                 "longitude_deg": product["target_longitude_deg"]}, product["geometry"], product["capture_s"])
            product["delivery_s"] = self.physics.time_s
            self.delivered_ack = product["target_id"]
            self.products.popleft()
            for target in self.targets:
                if target["id"] == product["target_id"]:
                    target["delivered"] += 1
                    if not target.get("repeat_s", 0):
                        target["status"] = "delivered"
            self.recording.record("product_delivered", {key: value for key, value in product.items() if key != "path"})

    def step(self, advance=True):
        if self.closed:
            raise ValueError("This mission session is closed")
        self.faults = [f for f in self.faults if f["end_s"] >= self.physics.time_s]
        sample = self.physics.measurement(bool(self.stored_ack), bool(self.delivered_ack), self.faults)
        used_bytes = sum(p["size"] for p in self.products)
        sample.update(product_target_id=self.stored_ack, delivered_target_id=self.delivered_ack,
                      storage_free_bytes=self.storage_capacity - used_bytes, storage_used_bytes=used_bytes,
                      queue_depth=len(self.products), queue_target_id=self.products[0]["target_id"] if self.products else 0)
        self.recording.time_s = sample["time_s"]
        self._in_step = True
        try:
            control = self.bridge.step(sample)
        finally:
            self._in_step = False
        self.stored_ack = self.delivered_ack = 0
        eps_status = {"mode": "Host reference", "permitted_w": control["load_w"], "flags": 0, "heartbeat": 0}
        if self.eps:
            eps_status = self.eps.permission(sample["time_s"], sample["energy_j"], self.scenario["capacity_j"], control["load_w"], self.scenario["step_s"] if advance else 0.001)
            control["load_w"] = eps_status["permitted_w"]
            if eps_status["flags"]:
                control["capture"] = control["downlink"] = 0
                control.get("orbit", {})["force_body_n"] = [0, 0, 0]
                if "vehicle" in control:
                    control["vehicle"]["beacon_on"] = 0
            self.recording.record("eps_permission", eps_status)
        if control["capture"]:
            self._store(sample, control)
        if control["downlink"] and self.products:
            self._transfer()
        target = next((target for target in self.targets if target["id"] == control["target_id"]), self.scenario["targets"][0])
        ground = rotate_z(ecef_point(math.radians(target["latitude_deg"]), math.radians(target["longitude_deg"])), EARTH_RATE * sample["time_s"])
        direction = ground - sample["position_eci_m"]
        direction /= np.linalg.norm(direction)
        optical = rbk.EP2C(sample["truth_quaternion_body_to_eci"]).T @ np.array([0, -1, 0])
        pointing_truth = math.degrees(math.acos(float(np.clip(np.dot(optical, direction), -1, 1))))
        self.snapshot = {**sample, **control, "phase_id": control["phase"], "phase": PHASES[control["phase"]],
            "schema": "slx.orbitlab.snapshot/1", "mode": "LIVE", "run_id": self.run_id,
            "scenario_name": self.scenario["name"], "strategy": self.strategy,
            "duration_s": None if self.scenario.get("continuous") else self.scenario["duration_s"],
            "continuous": self.scenario.get("continuous", False), "epoch_utc": self.scenario["epoch_utc"],
            "soc_percent": sample["energy_j"] / self.scenario["capacity_j"] * 100,
            "capacity_j": self.scenario["capacity_j"], "reserve_percent": self.scenario["reserve_fraction"] * 100,
            "pointing_error_deg": math.degrees(control["pointing_error_rad"]), "truth_pointing_error_deg": pointing_truth,
            "stored_bytes": sum(p["size"] for p in self.products), "delivered_bytes": self.delivered_bytes,
            "storage_capacity_bytes": self.storage_capacity, "queue_depth": len(self.products),
            "next_target_id": self.next_target_id,
            "targets": self._target_status(sample["time_s"]),
            "ground_station": self.scenario["ground_station"],
            "products": [{key: value for key, value in p.items() if key != "path"} for p in self.recent_products],
            "runtime": {"native_packets": self.bridge.packet_count, "native_bytes": self.bridge.packet_bytes,
                        "fprime_step_ms": self.bridge.last_step_ms, "step_s": self.physics.dt,
                        "core_abi": 2, "prediction_grid_s": 10, "prediction_horizon_s": 12000},
            "recording": self.recording.telemetry_status(),
            "attitude_estimation_error_deg": math.degrees(2 * math.acos(float(np.clip(abs(np.dot(
                sample["quaternion_body_to_eci"], sample["truth_quaternion_body_to_eci"])), 0, 1)))),
            "eps": eps_status,
            "sequence": copy.deepcopy(self.sequence_status),
            "initial_orbit_target": self.scenario["targets"][0]["name"],
            "visual": self.physics.visual(sample, control), "channels": list(self.bridge.channels.values())}
        self.recording.frame(self.snapshot)
        if advance:
            self.physics.advance(control)
        return self.snapshot

    def presentation(self):
        return {**self.snapshot, "events": list(self.bridge.events)[-80:], "commands": list(self.bridge.commands)[-100:]}

    def _target_status(self, time_s):
        for target in self.targets:
            if target["status"] in ("retired", "expired", "delivered", "acquired"):
                continue
            if target.get("deadline_s", 0) and time_s >= target["deadline_s"]:
                target["status"] = "expired"
            elif target.get("repeat_s", 0) and target["last_capture_s"] is not None:
                target["status"] = "cooldown" if time_s < target["last_capture_s"] + target["repeat_s"] else "pending"
        return copy.deepcopy(self.targets)

    def inject_fault(self, kind, duration):
        now = self.physics.time_s
        if kind not in ("attitude_sensor", "solar_generation", "reaction_wheel", "ground_link"):
            raise ValueError("Unknown physical fault")
        if not math.isfinite(duration) or not 0 < duration <= 86400 or len(self.faults) >= 128:
            raise ValueError("Fault interval or pending fault count exceeds limits")
        if not self.scenario.get("continuous") and now + duration > self.scenario["duration_s"]:
            raise ValueError("Fault duration exceeds mission limits")
        fault = {"kind": kind, "start_s": now, "end_s": now + duration}
        self.faults.append(fault)
        self.recording.record("fault_injection", fault)
        return fault

    def close(self, aborted=False):
        if self.closed:
            return
        if self.sequence_status.get("status") in ("running", "loaded", "waiting_step"):
            self.control_sequence("cancel")
        self.closed = True
        self.bridge.close()
        if self.eps:
            self.eps.close()
        return self.recording.close(aborted)


def run_batch(scenario, strategy, workspace, rtems=False, evaluation_s=None, cancel=None):
    horizon = evaluation_s if evaluation_s is not None else scenario.get("duration_s")
    if (scenario.get("continuous") and evaluation_s is None) or not isinstance(horizon, (int, float)) or not math.isfinite(horizon) or not 1 <= horizon <= 604800:
        raise ValueError("Batch verification requires a finite evaluation interval")
    run = MissionRun(scenario, strategy, workspace, rtems=rtems)
    try:
        before = deque(sorted((item for item in scenario.get("operator_stimuli", []) if item.get("boundary") == "before_frame"), key=lambda item: item["time_s"]))
        after = deque(sorted((item for item in scenario.get("operator_stimuli", []) if item.get("boundary", "after_frame") == "after_frame"), key=lambda item: item["time_s"]))
        def apply_ready(stimuli, time_s):
            while stimuli and stimuli[0]["time_s"] <= time_s:
                item = stimuli.popleft()
                result = run.command(item["name"], item["args"])
                if result["response"]:
                    raise ValueError("Recorded operator stimulus was rejected")
        while run.physics.time_s <= horizon:
            if cancel and cancel.is_set():
                return run.close(aborted=True)
            apply_ready(before, run.physics.time_s)
            run.step()
            apply_ready(after, run.snapshot["time_s"])
        return run.close()
    except Exception:
        run.close(aborted=True)
        raise
