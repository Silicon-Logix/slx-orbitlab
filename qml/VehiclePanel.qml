// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Component inspection and native vehicle commands use confirmed mission telemetry.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Panel {
    id: vehiclePanel
    title: "COMPONENTS AND F PRIME COMMANDS"
    signal sceneRequested(int scene)
    readonly property bool popupVisible: components.popup.visible
    readonly property bool canCommand: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
    readonly property bool canManeuver: canCommand && ![1, 2, 5].includes((orbit.state.orbit || {}).burn_state)
    readonly property bool orbitBurnActive: [1, 2, 5].includes((orbit.state.orbit || {}).burn_state)
    readonly property var vehicle: orbit.state.vehicle || {}
    readonly property var choices: [
        {
            name: "Optical instrument",
            node: "Optical_Payload",
            purpose: "Creates an image when pointing, sensors and energy permit observation."
        },
        {
            name: "Battery and power",
            node: "Power_Controller",
            purpose: "Powers instruments. The energy reserve can defer activities or trigger protection."
        },
        {
            name: "Solar panels",
            node: "Solar_Left_Deploy",
            purpose: "Generate power. Deployment, stowage and Sun tracking change generation."
        },
        {
            name: "Navigation sensors",
            node: "Navigation_Sensors",
            purpose: "Measure the attitude used by F Prime. A fault suspends observations."
        },
        {
            name: "Reaction wheels",
            node: "Reaction_Wheel_Assembly",
            purpose: "Rotate the satellite using commanded torque. Basilisk integrates motion."
        },
        {
            name: "Communications",
            node: "Communications",
            purpose: "Downlink files during ground contact. The beacon follows F Prime telemetry."
        },
        {
            name: "Onboard computer",
            node: "Onboard_Computer",
            purpose: "F Prime receives commands, executes sequences and decides which activities can proceed."
        },
        {
            name: "Ground station",
            node: "GroundStation_Root",
            purpose: "The antenna tracks the satellite. It receives data during a suitable contact while the link is available."
        }
    ]
    readonly property string node: choices[components.currentIndex].node
    function choose(index) {
        const chosen = choices[index].node;
        if (chosen === "GroundStation_Root" && orbit.inspector.frame.scene !== 4)
            sceneRequested(4);
        else if (chosen !== "GroundStation_Root" && orbit.inspector.frame.scene === 4)
            sceneRequested(0);
        orbit.inspector.selectComponent(chosen);
    }
    ConsoleComboBox {
        id: components
        objectName: "vehicleComponentSelector"
        Layout.fillWidth: true
        model: vehiclePanel.choices
        textRole: "name"
        onActivated: index => vehiclePanel.choose(index)
    }
    Text {
        Layout.fillWidth: true
        text: vehiclePanel.choices[components.currentIndex].purpose
        wrapMode: Text.WordWrap
        color: "#56647a"
        font.pixelSize: 14
    }
    Text {
        objectName: "vehicleComponentStatus"
        Layout.fillWidth: true
        color: "#087762"
        font.pixelSize: 15
        wrapMode: Text.WordWrap
        text: {
            if (!orbit.status.fprime_running && orbit.status.mode !== "REPLAY")
                return "Start an observation to command the satellite";
            if (vehiclePanel.node === "Power_Controller")
                return "Battery " + Number(orbit.state.soc_percent).toFixed(1) + "% · " + Number(orbit.state.energy_j / 3600).toFixed(1) + " Wh\nGeneration " + Number(orbit.state.generation_w).toFixed(1) + " W / load " + Number(orbit.state.consumed_w).toFixed(1) + " W";
            if (vehiclePanel.node === "Solar_Left_Deploy")
                return "Deployment " + Number(orbit.state.visual.pivots_native_deg.Solar_Left_Deploy).toFixed(1) + "°\nGeneration " + Number(orbit.state.generation_w).toFixed(1) + " W";
            if (vehiclePanel.node === "Navigation_Sensors")
                return orbit.state.attitude_valid ? "Sensor available\nEstimation error " + Number(orbit.state.attitude_estimation_error_deg).toFixed(4) + "°" : "Sensor unavailable · pointing held";
            if (vehiclePanel.node === "Reaction_Wheel_Assembly")
                return "Wheel speed [rad/s]\n" + (orbit.state.wheel_speeds_radps || []).map(v => Number(v).toFixed(2)).join(" / ");
            if (vehiclePanel.node === "GroundStation_Root" || vehiclePanel.node === "Communications")
                return (orbit.state.downlink ? "Downlink active" : vehiclePanel.vehicle.downlink_enabled === 0 ? "Downlink disabled" : "Waiting for contact") + "\n" + Number(orbit.state.delivered_bytes / 1024).toFixed(1) + " KiB received";
            if (vehiclePanel.node === "Optical_Payload")
                return vehiclePanel.vehicle.payload_enabled === 0 ? "Instrument disabled" : orbit.state.phase_id === 5 ? "Image acquisition" : "Instrument ready · " + orbit.state.acquired + " acquired images";
            return orbit.channels.length + " F Prime telemetry channels";
        }
    }
    RowLayout {
        ActionButton {
            text: "Focus"
            objectName: "vehicleFocusButton"
            enabled: orbit.inspector.ready
            onClicked: orbit.inspector.focusComponent()
        }
        ActionButton {
            text: "Reset view"
            enabled: orbit.inspector.ready
            onClicked: {
                isolated.checked = false;
                orbit.inspector.resetCamera();
            }
        }
    }
    ConsoleCheckBox {
        id: isolated
        objectName: "vehicleIsolateCheck"
        text: "Isolate component"
        enabled: orbit.inspector.ready && [1, 2].indexOf(Number(orbit.inspector.frame.scene)) >= 0
        onToggled: orbit.inspector.isolateComponent(checked)
    }
    RowLayout {
        visible: vehiclePanel.node === "Solar_Left_Deploy"
        ActionButton {
            text: "Deploy panels"
            objectName: "vehicleDeployButton"
            enabled: vehiclePanel.canCommand
            onClicked: orbit.vehicleCommand("panels", 1)
        }
        ActionButton {
            text: "Stow"
            objectName: "vehicleStowButton"
            enabled: vehiclePanel.canCommand
            onClicked: orbit.vehicleCommand("panels", 0)
        }
    }
    ActionButton {
        visible: vehiclePanel.node === "Optical_Payload"
        Layout.fillWidth: true
        text: vehiclePanel.vehicle.payload_enabled === 0 ? "Enable optical instrument" : "Disable optical instrument"
        enabled: vehiclePanel.canCommand
        onClicked: orbit.vehicleCommand("payload", vehiclePanel.vehicle.payload_enabled === 0 ? 1 : 0)
    }
    ActionButton {
        visible: vehiclePanel.node === "Communications" || vehiclePanel.node === "GroundStation_Root"
        Layout.fillWidth: true
        text: vehiclePanel.vehicle.downlink_enabled === 0 ? "Enable downlink" : "Disable downlink"
        enabled: vehiclePanel.canCommand
        onClicked: orbit.vehicleCommand("downlink", vehiclePanel.vehicle.downlink_enabled === 0 ? 1 : 0)
    }
    ActionButton {
        visible: vehiclePanel.node === "Navigation_Sensors"
        Layout.fillWidth: true
        text: "Inject sensor fault · 10 s"
        enabled: vehiclePanel.canCommand
        onClicked: {
            orbit.injectPhysicalFault("attitude_sensor", 10);
            orbit.action("resume");
        }
    }
    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#e3e8f0"
    }
    Text {
        text: "ATTITUDE MANEUVERS"
        color: "#192541"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    Text {
        Layout.fillWidth: true
        text: vehiclePanel.orbitBurnActive ? "Orbital maneuver · " + Number(orbit.state.delivered_delta_v_mps || 0).toFixed(3) + " m/s delivered\nMeasured thrust " + Number(orbit.state.applied_thrust_n || 0).toFixed(2) + " N · +X error " + Number(orbit.state.pointing_error_deg || 0).toFixed(2) + "°" : ["Automatic mission", "Sun pointing", "Earth pointing", "Relative rotation"][Number(vehiclePanel.vehicle.maneuver_mode || 0)] + "\nError " + Number(orbit.state.pointing_error_deg || 0).toFixed(2) + "°"
        color: "#4c4ed7"
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    RowLayout {
        ActionButton {
            text: "Toward the Sun"
            objectName: "vehicleSunButton"
            enabled: vehiclePanel.canManeuver
            onClicked: orbit.vehicleCommand("maneuver", 1)
        }
        ActionButton {
            text: "Toward the Earth"
            enabled: vehiclePanel.canManeuver
            onClicked: orbit.vehicleCommand("maneuver", 2)
        }
    }
    RowLayout {
        ConsoleSpinBox {
            id: angle
            from: -180
            to: 180
            value: 45
            stepSize: 15
        }
        ActionButton {
            text: "Rotate [degrees]"
            objectName: "vehicleSlewButton"
            enabled: vehiclePanel.canManeuver
            onClicked: orbit.vehicleCommand("maneuver", 3, angle.value)
        }
    }
    ActionButton {
        Layout.fillWidth: true
        text: "Resume automatic mission"
        objectName: "vehicleAutoButton"
        primary: true
        enabled: vehiclePanel.canManeuver
        onClicked: orbit.vehicleCommand("maneuver", 0)
    }
    Text {
        text: "BEACON"
        color: "#192541"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    ActionButton {
        Layout.fillWidth: true
        objectName: "vehicleBeaconButton"
        text: vehiclePanel.vehicle.beacon_enabled ? "Disable beacon" : "Enable flashing · 4 s"
        enabled: vehiclePanel.canCommand
        onClicked: orbit.vehicleCommand("beacon", vehiclePanel.vehicle.beacon_enabled ? 0 : 1, 4)
    }
    Text {
        objectName: "vehicleBeaconStatus"
        Layout.fillWidth: true
        text: !vehiclePanel.vehicle.beacon_enabled ? "Beacon disabled" : orbit.state.safety_active || orbit.state.energy_j < orbit.state.capacity_j * orbit.state.reserve_percent / 100 + 5000 || orbit.state.eps.flags ? "Flashing requested · held for energy reserve" : "Flashing enabled · period " + vehiclePanel.vehicle.beacon_period_s + " s · 2 W during each pulse"
        color: "#087762"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Rectangle {
            objectName: "vehicleBeaconIndicator"
            width: 12
            height: 12
            radius: 6
            color: vehiclePanel.vehicle.beacon_on ? "#18b276" : "#c1c9d6"
        }
        Text {
            text: "Beacon pulse confirmed"
            color: "#56647a"
            font.pixelSize: 12
        }
    }
    Item {
        Layout.fillHeight: true
    }
    Connections {
        target: orbit.inspector
        function onChanged() {
            if (!orbit.inspector.ready || components.popup.visible)
                return;
            const selected = orbit.inspector.selectedComponent;
            for (let i = 0; i < vehiclePanel.choices.length; ++i)
                if (vehiclePanel.choices[i].node === selected || i === 2 && selected.indexOf("Solar_") === 0 || i === 1 && selected === "Battery_Module" || i === 7 && selected.indexOf("GroundStation_") === 0)
                    components.currentIndex = i;
        }
    }
}
