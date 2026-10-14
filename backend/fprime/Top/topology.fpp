# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
module OrbitLab {
    instance mission: Mission base id 0x1000
    instance transport: Transport base id 0x2000
    instance seqAdapter: Transport base id 0x2100
    instance cmdDisp: Svc.CommandDispatcher base id 0x3000 queue size 32 stack size 65536 priority 10
    instance cmdSeq: Svc.CmdSequencer base id 0x4000 queue size 32 stack size 65536 priority 11
    deployment topology OrbitLab {
        instance mission
        instance transport
        instance seqAdapter
        instance cmdDisp
        instance cmdSeq
        command connections instance cmdDisp
        event connections instance transport
        telemetry connections instance transport
        time connections instance transport
        connections HostAdapter {
            transport.commandOut -> cmdDisp.seqCmdBuff[0]
            cmdDisp.seqCmdStatus[0] -> transport.responseIn
            cmdSeq.comCmdOut -> seqAdapter.sequencerCommandIn
            seqAdapter.sequencerCommandOut -> cmdDisp.seqCmdBuff[1]
            cmdDisp.seqCmdStatus[1] -> seqAdapter.sequencerResponseIn
            seqAdapter.sequencerResponseOut -> cmdSeq.cmdResponseIn
            seqAdapter.sequenceTick -> cmdSeq.schedIn
            seqAdapter.dispatcherTick -> cmdDisp.run
            seqAdapter.queueFence[0] -> cmdDisp.pingIn
            cmdDisp.pingOut -> seqAdapter.queueFenceReturn[0]
            seqAdapter.queueFence[1] -> cmdSeq.pingIn
            cmdSeq.pingOut -> seqAdapter.queueFenceReturn[1]
        }
    }
}
