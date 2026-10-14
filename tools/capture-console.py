# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Capture real Qt pages and verify all Godot scenes against an isolated live Linux service."""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


class Operator:
    def __init__(self, port):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.stream = self.socket.makefile("rwb")

    def request(self, operation, **values):
        identifier = uuid.uuid4().hex
        self.stream.write(json.dumps({"op": operation, "request_id": identifier, **values}).encode() + b"\n")
        self.stream.flush()
        while True:
            message = self.message()
            if message.get("request_id") == identifier:
                if not message["ok"]:
                    raise RuntimeError(message["error"])
                return message["data"]

    def message(self):
        line = self.stream.readline()
        if not line:
            raise RuntimeError("The mission service disconnected")
        return json.loads(line)

    def close(self):
        self.stream.close()
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8877)
    parser.add_argument("--distribution", default="Ubuntu-22.04")
    parser.add_argument("--campaign", action="store_true")
    args = parser.parse_args()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", args.port))
    output = ROOT / "build/screenshots"
    output.mkdir(parents=True, exist_ok=True)
    linux_root = subprocess.check_output(["wsl.exe", "-d", args.distribution, "--", "wslpath", "-a", "-u", ROOT.as_posix()], text=True).strip()
    results, operator = [], None
    log = (output / "capture-service.log").open("w", encoding="utf-8")
    service = subprocess.Popen(["wsl.exe", "-d", args.distribution, "--", "bash", linux_root + "/scripts/start-backend.sh", "--port", str(args.port)],
                               stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            try:
                operator = Operator(args.port)
                break
            except OSError:
                if service.poll() is not None:
                    raise RuntimeError("Capture service failed; inspect capture-service.log")
                time.sleep(0.1)
        if operator is None:
            raise RuntimeError("Capture service did not become ready")
        if operator.request("hello", role="operator")["role"] != "operator":
            raise RuntimeError("The capture port belongs to another operator")
        operator.request("start", scenario="nominal", strategy="energy-aware", continuous=True)
        operator.request("speed", value=600)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            message = operator.message()
            if message.get("type") == "snapshot" and message["snapshot"].get("time_s", 0) >= 270:
                operator.request("pause")
                break
        else:
            raise RuntimeError("Capture mission did not reach its observation")
        if args.campaign:
            operator.request("campaign", seed_count=1)
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                message = operator.message()
                if message.get("type") == "snapshot" and message.get("campaign", {}).get("status") == "finished":
                    if not message["campaign"]["passed"]:
                        raise RuntimeError("The captured verification campaign failed")
                    break
            else:
                raise RuntimeError("Capture campaign timed out")
        operator.close()
        operator = None
        time.sleep(0.2)
        for page in (0, 1, 4, 5):
            diagnostic = output / f"page-{page}.log"
            process = subprocess.run([str(ROOT / "build/windows-mingw/slx-orbitlab.exe"), "--root", str(ROOT),
                "--port", str(args.port), "--no-backend-start", "--page", str(page),
                "--diagnostics", str(diagnostic), "--screenshot", str(output / f"page-{page}.png")],
                capture_output=True, text=True, timeout=15)
            warnings = diagnostic.read_text(encoding="utf-8") if diagnostic.exists() else ""
            results.append({"page": page, "passed": process.returncode == 0 and not warnings.strip(),
                            "diagnostics": warnings.strip(), "stderr": process.stderr.strip()})
        godot = subprocess.run([str(ROOT / "build/tools/godot/Godot_v4.5-stable_win64_console.exe"), "--headless",
            "--path", str(ROOT / "SLX_OrbitLab_3D"), "--script", "res://godot/test_mission.gd", "--", "--backend-port", str(args.port)],
            capture_output=True, text=True, timeout=40)
        viewer = next((json.loads(line) for line in godot.stdout.splitlines() if line.startswith('{') and "slx.orbitlab.viewer-integration/1" in line), {})
        result = {"schema": "slx.orbitlab.presentation-check/1", "passed": all(r["passed"] for r in results) and viewer.get("passed", False),
                  "pages": results, "viewer": viewer, "viewer_exit_code": godot.returncode}
        (ROOT / "validation/presentation.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0 if result["passed"] else 1
    finally:
        if operator:
            operator.close()
        if service.poll() is None:
            try:
                operator = Operator(args.port)
                operator.request("hello", role="operator")
                operator.request("shutdown")
                operator.close()
                service.wait(timeout=15)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                service.terminate()
                service.wait(timeout=5)
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
