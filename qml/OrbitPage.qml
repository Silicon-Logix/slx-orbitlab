// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Orbital operations use native flight commands and measured Basilisk dynamics.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    spacing: 16
    readonly property var dynamics: orbit.state.orbit || ({})
    readonly property bool hasOrbit: Number.isFinite(dynamics.semimajor_axis_m) && dynamics.semimajor_axis_m > 0
    readonly property bool live: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
    readonly property bool burning: [1, 2, 5].includes(dynamics.burn_state)
    readonly property var burnLabels: ["No maneuver", "Aligning for thrust", "Thrust active", "Delta-v achieved", "Maneuver cancelled", "Thrust held by protection"]
    function measured(value, divisor, digits) {
        return root.hasOrbit && Number.isFinite(Number(value)) ? Number(value / divisor).toFixed(digits) : "—";
    }
    function countdown(time) {
        if (time < 0)
            return "No pass predicted in the next 24 hours";
        const delay = Math.max(0, time - Number(orbit.state.time_s || 0));
        return delay < 1 ? "Access available now" : "In " + Math.floor(delay / 3600) + " h " + Math.floor(delay % 3600 / 60) + " min " + Math.floor(delay % 60) + " simulated s";
    }
    function sendBurn() {
        orbit.command("OrbitLab.mission.ORBIT_BURN", JSON.stringify([Number(radial.text), Number(along.text), Number(normal.text)]), true);
    }
    Theme {
        id: theme
    }
    ScrollView {
        id: controlsScroll
        Layout.preferredWidth: 365
        Layout.minimumWidth: 365
        Layout.maximumWidth: 365
        Layout.fillHeight: true
        contentWidth: availableWidth
        contentHeight: controls.implicitHeight
        clip: true
        Panel {
            id: controls
            width: controlsScroll.availableWidth
            height: implicitHeight
            title: "F′ · ORBITAL MANEUVERS"
            Text {
                Layout.fillWidth: true
                text: "Added targets are observed at their next suitable pass. An orbital maneuver changes velocity and access windows; it requires thrust and propellant."
                color: theme.ink
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            ConsoleComboBox {
                id: preset
                objectName: "orbitBurnPreset"
                Layout.fillWidth: true
                model: ["Raise orbit · +2 m/s", "Lower orbit · −2 m/s", "Change plane · +1 m/s", "Custom delta-v"]
                enabled: !root.burning
                onActivated: index => {
                    radial.text = "0";
                    along.text = index === 0 ? "2" : index === 1 ? "-2" : "0";
                    normal.text = index === 2 ? "1" : "0";
                }
            }
            Text {
                text: "Delta-v [m/s] · RTN frame"
                color: theme.muted
                font.pixelSize: 13
            }
            RowLayout {
                Text {
                    text: "Radial"
                    color: theme.ink
                    Layout.preferredWidth: 100
                }
                ConsoleTextField {
                    id: radial
                    objectName: "orbitRadialDeltaV"
                    Layout.fillWidth: true
                    text: "0"
                    enabled: !root.burning
                    validator: DoubleValidator {
                        bottom: -10
                        top: 10
                        locale: "C"
                    }
                }
            }
            RowLayout {
                Text {
                    text: "Along-track"
                    color: theme.ink
                    Layout.preferredWidth: 100
                }
                ConsoleTextField {
                    id: along
                    objectName: "orbitAlongDeltaV"
                    Layout.fillWidth: true
                    text: "2"
                    enabled: !root.burning
                    validator: DoubleValidator {
                        bottom: -10
                        top: 10
                        locale: "C"
                    }
                }
            }
            RowLayout {
                Text {
                    text: "Normal"
                    color: theme.ink
                    Layout.preferredWidth: 100
                }
                ConsoleTextField {
                    id: normal
                    objectName: "orbitNormalDeltaV"
                    Layout.fillWidth: true
                    text: "0"
                    enabled: !root.burning
                    validator: DoubleValidator {
                        bottom: -10
                        top: 10
                        locale: "C"
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: "Maximum thrust 5 N · total delta-v 0.01–10 m/s · initial propellant 1 kg. F Prime aligns the +X axis and enables thrust only with valid sensors, energy and pointing."
                color: theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            ActionButton {
                objectName: "orbitBurnSendButton"
                Layout.fillWidth: true
                text: "Send maneuver to F Prime"
                primary: true
                enabled: root.live && !root.burning && radial.acceptableInput && along.acceptableInput && normal.acceptableInput
                onClicked: root.sendBurn()
            }
            ActionButton {
                objectName: "orbitBurnCancelButton"
                Layout.fillWidth: true
                text: "Stop thrust"
                enabled: root.live && root.burning
                onClicked: orbit.command("OrbitLab.mission.CANCEL_BURN", "[]", true)
            }
            Text {
                objectName: "orbitBurnStatus"
                Layout.fillWidth: true
                text: root.hasOrbit ? root.burnLabels[root.dynamics.burn_state || 0] + "\nRemaining delta-v " + Number(root.dynamics.remaining_delta_v_mps || 0).toFixed(3) + " m/s\nMeasured thrust " + Number(orbit.state.applied_thrust_n || 0).toFixed(2) + " N" : orbit.status.mode === "REPLAY" ? "This recording has no orbital parameters." : "Start a mission to compute the orbit and access windows."
                color: root.dynamics.burn_state === 5 ? theme.accent : theme.teal
                font.pixelSize: 15
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: (orbit.commandResult.name || "").endsWith("ORBIT_BURN") || (orbit.commandResult.name || "").endsWith("CANCEL_BURN")
                text: orbit.commandResult.status === "error" ? orbit.commandResult.message : orbit.commandResult.response === 0 ? "Command accepted by the dispatcher. The state above confirms physical execution." : orbit.commandResult.status === "sending" ? "Sending command…" : "Request rejected: check delta-v, propellant and the minimum perigee of 200 km."
                color: theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            RowLayout {
                ActionButton {
                    text: orbit.status.playing ? "Pause" : "Resume"
                    enabled: root.live
                    onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
                }
                ActionButton {
                    text: "3D view"
                    onClicked: window.page = 6
                }
            }
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOn
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14
        Text {
            text: "Orbit and observation opportunities"
            color: theme.ink
            font.pixelSize: 25
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: "Initial orbit prepared for " + (orbit.state.initial_orbit_target || "the selected target") + ". New targets retain the current trajectory. For an immediate New York demonstration, select it when starting a new session."
            color: theme.muted
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Metric {
                Layout.fillWidth: true
                label: "PERIGEE / APOGEE"
                value: root.measured(root.dynamics.perigee_altitude_m, 1000, 1) + " / " + root.measured(root.dynamics.apogee_altitude_m, 1000, 1)
                unit: "km"
            }
            Metric {
                Layout.fillWidth: true
                label: "INCLINAZIONE"
                value: root.measured(root.dynamics.inclination_rad, Math.PI / 180, 3)
                unit: "°"
            }
            Metric {
                Layout.fillWidth: true
                label: "PROPELLENTE"
                value: root.measured(orbit.state.propellant_kg, 1, 4)
                unit: "kg"
                accent: theme.teal
            }
        }
        RowLayout {
            Metric {
                Layout.fillWidth: true
                label: "DELIVERED DELTA-V"
                value: root.measured(orbit.state.delivered_delta_v_mps, 1, 3)
                unit: "m/s"
            }
            Metric {
                Layout.fillWidth: true
                label: "ORBITAL PERIOD"
                value: root.measured(root.dynamics.period_s, 60, 2)
                unit: "min"
            }
            Metric {
                Layout.fillWidth: true
                label: "ECCENTRICITY"
                value: root.measured(root.dynamics.eccentricity, 1, 6)
                unit: ""
            }
        }
        Panel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "UPCOMING PASSES · F PRIME / C++ CORE PREDICTION"
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Horizon: 24 simulated hours · visibility and pointing checked during execution"
                    color: theme.muted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    text: "Recalculate"
                    enabled: root.live
                    onClicked: orbit.command("OrbitLab.mission.REPLAN", "[]", true)
                }
            }
            ListView {
                objectName: "orbitAccessWindows"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: orbit.state.targets || []
                delegate: Rectangle {
                    required property var modelData
                    readonly property var access: (orbit.state.access_windows || []).find(w => w.target_id === modelData.id)
                    width: ListView.view.width - 16
                    height: textColumn.implicitHeight + 24
                    color: theme.canvas
                    radius: 6
                    Column {
                        id: textColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                        }
                        spacing: 6
                        Text {
                            width: parent.width
                            text: "T" + modelData.id + " · " + modelData.name + " · priority " + modelData.priority
                            color: theme.ink
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: access ? root.countdown(access.start_s) : "Target " + modelData.status
                            color: access && access.start_s >= 0 ? theme.teal : theme.muted
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: Number(modelData.latitude_deg).toFixed(4) + "°, " + Number(modelData.longitude_deg).toFixed(4) + "°" + (access && access.start_s >= 0 ? " · window " + Number(access.start_s).toFixed(0) + "–" + (access.end_s >= 0 ? Number(access.end_s).toFixed(0) : "beyond prediction horizon") + " s" : "")
                            color: theme.muted
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                }
            }
            Text {
                Layout.fillWidth: true
                text: "A small maneuver changes the orbit gradually. Predictions use the measured state and are updated; they exclude future burns and do not guarantee access to a city."
                color: theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }
    }
}
