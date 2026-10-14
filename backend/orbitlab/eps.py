# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Optional RTEMS/LEON3 controller through Renode's remote UART tester and bounded virtual time."""
import binascii
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import xmlrpc.client
from .evidence import digest


class BoundedTransport(xmlrpc.client.Transport):
    """Bound a stalled emulator call independently of its virtual-time UART timeout."""
    def make_connection(self, host):
        connection = super().make_connection(host)
        connection.timeout = 8
        return connection


class EpsController:
    def __init__(self, backend_home=None):
        home = Path(backend_home or os.environ.get("SLX_BACKEND_HOME", Path.home() / ".cache/slx-orbitlab"))
        self.cache = home / "embedded"
        self.firmware = self.cache / "firmware/eps.elf"
        self.renode = self.cache / "renode/renode"
        if not self.firmware.is_file() or not self.renode.is_file():
            raise RuntimeError("Build the qualified RTEMS firmware and install Renode first")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        self.log = tempfile.TemporaryFile()
        self.process = subprocess.Popen([str(self.renode), "--disable-gui", "--hide-log", "--robot-server-port", str(port)], stdout=self.log, stderr=subprocess.STDOUT)
        self.transport = BoundedTransport()
        self.proxy = xmlrpc.client.ServerProxy(f"http://127.0.0.1:{port}", transport=self.transport)
        self.sequence = 0
        try:
            for attempt in range(80):
                try:
                    self.proxy.get_keyword_names()
                    break
                except OSError:
                    if self.process.poll() is not None:
                        raise RuntimeError("Renode exited during startup")
                    time.sleep(0.05)
            else:
                raise RuntimeError("Renode remote server startup timeout")
            self.command('mach create "OrbitLabEPS"')
            self.command("machine LoadPlatformDescription @" + str(self.cache / "renode/platforms/boards/leon3.repl"))
            self.command("sysbus LoadELF @" + str(self.firmware))
            # The RCC BSP reads the boot stack as RAM end, and CLOCK_SPEED in MHz.
            # These are explicit ELF-loader preconditions, not an analog PROM model.
            self.command("cpu SetRegister 14 0x40400000")
            clock_address = self.command('sysbus GetSymbolAddress "CLOCK_SPEED"').strip()
            self.command("sysbus WriteDoubleWord " + clock_address + " 50")
            # The BSP expects a 1 MHz GPTimer input from the boot loader.
            self.command("sysbus WriteDoubleWord 0x80000304 49")
            self.command("sysbus WriteDoubleWord 0x80000300 49")
            self.command("cpu PerformanceInMips 50")
            self.command("emulation SetGlobalAdvanceImmediately true")
            self.command('emulation SetGlobalQuantum "0.0001"')
            self.tester = self.keyword("CreateTerminalTester", ["sysbus.uart"])
            self.advance(1.0)
            ready = self.keyword("WaitForLineOnUart", ["ORBITLAB_EPS_READY", 2, self.tester, False, False, True])
            self.identity = {"platform": "LEON3", "rtems": ready["Line"], "renode": "1.16.1",
                             "firmware_sha256": digest(self.firmware), "timer_hz": 1000, "timer_prescaler": 49,
                             "cpu_mips": 50, "advance_immediately": True, "quantum_s": 0.0001,
                             "ram_start": "0x40000000", "ram_end": "0x40400000"}
        except Exception:
            self.close()
            raise

    def keyword(self, name, arguments):
        result = self.proxy.run_keyword(name, arguments)
        if result.get("status") != "PASS":
            raise RuntimeError("Renode " + name + ": " + result.get("error", "unknown error"))
        return result.get("return")

    def command(self, text):
        return self.keyword("ExecuteCommand", [text])

    def advance(self, seconds):
        self.command('emulation RunFor "' + format(seconds, ".9g") + '"')

    @staticmethod
    def encode(body):
        return f"{body} {binascii.crc32(body.encode()):08x}"

    def raw(self, frame, expected="EPS_", seconds=0.5):
        self.keyword("WriteLineToUart", [frame, self.tester, False, True])
        self.advance(seconds)
        value = self.keyword("WaitForLineOnUart", [expected, 2, self.tester, False, False, True])
        return value["Line"]

    def permission(self, time_s, energy_j, capacity_j, requested_w, step_s=0.5):
        self.sequence += 1
        milliseconds = int(round(time_s * 1000))
        body = f"EPS {self.sequence} {milliseconds} {int(energy_j)} {int(capacity_j)} {int(round(requested_w * 1000))}"
        response = self.raw(self.encode(body), f"EPS_ACK {self.sequence} ", step_s)
        packet, crc = response.rsplit(" ", 1)
        if binascii.crc32(packet.encode()) != int(crc, 16):
            raise RuntimeError("Firmware response CRC mismatch")
        fields = packet.split()
        if int(fields[1]) != self.sequence or int(fields[2]) != milliseconds:
            raise RuntimeError("Firmware acknowledgement correlation failed")
        return {"mode": "RTEMS / Renode", "sequence": self.sequence, "time_s": time_s,
                "permitted_w": int(fields[3]) / 1000, "flags": int(fields[4]),
                "heartbeat": int(fields[5]), "response": response}

    def close(self):
        self.transport.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.log.close()
