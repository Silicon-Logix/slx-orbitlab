# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Qualify ELF boot, timer interrupts, UART framing and power permissions before integration."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from orbitlab.eps import EpsController

root = Path(__file__).resolve().parents[1]
controller = EpsController()
try:
    checks = []
    first = controller.permission(0, 500000, 648000, 115)
    assert first["permitted_w"] == 115 and first["flags"] == 0
    checks.append("Nominal power permission")
    limited = controller.permission(0.5, 20000, 648000, 115)
    assert limited["permitted_w"] == 18 and limited["flags"] == 1
    checks.append("Low-energy load shedding")
    critical = controller.permission(1, 5000, 648000, 115)
    assert critical["permitted_w"] == 5 and critical["flags"] == 3
    checks.append("Critical-energy load shedding")
    malformed = controller.raw("EPS 77 0 10000 648000 115000 00000000", "EPS_ERR")
    assert malformed == "EPS_ERR CRC"
    checks.append("Malformed UART CRC rejected")
    after = controller.permission(2, 500000, 648000, 35)
    assert after["heartbeat"] > first["heartbeat"]
    # The timer heartbeat is 100 ms; elapsed virtual time is 2 seconds across four requests.
    assert 15 <= after["heartbeat"] - first["heartbeat"] <= 25
    checks.extend(["RTEMS periodic task and timer interrupts", "Recovery after malformed frame"])
    result = {"schema": "slx.orbitlab.embedded-qualification/1", "passed": True,
              "identity": controller.identity, "checks": checks,
              "first_response": first, "final_response": after,
              "loader": "ELF with explicit boot stack and CLOCK_SPEED; no physical board or PROM image"}
    directory = root / "validation"
    directory.mkdir(exist_ok=True)
    (directory / "rtems-renode.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
finally:
    controller.close()
