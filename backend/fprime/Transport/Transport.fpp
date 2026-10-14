# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
module OrbitLab {
    @ Host-process adapter preserves native F Prime packet serialization and simulation time.
    passive component Transport {
        sync input port telemetryIn: Fw.Tlm
        sync input port eventIn: Fw.Log
        sync input port responseIn: Fw.CmdResponse
        sync input port clockIn: Fw.Time
        output port commandOut: Fw.Com
        sync input port sequencerCommandIn: Fw.Com
        output port sequencerCommandOut: Fw.Com
        sync input port sequencerResponseIn: Fw.CmdResponse
        output port sequencerResponseOut: Fw.CmdResponse
        output port sequenceTick: Svc.Sched
        output port dispatcherTick: Svc.Sched
        output port queueFence: [2] Svc.Ping
        sync input port queueFenceReturn: [2] Svc.Ping
    }
}
