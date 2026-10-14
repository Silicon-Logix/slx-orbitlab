# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Repeatable verification campaigns trace requirements to executed flight software evidence."""
import copy
import json
from pathlib import Path
import uuid
import html
from .mission import run_batch
from .evidence import atomic_json, read_rows, digest


def campaign_cases(scenarios, seed):
    cases = []
    for name in ("nominal", "low-energy", "sensor-outage"):
        value = copy.deepcopy(scenarios[name])
        value.update(duration_s=500, seed=seed)
        cases.append((name, value))
    for kind in ("reaction_wheel", "solar_generation", "ground_link"):
        value = copy.deepcopy(scenarios["nominal"])
        value.update(duration_s=500, seed=seed,
                     faults=[{"kind": kind, "start_s": 100 if kind != "ground_link" else 200,
                              "end_s": 220 if kind != "ground_link" else 320}])
        cases.append((kind, value))
    value = copy.deepcopy(scenarios["nominal"])
    value.update(duration_s=500, seed=seed)
    value["targets"].append({**value["targets"][0], "id": 2, "name": "Second observation", "priority": 70})
    cases.append(("multiple-products", value))
    value = copy.deepcopy(value)
    value["storage_capacity_bytes"] = 65588
    value["faults"] = [{"kind": "ground_link", "start_s": 0, "end_s": 500}]
    cases.append(("storage-pressure", value))
    value = copy.deepcopy(scenarios["nominal"])
    value.update(duration_s=60, continuous=True, seed=seed, segment_duration_s=120)
    cases.append(("continuous-session", value))
    return cases


def assess_case(case, scenario, report, workspace):
    checks = list(report["checks"])
    if case in ("nominal", "sensor-outage", "reaction_wheel", "solar_generation", "ground_link", "continuous-session"):
        checks.append({"id": "SLX-MISSION-001", "name": "Observation delivered after recovery", "passed": report["completed_observations"] >= 1})
    if case == "low-energy":
        checks.append({"id": "SLX-POWER-001", "name": "Low energy defers the first observation", "passed": report["deferred_observations"] > 0 and report["completed_observations"] == 0})
    if case == "multiple-products":
        checks.append({"id": "SLX-DATA-002", "name": "Two separate products acquired and delivered", "passed": report["completed_observations"] == 2})
    if case == "storage-pressure":
        checks.append({"id": "SLX-STORE-002", "name": "Full memory inhibits additional acquisition", "passed": report["acquired_observations"] == 1 and report["pending_products"] == 1})
    if case == "continuous-session":
        checks.append({"id": "SLX-CONT-001", "name": "Session exceeds the original end time and rotates evidence segments", "passed": report["duration_s"] >= 650 and report["segments"] >= 5})
    fault_errors = 0
    tested_frames = 0
    for row in read_rows(Path(workspace) / "runs" / report["run_id"], "SELECT snapshot FROM frames ORDER BY time_s"):
        state = json.loads(row[0])
        for fault in scenario["faults"]:
            if fault["start_s"] + scenario["step_s"] <= state["time_s"] < fault["end_s"]:
                tested_frames += 1
                kind = fault["kind"]
                if kind == "attitude_sensor":
                    fault_errors += int(state["attitude_valid"] or bool(state["capture"]) or any(state["torque_body_nm"]))
                elif kind == "reaction_wheel":
                    fault_errors += int(state["actuator_valid"] or bool(state["capture"]) or any(state["torque_body_nm"]))
                elif kind == "solar_generation":
                    fault_errors += int(abs(state["generation_w"]) > 1e-6)
                elif kind == "ground_link":
                    fault_errors += int(state["link_available"] or bool(state["downlink"]))
    if scenario["faults"]:
        checks.append({"id": "SLX-FAULT-001", "name": "Injected faults affect physical operation", "passed": tested_frames > 0 and fault_errors == 0})
    return {"case": case, "seed": scenario["seed"], "run_id": report["run_id"],
            "evidence_sha256": digest(Path(workspace) / "runs" / report["run_id"] / "MANIFEST.json"),
            "checks": checks, "passed": all(c["passed"] is not False for c in checks),
            "completed": report["completed_observations"], "rms_deg": report["pointing_rms_deg"]}


def run_campaign(scenarios, workspace, seed_count=1, cancel=None, progress=None):
    campaign_id = uuid.uuid4().hex[:12]
    directory = Path(workspace) / "campaigns" / campaign_id
    directory.mkdir(parents=True)
    result = {"schema": "slx.orbitlab.campaign/1", "campaign_id": campaign_id,
              "status": "running", "cases": [], "total": 9 * seed_count, "passed": None,
              "scope": "Pinned F Prime/Basilisk integration evidence; no flight certification."}
    for seed in range(42, 42 + seed_count):
        for name, scenario in campaign_cases(scenarios, seed):
            if cancel and cancel.is_set():
                result["status"] = "cancelled"
                break
            report = run_batch(scenario, "energy-aware", workspace, evaluation_s=650 if scenario.get("continuous") else None, cancel=cancel)
            if report["aborted"]:
                result["status"] = "cancelled"
                break
            result["cases"].append(assess_case(name, scenario, report, workspace))
            atomic_json(directory / "campaign.json", result)
            if progress:
                progress(copy.deepcopy(result))
        if result["status"] == "cancelled":
            break
    if result["status"] != "cancelled":
        result["status"] = "finished"
        result["passed"] = all(case["passed"] for case in result["cases"])
    atomic_json(directory / "campaign.json", result)
    rows = "".join(f"<tr><td>{html.escape(c['case'])}</td><td>{c['seed']}</td><td>{'PASS' if c['passed'] else 'FAIL'}</td>"
                   f"<td>{c['completed']}</td><td><a href='../../runs/{c['run_id']}/report.html'>{c['run_id']}</a></td>"
                   f"<td>{html.escape(', '.join(item['id'] for item in c['checks']))}</td></tr>" for c in result["cases"])
    (directory / "campaign.html").write_text(f"<!doctype html><html lang='en'><meta charset='utf-8'><title>SLX OrbitLab verification</title>"
        f"<style>body{{font:14px 'Segoe UI',sans-serif;margin:40px;color:#192541}}table{{border-collapse:collapse;width:100%}}td,th{{padding:12px;border-bottom:1px solid #dfe5f0;text-align:left}}header{{background:#111c31;color:white;padding:24px}}</style>"
        f"<header><h1>SLX OrbitLab verification campaign</h1>Silicon LogiX · F Prime / Basilisk</header><p>{result['status']} · {len(result['cases'])}/{result['total']} cases</p>"
        f"<table><tr><th>Scenario</th><th>Seed</th><th>Result</th><th>Delivered</th><th>Evidence</th><th>Requirements</th></tr>{rows}</table><p>{result['scope']}</p></html>", encoding="utf-8")
    return result
