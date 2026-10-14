// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Component modes, base IDs and host port routes mirror Top/topology.fpp.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    spacing: 8
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                {
                    name: "Svc.CmdSequencer",
                    mode: "active · queue 32",
                    address: "0x4000",
                    port: "comCmdOut → seqAdapter → cmdDisp.seqCmdBuff[1]"
                },
                {
                    name: "Svc.CommandDispatcher",
                    mode: "active · queue 32",
                    address: "0x3000",
                    port: "native dispatch → mission.commandIn"
                },
                {
                    name: "OrbitLab.Mission",
                    mode: "passive · synchronous",
                    address: "0x1000",
                    port: "C ABI 2 → proprietary mission library"
                },
                {
                    name: "OrbitLab.Transport",
                    mode: "passive · host adapter",
                    address: "0x2000",
                    port: "commandOut → cmdDisp.seqCmdBuff[0]; events, telemetry, time, ACK"
                }
            ]
            Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: 5
                color: "#f0f3fa"
                border.color: "#dfe5f0"
                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 6
                    Text {
                        width: parent.width
                        text: modelData.name
                        color: "#192541"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        text: modelData.mode
                        color: "#56647a"
                        font.pixelSize: 12
                    }
                    Text {
                        text: "Base ID " + modelData.address
                        color: "#4c4ed7"
                        font.pixelSize: 12
                    }
                }
                HoverHandler {
                    id: hover
                }
                ToolTip.visible: hover.hovered
                ToolTip.text: modelData.port
                ToolTip.delay: 350
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Commands → dispatcher → mission → native response / events / telemetry → host transport → GDS → Qt & Godot"
        color: "#4c4ed7"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }
}
