// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Requirement-linked campaigns and finite, reproducible strategy evaluations.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: verificationRoot
    spacing: 16
    Theme {
        id: theme
    }
    ScrollView {
        id: configurationScroll
        Layout.preferredWidth: 365
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        Layout.preferredHeight: 0
        contentWidth: availableWidth
        contentHeight: Math.max(930, verificationRoot.height)
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        Panel {
            id: configurationPanel
            width: configurationScroll.availableWidth
            height: configurationScroll.contentHeight
            title: "VERIFICATION CAMPAIGNS"
            Text {
                text: "Verification campaigns"
                color: theme.ink
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: "Nine repeatable tests: nominal mission, insufficient energy, sensor and actuator faults, solar generation or ground contact loss, two images, full storage and continuous operation."
                color: theme.muted
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Text {
                    text: "Repeatable variants"
                    color: theme.muted
                    font.pixelSize: 14
                }
                Item {
                    Layout.fillWidth: true
                }
                ConsoleSpinBox {
                    id: seeds
                    from: 1
                    to: 8
                    value: 1
                }
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Run test campaign"
                primary: true
                enabled: orbit.canControl
                onClicked: orbit.runCampaign(seeds.value)
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Cancel active tests"
                enabled: orbit.connected && orbit.status.busy
                onClicked: orbit.action("cancel_job")
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Open campaign report ↗"
                enabled: orbit.campaign.status === "finished" || orbit.campaign.status === "cancelled"
                onClicked: orbit.openCampaign()
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: theme.line
            }
            Text {
                text: "Comparison duration [simulated s]"
                color: theme.ink
                font.pixelSize: 14
            }
            ConsoleSpinBox {
                id: horizon
                Layout.fillWidth: true
                from: 60
                to: 604800
                stepSize: 60
                value: 6000
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Compare both strategies"
                enabled: orbit.canControl && orbit.state.run_id !== "—"
                onClicked: orbit.compareStrategies(horizon.value)
            }
            Text {
                Layout.fillWidth: true
                text: "Comparison repeats the same mission with both strategies and identical faults. The active mission pauses during the test."
                color: theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: theme.line
            }
            Text {
                text: "Recover an interrupted recording"
                color: theme.ink
                font.pixelSize: 14
            }
            ConsoleComboBox {
                id: interrupted
                Layout.fillWidth: true
                model: orbit.recoverable
                textRole: "run_id"
            }
            RowLayout {
                ActionButton {
                    text: "Refresh"
                    enabled: orbit.connected
                    onClicked: orbit.action("recordings")
                }
                ActionButton {
                    text: "Recover recording"
                    enabled: orbit.canControl && interrupted.currentIndex >= 0
                    onClicked: orbit.recoverRecording(orbit.recoverable[interrupted.currentIndex].run_id)
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Metric {
                Layout.fillWidth: true
                label: "CAMPAGNA"
                value: orbit.campaign.status === "finished" ? "Complete" : orbit.campaign.status === "cancelled" ? "Cancelled" : orbit.status.busy ? "Running" : "Ready"
                unit: ""
            }
            Metric {
                Layout.fillWidth: true
                label: "COMPLETED TESTS"
                value: (orbit.campaign.cases || []).length + " / " + (orbit.campaign.total || 0)
                unit: ""
            }
            Metric {
                Layout.fillWidth: true
                label: "ESITO"
                value: orbit.campaign.passed === true ? "PASS" : orbit.campaign.passed === false ? "FAIL" : "Waiting"
                unit: ""
                accent: orbit.campaign.passed === false ? "#955a12" : theme.teal
            }
        }
        Panel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "RESULTS AND VERIFIED REQUIREMENTS"
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: orbit.campaign.cases || []
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 130
                    radius: 6
                    color: theme.canvas
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 7
                        RowLayout {
                            Text {
                                Layout.fillWidth: true
                                text: modelData.case + " · seed " + modelData.seed
                                color: theme.ink
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: modelData.passed ? "PASS" : "FAIL"
                                color: modelData.passed ? theme.teal : "#955a12"
                                font.pixelSize: 15
                            }
                            ActionButton {
                                text: "Report ↗"
                                onClicked: orbit.openReport(modelData.run_id)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.checks.map(c => c.id + ": " + (c.passed === null ? "N/A" : c.passed ? "PASS" : "FAIL")).join("   ")
                            color: theme.muted
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            text: "Run " + modelData.run_id + " · " + modelData.completed + " delivered · RMS error " + (modelData.rms_deg === null ? "N/A" : Number(modelData.rms_deg).toFixed(4) + " degrees")
                            color: theme.accent
                            font.pixelSize: 13
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
        Panel {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            title: "CONTINUOUS RECORDING STATUS"
            Text {
                Layout.fillWidth: true
                text: orbit.state.recording.segments + " SQLite segments · " + Number(orbit.state.recording.disk_bytes / 1048576).toFixed(1) + " / " + Number(orbit.state.recording.quota_bytes / 1048576).toFixed(0) + " MiB · committed " + Number(orbit.state.recording.checkpoint_s).toFixed(1) + " s"
                color: theme.ink
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
        }
    }
}
