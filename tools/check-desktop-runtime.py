# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Run the Windows desktop without Qt/toolchain PATH entries or checkout working directory."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess
import tempfile


def check(application, mission=False, port=8876, output=None, screenshot=None, extended=False, console=False, early_close=False, sequences=False, orbits=False):
    environment = dict(os.environ)
    environment["PATH"] = os.pathsep.join(part for part in environment.get("PATH", "").split(os.pathsep)
                                           if "/qt/" not in part.replace("\\", "/").lower())
    for name in ("QT_PLUGIN_PATH", "QML_IMPORT_PATH", "QML2_IMPORT_PATH", "QT_QPA_PLATFORM"):
        environment.pop(name, None)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 1 if mission else subprocess.SW_HIDE  # Win32 SW_SHOWNORMAL
    # Suppress the loader's modal missing-DLL dialog; preserve its exit status as evidence.
    old_mode = ctypes.windll.kernel32.SetErrorMode(0x0001 | 0x0002 | 0x8000)
    try:
        with tempfile.TemporaryDirectory(prefix="slx-orbitlab-runtime-") as unrelated_directory:
            diagnostics = Path(unrelated_directory) / "desktop.log"
            report = Path(unrelated_directory) / "mission.json"
            arguments = [str(application), "--diagnostics", str(diagnostics)]
            arguments += ["--orbit-test" if orbits else "--sequence-test" if sequences else "--console-test" if console else "--operations-test" if extended else "--mission-test", "--port", str(port), "--report", str(report)] if mission else ["--smoke-test", "--no-backend-start"]
            if console and extended:
                arguments.append("--operations-test")
            if early_close:
                arguments.remove("--no-backend-start")
                arguments += ["--port", str(port), "--smoke-delay-ms", "200"]
            if screenshot:
                arguments += ["--screenshot", str(screenshot.resolve())]
            process = subprocess.run(arguments, cwd=unrelated_directory,
                                     env=environment, startupinfo=startup, capture_output=True,
                                     text=True, timeout=110 if console or orbits else 65 if mission else 15)
            messages = diagnostics.read_text(encoding="utf-8") if diagnostics.exists() else ""
            result = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
            if output:
                output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        passed = process.returncode == 0 and (not mission or result.get("passed") is True)
        if early_close:
            passed = passed and "Destroyed while process" not in messages
        return {"schema": "slx.orbitlab.desktop-runtime/1", "passed": passed,
                "application": str(application), "exit_code": process.returncode,
                "windows_status": f"0x{process.returncode & 0xffffffff:08x}",
                "stderr": process.stderr.strip(), "diagnostics": messages.strip(), "qt_path_removed": True,
                "checkout_working_directory": False, "mission": result}
    finally:
        ctypes.windll.kernel32.SetErrorMode(old_mode)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--application", type=Path, default=Path(__file__).resolve().parents[1] / "build/windows-mingw/slx-orbitlab.exe")
    parser.add_argument("--mission", action="store_true", help="Start the backend and execute a mission using QML actions")
    parser.add_argument("--extended", action="store_true", help="Also schedule and deliver a second target through the Operations controls")
    parser.add_argument("--console", action="store_true", help="Select and acknowledge a native command, then show all five embedded Godot scenes")
    parser.add_argument("--sequences", action="store_true", help="Validate and execute the native timed sequence, then inspect recording cards, scroll and replay")
    parser.add_argument("--orbits", action="store_true", help="Command a finite native orbital burn, verify physical dynamics and select New York through the city preset")
    parser.add_argument("--startup", action="store_true", help="Close while the owned Linux service is preparing and check process cleanup")
    parser.add_argument("--port", type=int, default=8876)
    parser.add_argument("--output", type=Path, help="Preserve the mission acceptance report")
    parser.add_argument("--screenshot", type=Path, help="Capture the confirmed mission result in the console")
    args = parser.parse_args()
    result = check(args.application.resolve(), args.mission or args.extended or args.console or args.sequences or args.orbits, args.port, args.output, args.screenshot, args.extended, args.console, args.startup, args.sequences, args.orbits)
    if args.startup and args.output:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)
