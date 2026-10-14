# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Segmented, bounded-memory evidence, crash recovery and synchronized integrity-checked replay."""
import csv
from collections import deque
import hashlib
import html
import json
import os
from pathlib import Path
import shutil
import sqlite3
import fcntl


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def stable_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False), encoding="utf-8")
    temporary.replace(path)


def segment_paths(directory):
    directory = Path(directory)
    index = directory / "SEGMENTS.json"
    if index.is_file():
        names = [entry["file"] for entry in json.loads(index.read_text(encoding="utf-8"))["segments"]]
    else:
        names = ["mission.sqlite"] + [p.name for p in sorted(directory.glob("segment-*.sqlite"))]
    paths = [(directory / name).resolve() for name in names]
    if not paths or any(not p.is_relative_to(directory.resolve()) for p in paths):
        raise ValueError("Invalid segment index")
    return paths


def read_rows(directory, sql, parameters=(), reverse=False):
    paths = segment_paths(directory)
    for path in reversed(paths) if reverse else paths:
        db = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
        try:
            yield from db.execute(sql, parameters)
        finally:
            db.close()


class Recording:
    """SQLite has a small page cache; old segments close and acquire their own digest."""
    def __init__(self, directory, metadata):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=False)
        self.lock = (self.directory / ".writer.lock").open("a")
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.metadata = metadata
        self.segment_duration = metadata["scenario"].get("segment_duration_s", 1800)
        self.quota = metadata["scenario"].get("recording_quota_bytes", 2147483648)
        self.segments = []
        self.time_s = self.last_commit = self.last_quota_check = 0.0
        self.disk_bytes = 0
        self.closed = False
        self._open_segment()
        atomic_json(self.directory / "scenario.json", metadata["scenario"])

    def _open_segment(self):
        name = "mission.sqlite" if not self.segments else f"segment-{len(self.segments):06d}.sqlite"
        self.db = sqlite3.connect(self.directory / name)
        self.db.executescript("""
            PRAGMA cache_size=-2048;
            CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE frames(time_s REAL PRIMARY KEY, snapshot TEXT NOT NULL);
            CREATE TABLE records(sequence INTEGER PRIMARY KEY, time_s REAL NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL);
            CREATE INDEX records_by_time ON records(time_s);
            CREATE INDEX records_by_kind_time ON records(kind,time_s);
        """)
        self.db.execute("INSERT INTO metadata VALUES (?,?)", ("run", stable_json(self.metadata)))
        self.segments.append({"file": name, "start_s": self.time_s, "end_s": self.time_s, "sha256": None})
        self._checkpoint()

    def _checkpoint(self):
        self.db.commit()
        self.segments[-1]["end_s"] = self.time_s
        atomic_json(self.directory / "SEGMENTS.json", {"schema": "slx.orbitlab.segments/1", "segments": self.segments})
        atomic_json(self.directory / "checkpoint.json", {"schema": "slx.orbitlab.checkpoint/1",
                    "committed_time_s": self.time_s, "segment": self.segments[-1]["file"],
                    "scope": "Recorded evidence only; physical state restart is not claimed."})
        self.last_commit = self.time_s

    def _ensure_segment(self):
        if self.time_s - self.segments[-1]["start_s"] >= self.segment_duration:
            self._checkpoint()
            self.metadata = json.loads(self.db.execute("SELECT value FROM metadata WHERE key='run'").fetchone()[0])
            self.db.close()
            self.segments[-1]["sha256"] = digest(self.directory / self.segments[-1]["file"])
            self._open_segment()

    def record(self, kind, payload):
        self._ensure_segment()
        self.db.execute("INSERT INTO records(time_s,kind,payload) VALUES (?,?,?)",
                        (payload.get("time_s", self.time_s), kind, stable_json(payload)))

    def frame(self, snapshot):
        self.time_s = snapshot["time_s"]
        self._ensure_segment()
        self.db.execute("INSERT OR REPLACE INTO frames VALUES (?,?)", (self.time_s, stable_json(snapshot)))
        if self.time_s - self.last_commit >= 5:
            self._checkpoint()
        if self.time_s - self.last_quota_check >= 60 or self.last_quota_check == 0:
            self.db.commit()
            self.disk_bytes = sum(p.stat().st_size for p in self.directory.rglob("*") if p.is_file())
            self.last_quota_check = self.time_s
            if self.disk_bytes >= self.quota or shutil.disk_usage(self.directory).free < 104857600:
                self._checkpoint()
                raise RuntimeError("Recording storage limit reached. Session paused; finalize or export the evidence.")

    def telemetry_status(self):
        return {"segments": len(self.segments), "disk_bytes": self.disk_bytes, "quota_bytes": self.quota,
                "checkpoint_s": self.last_commit, "segment_duration_s": self.segment_duration}

    def report(self, aborted=False, finalized=False, recovered=False):
        self._checkpoint()
        meta = json.loads(self.db.execute("SELECT value FROM metadata WHERE key='run'").fetchone()[0])
        final, minimum, samples, square_sum, peak, invalid_captures = {}, float("inf"), 0, 0.0, 0.0, 0
        storage_errors = 0
        propulsion_errors = 0
        propulsion_samples = 0
        fields = ["time_s", "phase", "target_id", "energy_j", "soc_percent", "generation_w", "consumed_w",
                  "truth_pointing_error_deg", "completed", "acquired", "deferred", "expired", "queue_depth",
                  "stored_bytes", "delivered_bytes", "forecast_min_energy_j", "safety_active", "reason"]
        with (self.directory / "telemetry.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            for row in read_rows(self.directory, "SELECT snapshot FROM frames ORDER BY time_s"):
                final = json.loads(row[0])
                writer.writerow(final)
                minimum = min(minimum, final["energy_j"])
                storage_errors += int(final.get("stored_bytes", 0) > final.get("storage_capacity_bytes", 2097152))
                if "propellant_kg" in final:
                    propulsion_samples += 1
                    expected_fuel = meta["scenario"].get("propellant_kg", 1.0) - final["delivered_delta_v_mps"] * 65 / (220 * 9.80665)
                    thrust = final.get("orbit", {}).get("force_body_n", [0, 0, 0])[0]
                    propulsion_errors += int(abs(expected_fuel - final["propellant_kg"]) > 1e-7 or final["propellant_kg"] < 0 or
                        (thrust > 0 and (not final["attitude_valid"] or not final["actuator_valid"] or
                         final["safety_active"] or final["energy_j"] < final["capacity_j"] * final["reserve_percent"] / 100)))
                if final["phase"] == "Acquire":
                    error = final["truth_pointing_error_deg"]
                    samples += 1
                    square_sum += error * error
                    peak = max(peak, error)
                invalid_captures += int(bool(final.get("capture")) and
                    (not final["attitude_valid"] or not final.get("actuator_valid", True) or bool(final.get("safety_active")) or
                     final["energy_j"] < final["capacity_j"] * final["reserve_percent"] / 100))
        delivered_count = delivery_errors = 0
        for row in read_rows(self.directory, "SELECT payload FROM records WHERE kind='product_delivered' ORDER BY sequence"):
            product = json.loads(row[0])
            source = self.directory / "products" / product["filename"]
            received = self.directory / "ground" / product["filename"]
            delivered_count += 1
            delivery_errors += int(not source.is_file() or not received.is_file() or
                                   digest(source) != product["sha256"] or digest(received) != product["sha256"])
        checks = [
            {"id": "SLX-SAFE-001", "name": "Invalid sensors, actuators and safe mode inhibit acquisition", "passed": invalid_captures == 0},
            {"id": "SLX-POINT-001", "name": "Exposure pointing peak below 0.5 deg", "passed": peak <= 0.5 if samples else None},
            {"id": "SLX-STORE-001", "name": "Logical onboard capacity respected",
             "passed": storage_errors == 0},
            {"id": "SLX-DATA-001", "name": "Every delivered product matches its recorded source checksum", "passed": delivery_errors == 0},
            {"id": "SLX-PROP-001", "name": "Propellant balance and sensor/energy guards respected", "passed": propulsion_errors == 0 if propulsion_samples else None}
        ]
        sequence_results = deque(maxlen=100)
        sequence_counts = {"completed": 0, "canceled": 0, "failed": 0}
        for row in read_rows(self.directory, "SELECT payload FROM records WHERE kind='sequence_result' ORDER BY sequence"):
            execution = json.loads(row[0])
            sequence_counts[execution["status"]] += 1
            sequence_results.append(execution)
        with (self.directory / "sequence-commands.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=["time_s", "sequence_id", "index", "name", "args", "opcode", "response"])
            writer.writeheader()
            for row in read_rows(self.directory, "SELECT payload FROM records WHERE kind='sequence_step' ORDER BY sequence"):
                writer.writerow(json.loads(row[0]))
        result = {"schema": "slx.orbitlab.report/2", "run_id": meta["run_id"], "scenario": meta["scenario"]["name"],
                  "sequences_completed": sequence_counts["completed"], "sequences_canceled": sequence_counts["canceled"],
                  "sequences_failed": sequence_counts["failed"], "sequences": list(sequence_results),
                  "strategy": meta["strategy"], "duration_s": final.get("time_s", 0), "aborted": aborted,
                  "finalized": finalized, "recovered": recovered, "continuous": meta["scenario"].get("continuous", False),
                  "completed_observations": final.get("completed", 0), "acquired_observations": final.get("acquired", 0),
                  "deferred_observations": final.get("deferred", 0), "expired_targets": final.get("expired", 0),
                  "pending_products": final.get("queue_depth", 0), "delivered_bytes": final.get("delivered_bytes", 0),
                  "verified_deliveries": delivered_count,
                  "final_energy_j": final.get("energy_j", 0), "minimum_energy_j": minimum if final else 0,
                  "pointing_rms_deg": (square_sum / samples) ** 0.5 if samples else None,
                  "pointing_peak_deg": peak if samples else None, "acquisition_samples": samples,
                  "versions": meta["versions"], "identity": meta.get("identity", {}),
                  "final_strategy": final.get("strategy", meta["strategy"]),
                  "orbital_maneuvers": final.get("orbit", {}).get("burn_count", 0),
                  "final_propellant_kg": final.get("propellant_kg", 0),
                  "delivered_delta_v_mps": final.get("delivered_delta_v_mps", 0),
                  "final_perigee_altitude_m": final.get("orbit", {}).get("perigee_altitude_m"),
                  "final_apogee_altitude_m": final.get("orbit", {}).get("apogee_altitude_m"),
                  "rtems_enabled": meta.get("rtems_enabled", False), "segments": len(self.segments),
                  "scenario_sha256": digest(self.directory / "scenario.json"), "checks": checks,
                  "passed": all(c["passed"] is not False for c in checks),
                  "limits": ["Elliptic two-body LEO (e<0.1); fixed inertial Sun; no J2, atmospheric drag or ephemerides. Unlimited duration does not imply unlimited fidelity.",
                             "Ideal body +X centre-of-mass propulsion: 5 N maximum, 220 s specific impulse, explicit propellant debit; constant 65 kg dynamics mass. No plume, valve, thermal or variable-mass tank model.",
                             "RTN delta-v maneuvers 0.01–10 m/s; osculating perigee guard 200 km; alignment and energy are verified each physical step. No automatic inter-city orbital transfer solver.",
                             "Rigid bus and balanced reaction wheels; no flexible-body, momentum unloading or thermal analysis.",
                             "Ideal finite battery; no electrochemistry, voltage or ageing. Baseline load can exhaust charge.",
                             "600-second energy forecast holds measured solar power during predicted sunlight; it is a planning estimate.",
                             "Synthetic optical products; geometric contact and rate-limited verified transfer; no RF link budget.",
                             "24-hour two-body access scan, 10-second grid for first 12000 s then 30-second grid; refreshed every 60 s and on replanning. Future burns are not assumed in forecasts; execution checks every physical step.",
                             "Archived source products remain as evidence after logical onboard memory is freed by ground acknowledgement.",
                             "Crash recovery restores committed evidence, not the numerical state of the spacecraft.",
                             "EPS: " + ("RTEMS 5 on emulated LEON3 with qualified ELF boot conditions." if meta.get("rtems_enabled") else "host controller; RTEMS/Renode inactive.")]}
        atomic_json(self.directory / "report.json", result)
        events = deque(maxlen=1000)
        with (self.directory / "events.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["time_s", "name", "severity", "text"])
            for row in read_rows(self.directory, "SELECT payload FROM records WHERE kind='event' ORDER BY sequence"):
                event = json.loads(row[0])
                events.append(event)
                writer.writerow([event["time_s"], event["name"], event["severity"], event["text"]])
        metrics = "".join(f"<tr><th>{html.escape(key.replace('_', ' '))}</th><td>{html.escape(str(value))}</td></tr>"
                          for key, value in result.items() if not isinstance(value, (list, dict)))
        event_rows = "".join(f"<tr><td>{e['time_s']:.1f} s</td><td>{html.escape(e['name'])}</td><td>{html.escape(e['text'])}</td></tr>" for e in events)
        limits = "".join(f"<li>{html.escape(limit)}</li>" for limit in result["limits"])
        check_rows = "".join(f"<tr><td>{c['id']}</td><td>{html.escape(c['name'])}</td><td>{'PASS' if c['passed'] else 'N/A' if c['passed'] is None else 'FAIL'}</td></tr>" for c in checks)
        content = f"""<!doctype html><html lang="en"><meta charset="utf-8"><title>SLX OrbitLab mission evidence</title>
        <style>body{{font:14px 'Segoe UI',sans-serif;margin:40px;color:#192541;background:#f3f5f9}}header{{background:#111c31;color:white;padding:24px;border-bottom:3px solid #5354e8}}table{{border-collapse:collapse;width:100%;background:white;margin:20px 0}}th,td{{text-align:left;padding:10px;border-bottom:1px solid #e3e8f0}}th{{width:35%}}footer{{color:#56647a;margin-top:24px}}</style>
        <header><h1>SLX OrbitLab</h1>Silicon LogiX · F Prime / Basilisk mission evidence</header>
        <h2>Run results</h2><table>{metrics}</table><h2>Verification</h2><table>{check_rows}</table>
        <h2>Last 1000 events</h2><p>Full decision trace: events.csv and SQLite segments.</p><table>{event_rows}</table>
        <h2>Model limits</h2><ul>{limits}</ul><footer>© 2026 Marco Pezzullo (Silicon LogiX). Local simulation evidence.</footer></html>"""
        (self.directory / "report.html").write_text(content, encoding="utf-8")
        return result

    def close(self, aborted=False, recovered=False):
        if self.closed:
            return
        self.record("lifecycle", {"status": "recovered" if recovered else "aborted" if aborted else "finished"})
        result = self.report(aborted, finalized=True, recovered=recovered)
        self.db.close()
        self.closed = True
        self.segments[-1]["sha256"] = digest(self.directory / self.segments[-1]["file"])
        atomic_json(self.directory / "SEGMENTS.json", {"schema": "slx.orbitlab.segments/1", "segments": self.segments})
        manifest = {"schema": "slx.orbitlab.evidence-manifest/2", "files": {
            path.relative_to(self.directory).as_posix(): digest(path)
            for path in sorted(self.directory.rglob("*")) if path.is_file()
            and path.name not in (".writer.lock", "MANIFEST.json")}}
        atomic_json(self.directory / "MANIFEST.json", manifest)
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.lock.close()
        return result


def recover_recording(directory):
    directory = Path(directory)
    if (directory / "MANIFEST.json").exists():
        raise ValueError("Finalized recordings cannot be recovered or modified")
    recording = Recording.__new__(Recording)
    recording.directory = directory
    recording.lock = (directory / ".writer.lock").open("a")
    try:
        fcntl.flock(recording.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        recording.lock.close()
        raise ValueError("This recording still has an active writer") from error
    try:
        paths = segment_paths(directory)
        index = directory / "SEGMENTS.json"
        if index.is_file():
            for entry in json.loads(index.read_text(encoding="utf-8"))["segments"]:
                if entry.get("sha256") and digest(directory / entry["file"]) != entry["sha256"]:
                    raise ValueError("Closed segment integrity failed; recovery stopped")
        recording.segments = []
        for path in paths:
            with sqlite3.connect(path) as db:
                if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                    raise ValueError("Damaged SQLite segment; recovery stopped")
                bounds = db.execute("SELECT MIN(time_s),MAX(time_s) FROM frames").fetchone()
            recording.segments.append({"file": path.name, "start_s": bounds[0] or 0,
                                       "end_s": bounds[1] or 0, "sha256": digest(path) if path != paths[-1] else None})
        recording.time_s = max(s["end_s"] for s in recording.segments)
        recording.db = sqlite3.connect(paths[-1])
        recording.metadata = json.loads(recording.db.execute("SELECT value FROM metadata WHERE key='run'").fetchone()[0])
        recording.segment_duration = recording.metadata["scenario"].get("segment_duration_s", 1800)
        recording.closed = False
        recording.last_commit = recording.time_s
        return recording.close(aborted=True, recovered=True)
    finally:
        if not recording.lock.closed:
            recording.lock.close()


class Replay:
    def __init__(self, directory):
        self.directory = Path(directory)
        manifest = json.loads((self.directory / "MANIFEST.json").read_text(encoding="utf-8"))
        if "mission.sqlite" not in manifest.get("files", {}):
            raise ValueError("Recording manifest is missing its physical frames")
        for name, expected in manifest["files"].items():
            file = (self.directory / name).resolve()
            if not file.is_relative_to(self.directory.resolve()) or not file.is_file() or digest(file) != expected:
                raise ValueError("Recording integrity check failed: " + name)
        self.paths = segment_paths(self.directory)
        self.duration_s = max((row[0] or 0 for row in read_rows(self.directory, "SELECT MAX(time_s) FROM frames")), default=0)
        self.db = None
        self.open_path = None

    def seek(self, time_s):
        time_s = max(0, min(float(time_s), self.duration_s))
        if self.db:
            self.db.close()
            self.db = None
        snapshot = None
        for path in reversed(self.paths):
            db = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
            row = db.execute("SELECT snapshot FROM frames WHERE time_s<=? ORDER BY time_s DESC LIMIT 1", (time_s,)).fetchone()
            if row:
                snapshot = json.loads(row[0])
                self.db = db
                break
            db.close()
        if snapshot is None:
            raise ValueError("Recording contains no physical frames")
        confirmed_time = snapshot["time_s"]
        for kind, key, limit in (("event", "events", 80), ("command", "commands", 100)):
            values = []
            for row in read_rows(self.directory, "SELECT payload FROM records WHERE kind=? AND time_s<=? ORDER BY sequence DESC LIMIT ?",
                                 (kind, confirmed_time, limit), reverse=True):
                values.append(json.loads(row[0]))
                if len(values) >= limit:
                    break
            snapshot[key] = list(reversed(values))
        previous = []
        for row in read_rows(self.directory, "SELECT snapshot FROM frames WHERE time_s<=? AND CAST(ROUND(time_s*1000) AS INTEGER)%5000=0 ORDER BY time_s DESC LIMIT 360",
                             (confirmed_time,), reverse=True):
            previous.append(json.loads(row[0]))
            if len(previous) >= 360:
                break
        trail, history = [], []
        for frame in reversed(previous):
            point = frame["visual"].get("orbit_position_ecef_display")
            if point is not None:
                trail.append(point)
            history.append({"time_s": frame["time_s"], "soc_percent": frame["soc_percent"],
                            "pointing_error_deg": frame["truth_pointing_error_deg"] if frame["phase_id"] in (4, 5) else None,
                            "generation_w": frame["generation_w"], "consumed_w": frame["consumed_w"],
                            "orbit_position_ecef_display": point, "latitude_deg": frame["visual"].get("latitude_deg", 0),
                            "longitude_deg": frame["visual"].get("longitude_deg", 0)})
        snapshot.update(trail_ecef_display=trail, presentation_history=history, mode="REPLAY", duration_s=self.duration_s)
        return snapshot

    def close(self):
        if self.db:
            self.db.close()
            self.db = None
