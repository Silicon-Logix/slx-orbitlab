# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Dictionary-checked vehicle plans compiled into native F Prime sequence files."""
import json
import math
from fprime_gds.common.tools.seqgen import generateSequence


SEQUENCE_COMMANDS = frozenset({"OrbitLab.mission.DEPLOY", "OrbitLab.mission.MANEUVER",
    "OrbitLab.mission.SET_PAYLOAD", "OrbitLab.mission.SET_DOWNLINK",
    "OrbitLab.mission.SET_BEACON", "OrbitLab.cmdDisp.CMD_NO_OP",
    "OrbitLab.mission.ADD_TARGET", "OrbitLab.mission.SCHEDULE_TARGET", "OrbitLab.mission.SET_PRIORITY",
    "OrbitLab.mission.UPDATE_TARGET", "OrbitLab.mission.REMOVE_TARGET", "OrbitLab.mission.ABORT",
    "OrbitLab.mission.SET_STRATEGY", "OrbitLab.mission.ORBIT_BURN", "OrbitLab.mission.CANCEL_BURN",
    "OrbitLab.mission.REPLAN", "OrbitLab.cmdDisp.CMD_NO_OP_STRING", "OrbitLab.cmdDisp.CMD_TEST_CMD_1"})


def validate_steps(bridge, steps):
    if not isinstance(steps, list) or not 1 <= len(steps) <= 64:
        raise ValueError("A sequence must contain 1 to 64 steps.")
    result = []
    for index, step in enumerate(steps, 1):
        if not isinstance(step, dict) or step.get("name") not in SEQUENCE_COMMANDS:
            raise ValueError(f"Step {index}: choose an operational command in the dictionary.")
        args, delay = step.get("args"), step.get("delay_s", 0)
        if not isinstance(args, list) or any(isinstance(v, bool) or
            not isinstance(v, (int, float, str)) or isinstance(v, (int, float)) and not math.isfinite(v) for v in args):
            raise ValueError(f"Step {index}: use finite numbers or strings according to the dictionary.")
        if isinstance(delay, bool) or not isinstance(delay, int) or not 0 <= delay <= 86400:
            raise ValueError(f"Step {index}: the delay must be an integer between 0 and 86400 seconds.")
        name = step["name"]
        bridge.encode_command(name, args)
        if name.startswith("OrbitLab.mission.") and any(not isinstance(v, (int, float)) for v in args):
            raise ValueError(f"Step {index}: this command requires numeric parameters.")
        if name.endswith(("DEPLOY", "SET_PAYLOAD", "SET_DOWNLINK", "SET_BEACON")) and args[0] not in (0, 1):
            raise ValueError(f"Step {index}: the enable value must be 0 or 1.")
        if name.endswith("SET_BEACON") and not 1 <= args[1] <= 60:
            raise ValueError(f"Step {index}: the beacon period must be between 1 and 60 seconds.")
        if name.endswith("MANEUVER") and (args[0] not in (0, 1, 2, 3) or not -180 <= args[1] <= 180):
            raise ValueError(f"Step {index}: attitude mode 0–3 and angle between −180 and 180 degrees.")
        if name.endswith("ORBIT_BURN") and not 0.01 <= math.hypot(*args) <= 10:
            raise ValueError(f"Step {index}: total delta-v between 0.01 and 10 m/s.")
        if name.endswith("SET_STRATEGY") and args[0] not in (0, 1):
            raise ValueError(f"Step {index}: strategy 0=priority, 1=energy.")
        if name.endswith(("ADD_TARGET", "SCHEDULE_TARGET", "UPDATE_TARGET")):
            if args[0] < 1 or abs(args[1]) > math.pi / 2 or abs(args[2]) > math.pi:
                raise ValueError(f"Step {index}: positive ID and WGS84 coordinates in radians.")
        if name.endswith(("ADD_TARGET", "SCHEDULE_TARGET")) and not 0 <= args[3] <= 100:
            raise ValueError(f"Step {index}: priority must be between 0 and 100.")
        if name.endswith("SET_PRIORITY") and (args[0] < 1 or not 0 <= args[1] <= 100):
            raise ValueError(f"Step {index}: positive ID and priority between 0 and 100 required.")
        if name.endswith("SCHEDULE_TARGET") and (args[4] < 0 or 0 < args[4] < 60 or args[5] < 0):
            raise ValueError(f"Step {index}: repeat interval must be 0 or at least 60 s; deadline must be nonnegative.")
        result.append({"name": name, "args": args, "delay_s": delay})
    if sum(s["delay_s"] for s in result) > 604800:
        raise ValueError("The scheduled duration cannot exceed seven days.")
    return result


def compile_steps(bridge, directory, identifier, steps):
    source, binary = directory / (identifier + ".seq"), directory / (identifier + ".bin")
    lines = ["; Silicon LogiX / SLX OrbitLab native operational sequence"]
    for step in steps:
        hours, rest = divmod(step["delay_s"], 3600)
        minutes, seconds = divmod(rest, 60)
        args = " ".join(json.dumps(str(v)) if isinstance(v, (int, float)) and v < 0 else json.dumps(v) for v in step["args"])
        lines.append(f"R{hours:02d}:{minutes:02d}:{seconds:02d} {step['name']} {args}")
    source.write_text("\n".join(lines) + "\n", encoding="utf-8")
    generateSequence(str(source), str(binary), str(bridge.dictionary_path), 0xFFFF)
    if binary.stat().st_size > 8192:
        raise ValueError("The sequence exceeds the native 8192-byte buffer.")
    return source, binary
