# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Native F Prime GDS codecs connected to the Linux deployment's bounded host adapter."""
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
from collections import deque
from fprime_gds.common.models.dictionaries import Dictionaries
from fprime_gds.common.data_types.cmd_data import CmdData, CommandArgumentsException
from fprime_gds.common.encoders.cmd_encoder import CmdEncoder
from fprime_gds.common.decoders.event_decoder import EventDecoder
from fprime_gds.common.decoders.ch_decoder import ChDecoder
from fprime_gds.common.utils.config_manager import ConfigManager
from .sequences import SEQUENCE_COMMANDS
from .command_help import command_help


class FPrimeBridge:
    """Commands always enter Svc.CommandDispatcher; frames enter the simulation boundary."""
    def __init__(self, backend_home=None, callback=None, work_dir=None):
        self.home = Path(backend_home or os.environ.get("SLX_BACKEND_HOME", Path.home() / ".cache/slx-orbitlab"))
        self.dictionary_path = self.home / "build/Top/OrbitLabTopologyDictionary.json"
        self.dictionary = Dictionaries.load_dictionaries_into_config(str(self.dictionary_path))
        self.command_definitions = {entry["name"]: entry for entry in json.loads(
            self.dictionary_path.read_text(encoding="utf-8"))["commands"]}
        self.encoder = CmdEncoder()
        self.events_decoder = EventDecoder(self.dictionary.event_id)
        self.channels_decoder = ChDecoder(self.dictionary.channel_id)
        self.descriptor_size = ConfigManager().get_type("FwPacketDescriptorType").getSize()
        self.callback = callback or (lambda *args: None)
        self.channels, self.events, self.commands = {}, deque(maxlen=256), deque(maxlen=256)
        self.packet_count = self.packet_bytes = 0
        self.last_step_ms = 0.0
        self.sequence = 0
        self.pending_commands = {}
        self._lines = queue.Queue()
        self.process = subprocess.Popen([str(self.home / "build/bin/Linux/OrbitLab")],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=work_dir)
        self.stderr = []
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()
        threading.Thread(target=self._read_errors, daemon=True).start()
        try:
            if not self._until("READY").endswith("ABI 2"):
                raise RuntimeError("The flight deployment uses a different mission ABI. Rebuild the backend.")
        except Exception:
            self.close()
            raise

    def _read(self):
        for line in self.process.stdout:
            self._lines.put(line.rstrip())
        self._lines.put("ERROR FPRIME_PROCESS_EXITED")

    def _read_errors(self):
        for line in self.process.stderr:
            self.stderr.append(line.rstrip())
            self.stderr = self.stderr[-30:]

    def _until(self, prefix):
        while True:
            try:
                line = self._lines.get(timeout=8)
            except queue.Empty as error:
                raise RuntimeError("F Prime response timeout: " + "; ".join(self.stderr)) from error
            if line.startswith("ERROR "):
                raise RuntimeError(line)
            if line.startswith("ACK "):
                _, sequence, opcode, response = line.split()
                item = self.pending_commands.pop(int(sequence), None)
                if item is None or item["opcode"] != int(opcode):
                    raise RuntimeError("Uncorrelated F Prime command response")
                item.update(response=int(response), status="OK" if response == "0" else "REJECTED")
                self.callback("command", item)
                if line.startswith(prefix):
                    return line
                continue
            if line.startswith("SEQ_ACK "):
                _, opcode, response, timestamp = line.split()
                self.callback("sequence_command", {"opcode": int(opcode), "response": int(response),
                                                   "time_s": float(timestamp)})
                continue
            if line.startswith(("TLM ", "EVENT ")):
                kind, encoded = line.split(" ", 1)
                raw = bytes.fromhex(encoded)
                self.packet_count += 1
                self.packet_bytes += len(raw)
                self.callback("packet", {"kind": kind, "hex": encoded})
                if kind == "EVENT":
                    events = self.events_decoder.decode_api(raw[self.descriptor_size:])
                    if events is None:
                        raise RuntimeError("Native F Prime event could not be decoded")
                    for event in events:
                        item = {"name": event.template.get_full_name(), "id": event.id,
                                "severity": str(event.get_severity()), "text": event.get_display_text(),
                                "time_s": float(event.time.seconds) + float(event.time.useconds) / 1e6}
                        self.events.append(item)
                        self.callback("event", item)
                else:
                    values = self.channels_decoder.decode_api(raw[self.descriptor_size:])
                    if values is None:
                        raise RuntimeError("Native F Prime telemetry could not be decoded")
                    for value in values:
                        name = value.template.get_full_name()
                        self.channels[name] = {"name": name, "id": value.id,
                                               "value": value.get_val(), "valid": True,
                                               "time_s": float(value.time.seconds) + float(value.time.useconds) / 1e6}
                continue
            if line.startswith(prefix):
                return line

    def encode_command(self, name, args):
        template = self.dictionary.command_name.get(name)
        if template is None or len(args) != len(template.arguments):
            raise ValueError("Unknown command or incorrect argument count")
        try:
            encoded = self.encoder.encode_api(CmdData(tuple(args), template))
        except CommandArgumentsException as error:
            raise ValueError("Invalid F Prime command arguments: " + str(error)) from error
        return template, encoded

    def synchronize(self):
        self.process.stdin.write("SYNC\n")
        self.process.stdin.flush()
        self._until("SYNC")

    def submit_command(self, name, args, command_id=None):
        template, encoded = self.encode_command(name, args)
        # The native host adapter receives the Fw::CmdPacket after GDS framing is removed.
        self.sequence += 1
        packet = encoded[8:]
        self.process.stdin.write(f"CMD {self.sequence} {packet.hex()}\n")
        self.process.stdin.flush()
        item = {"id": command_id or f"cmd-{self.sequence}", "sequence": self.sequence,
                "name": name, "opcode": template.get_op_code(), "args": args,
                "response": None, "status": "PENDING",
                "packet_hex": packet.hex()}
        self.pending_commands[self.sequence] = item
        self.commands.append(item)
        self.callback("command_requested", item)
        return item

    def command(self, name, args, command_id=None):
        item = self.submit_command(name, args, command_id)
        self._until("ACK " + str(item["sequence"]) + " ")
        return item

    def clear_tracking(self, command_id=None):
        if self.pending_commands:
            raise ValueError("Wait for pending commands to complete before resetting.")
        item = self.submit_command("OrbitLab.cmdDisp.CMD_CLEAR_TRACKING", [], command_id)
        self.synchronize()
        # F Prime 4.3 clears its own tracking slot. Do not invent a native ACK for this command.
        if item["response"] is None:
            self.pending_commands.pop(item["sequence"], None)
            item["status"] = "VERIFIED_BY_PROBE"
        probe = self.command("OrbitLab.cmdDisp.CMD_NO_OP", [])
        item["probe_response"] = probe["response"]
        item["probe_sequence"] = probe["sequence"]
        self.callback("maintenance_verification", item)
        return item

    def step(self, measurement):
        values = [measurement["time_s"], *measurement["position_eci_m"],
                  *measurement["velocity_eci_mps"], *measurement["quaternion_body_to_eci"],
                  *measurement["angular_rate_body_radps"], *measurement["sun_direction_eci"],
                  measurement["energy_j"], measurement["generation_w"], measurement["consumed_w"],
                  int(measurement["attitude_valid"]), int(measurement["product_stored"]),
                  int(measurement["downlink_confirmed"])]
        values.extend([measurement["product_target_id"], measurement["delivered_target_id"],
                       int(measurement["actuator_valid"]), int(measurement["link_available"]),
                       measurement["storage_free_bytes"], measurement["storage_used_bytes"],
                       measurement["queue_depth"], measurement["sunlight_fraction"], measurement["solar_peak_w"],
                       measurement["queue_target_id"]])
        values.extend([measurement.get("propellant_kg", 1), measurement.get("delivered_delta_v_mps", 0),
                       measurement.get("step_s", 0.5), measurement.get("applied_thrust_n", 0)])
        started = time.perf_counter()
        self.process.stdin.write("STEP " + " ".join(format(v, ".17g") for v in values) + "\n")
        self.process.stdin.flush()
        result = json.loads(self._until("STATE ")[6:])
        self.last_step_ms = (time.perf_counter() - started) * 1000
        return result

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write("QUIT\n")
                self.process.stdin.flush()
                self.process.wait(timeout=3)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()

    def catalogue(self):
        return [{"name": name, "opcode": template.get_op_code(),
                 **command_help(name),
                 "argument_types": [{"name": p["name"], "type": p["type"]["name"]}
                                    for p in self.command_definitions[name]["formalParams"]],
                 "sequence_allowed": name in SEQUENCE_COMMANDS,
                 "arguments": [argument[0] for argument in template.arguments]}
                for name, template in self.dictionary.command_name.items()]
