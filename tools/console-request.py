# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
"""Drive the local operator protocol for a live presentation or integration check."""
import argparse
import json
import socket
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--scenario", default="nominal")
parser.add_argument("--pause-at", type=float, default=270)
parser.add_argument("--speed", type=float, default=600)
parser.add_argument("--port", type=int, default=8765)
args = parser.parse_args()
with socket.create_connection(("127.0.0.1", args.port), timeout=20) as connection:
    stream = connection.makefile("rwb")
    def request(operation, **values):
        request_id = uuid.uuid4().hex
        stream.write(json.dumps({"op": operation, "request_id": request_id, **values}).encode() + b"\n")
        stream.flush()
        while True:
            message = json.loads(stream.readline())
            if message.get("request_id") == request_id:
                if not message["ok"]:
                    raise RuntimeError(message["error"])
                return message["data"]
    hello = request("hello", role="operator")
    if hello["role"] != "operator":
        raise RuntimeError("Another console owns the operator lease")
    request("start", scenario=args.scenario, strategy="energy-aware")
    request("speed", value=args.speed)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        message = json.loads(stream.readline())
        if message.get("type") == "snapshot" and message["snapshot"].get("time_s", 0) >= args.pause_at:
            request("pause")
            state = message["snapshot"]
            print(json.dumps({"time_s": state["time_s"], "phase": state["phase"], "completed": state["completed"], "run_id": state["run_id"]}))
            break
    else:
        raise RuntimeError("Presentation mission did not reach the requested time")
