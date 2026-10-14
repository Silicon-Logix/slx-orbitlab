// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Dictionary-derived examples and explanations connect native acknowledgements to physical effects.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: 12
    readonly property var selected: commandName.currentIndex >= 0 && orbit.catalogue.length ? orbit.catalogue[commandName.currentIndex] : ({})
    readonly property var result: orbit.commandResult || ({})
    readonly property bool hasResult: result.name === selected.name && result.run_id === orbit.state.run_id
    readonly property string inputError: {
        if (!selected.arguments)
            return "";
        try {
            const values = JSON.parse(commandArgs.text);
            if (!Array.isArray(values))
                return "Parameters must be enclosed in [ and ].";
            if (values.length !== selected.arguments.length)
                return "Requires " + selected.arguments.length + " parameters in the specified order.";
            return "";
        } catch (error) {
            return "Invalid format: click Use example to restore the parameters.";
        }
    }
    function useExample() {
        if (!commandArgs || !selected.name)
            return;
        let args = (selected.example || []).slice();
        if (selected.name.endsWith("CS_RUN") || selected.name.endsWith("CS_VALIDATE")) {
            if (orbit.preparedSequence.file_name)
                args[0] = orbit.preparedSequence.file_name;
        }
        const targets = orbit.state.targets || [];
        if (selected.name.endsWith("ADD_TARGET") || selected.name.endsWith("SCHEDULE_TARGET"))
            args[0] = orbit.state.next_target_id || Math.max(1, ...targets.map(t => Number(t.id))) + 1;
        if (selected.name.endsWith("SET_PRIORITY") || selected.name.endsWith("REMOVE_TARGET") || selected.name.endsWith("UPDATE_TARGET")) {
            const pending = targets.find(t => t.status === "pending") || targets[0];
            if (pending)
                args[0] = pending.id;
        }
        commandArgs.text = JSON.stringify(args);
    }
    function chooseInitial() {
        const index = orbit.catalogue.findIndex(c => c.name === "OrbitLab.mission.MANEUVER");
        commandName.currentIndex = index;
        useExample();
    }
    function effect() {
        if (!hasResult)
            return "";
        if (result.status === "sending")
            return "Sending to the F Prime dispatcher…";
        if (result.status === "error")
            return result.message || "The command was not sent.";
        if (result.name.endsWith("CMD_CLEAR_TRACKING"))
            return result.probe_response === 0 ? "Reset completed · subsequent CMD_NO_OP confirmed by the dispatcher with ACK OK." : "Dispatcher verification failed.";
        if (result.response !== 0)
            return "F Prime rejected the parameters. Check ranges and operating state.";
        const name = result.name;
        const args = result.args || [];
        const vehicle = orbit.state.vehicle || {};
        if (selected.category === "diagnostic") {
            if (name.endsWith("CMD_NO_OP_STRING"))
                return "Response OK · text is in the NoOpStringReceived event.";
            if (name.endsWith("CMD_TEST_CMD_1"))
                return "Response OK · the three values are in the TestCmd1Args event.";
            return "Response OK · command path verified. This diagnostic checks communication.";
        }
        if (!orbit.status.playing && orbit.status.mode === "LIVE")
            return "Command accepted · simulation paused. Click Resume to sample physical effects.";
        if (result.accepted_s !== undefined && Number(orbit.state.time_s) <= Number(result.accepted_s))
            return "Command accepted · waiting for a physics frame after the F Prime response.";
        if (name.endsWith("DEPLOY")) {
            const hinge = Number((orbit.state.visual.pivots_native_deg || {}).Solar_Left_Deploy || 0);
            if (Number(orbit.state.deploy) !== Number(args[0]))
                return "Request accepted · waiting for the next physics frame.";
            const done = Math.abs(hinge - (args[0] ? 0 : 90)) < 0.5;
            return (done ? (args[0] ? "Panels deployed" : "Panels stowed") : "Panels moving") + " · hinge " + hinge.toFixed(1) + "° · generation " + Number(orbit.state.generation_w).toFixed(1) + " W";
        }
        if (name.endsWith("MANEUVER")) {
            if (vehicle.maneuver_mode !== args[0])
                return "Request accepted · waiting for the next physics frame.";
            if (orbit.state.safety_active || !orbit.state.attitude_valid || !orbit.state.actuator_valid)
                return "Maneuver requested · held by energy protection, sensors or actuators. Check events.";
            if (args[0] === 0)
                return "Automatic mission confirmed by telemetry.";
            return (Number(orbit.state.pointing_error_deg) <= 0.5 ? "Attitude reached" : "Slewing") + " · error " + Number(orbit.state.pointing_error_deg).toFixed(2) + "°. Check the satellite in the 3D view.";
        }
        if (name.endsWith("SET_BEACON")) {
            if (vehicle.beacon_enabled !== args[0])
                return "Request accepted · waiting for the next physics frame.";
            if (!args[0])
                return "Beacon disabled · state confirmed by telemetry.";
            if (orbit.state.safety_active || Number(orbit.state.energy_j) < Number(orbit.state.capacity_j) * Number(orbit.state.reserve_percent) / 100 + 5000 || orbit.state.eps.flags)
                return "Flashing requested · held to preserve the energy reserve.";
            return "Flashing enabled · period " + vehicle.beacon_period_s + " s. Open the 3D view and use 1× to watch the pulses.";
        }
        if (name.endsWith("SET_PAYLOAD"))
            return vehicle.payload_enabled !== args[0] ? "Waiting for the next physics frame." : args[0] ? "Instrument enabled · acquisition waits for access, pointing and energy." : "Instrument suspended · no new acquisition.";
        if (name.endsWith("SET_DOWNLINK"))
            return vehicle.downlink_enabled !== args[0] ? "Waiting for the next physics frame." : !args[0] ? "Downlink suspended · data remains onboard." : orbit.state.downlink ? "Downlink active · " + Number(orbit.state.delivered_bytes / 1024).toFixed(1) + " KiB received." : "Downlink enabled · waiting for data, ground contact and energy.";
        if (name.endsWith("ADD_TARGET") || name.endsWith("SCHEDULE_TARGET"))
            return "Target T" + args[0] + " added to the queue. Mission shows the target selected by F Prime and other pending targets.";
        if (name.endsWith("SET_PRIORITY"))
            return "Priority of T" + args[0] + " updated to " + args[1] + ". A suitable pass is still required.";
        if (name.endsWith("REMOVE_TARGET"))
            return "Target T" + args[0] + " closed. Previously acquired images remain in the archive.";
        if (name.endsWith("ABORT"))
            return "Scheduled targets closed. The simulation continues and retains acquired data.";
        if (name.endsWith("SET_STRATEGY"))
            return "Strategy confirmed: " + (orbit.state.strategy === "energy-aware" ? "respect available energy" : "priority") + ". The change is recorded.";
        if (name.endsWith("ORBIT_BURN") || name.endsWith("CANCEL_BURN"))
            return "Maneuver state: " + ["idle", "aligning", "thrusting", "complete", "cancelled", "held by protection"][(orbit.state.orbit || {}).burn_state || 0] + " · delivered delta-v " + Number(orbit.state.delivered_delta_v_mps || 0).toFixed(3) + " m/s. Open Orbit and passes to check the trajectory.";
        if (name.endsWith("UPDATE_TARGET"))
            return "Coordinates of T" + args[0] + " updated. Check access predictions; previous products retain their acquisition coordinates.";
        if (name.endsWith("REPLAN"))
            return "Windows recalculated for the next 24 simulated hours. Open Orbit and passes.";
        return "Command accepted by F Prime. Check telemetry and events.";
    }
    Component.onCompleted: chooseInitial()
    Connections {
        target: orbit
        function onCatalogueChanged() {
            root.chooseInitial();
        }
    }
    ScrollView {
        id: composerScroll
        objectName: "nativeComposerScroll"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(470, Math.max(390, root.height - 265))
        contentWidth: availableWidth
        contentHeight: composer.implicitHeight
        clip: true
        Panel {
            id: composer
            width: composerScroll.availableWidth
            height: implicitHeight
            title: "NATIVE F PRIME COMMANDS"
            ConsoleComboBox {
                id: commandName
                objectName: "nativeCommandSelector"
                Layout.fillWidth: true
                popupWidth: Math.min(650, window.width - 70)
                model: orbit.catalogue
                textRole: "name"
                onCurrentIndexChanged: Qt.callLater(root.useExample)
            }
            Text {
                objectName: "nativeCommandFullName"
                Layout.fillWidth: true
                text: commandName.displayText
                wrapMode: Text.WrapAnywhere
                color: "#192541"
                font.pixelSize: 13
                font.family: "Consolas"
            }
            Text {
                objectName: "nativeCommandDescription"
                Layout.fillWidth: true
                text: root.selected.title || "Start a mission to load the dictionary."
                color: "#192541"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: root.selected.description || ""
                color: "#56647a"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                ConsoleTextField {
                    id: commandArgs
                    objectName: "nativeCommandArguments"
                    Layout.fillWidth: true
                    text: "[]"
                    placeholderText: "Selected command parameters"
                    selectByMouse: true
                }
                ActionButton {
                    objectName: "nativeCommandExampleButton"
                    text: "Use example"
                    enabled: root.selected.name !== undefined
                    onClicked: root.useExample()
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.inputError.length > 0
                text: root.inputError
                color: "#a33a36"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            ConsoleCheckBox {
                id: resumeClock
                text: "Resume simulation to apply physical effects"
                font.pixelSize: 13
                visible: root.selected.category === "mission" && root.selected.direct_enabled === true
                checked: true
            }
            ActionButton {
                objectName: "nativeCommandSendButton"
                Layout.fillWidth: true
                text: "Send F Prime command"
                primary: true
                enabled: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running && root.selected.direct_enabled === true && !root.inputError
                onClicked: orbit.command(root.selected.name, commandArgs.text, resumeClock.checked)
            }
            ActionButton {
                Layout.fillWidth: true
                visible: ["mission", "sequence"].includes(root.selected.workflow)
                text: root.selected.workflow === "mission" ? "Configure a new session →" : "Prepare a command sequence →"
                onClicked: window.page = root.selected.workflow === "mission" ? 0 : 7
            }
            Text {
                Layout.fillWidth: true
                visible: root.selected.workflow === "maintenance"
                text: "Deployment maintenance command; use the guided controls to manage execution."
                color: "#56647a"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: "Parameter order: " + (root.selected.argument_types || []).map(p => p.name + " (" + p.type + ")").join(", ") + "\n" + (root.selected.parameter_help || "")
                color: "#56647a"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOn
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: responseText.implicitHeight + 24
        color: root.hasResult && root.result.response === 0 ? "#e4f4ec" : "#edf0f7"
        radius: 6
        Text {
            id: responseText
            objectName: "nativeCommandEffect"
            anchors.fill: parent
            anchors.margins: 12
            text: root.hasResult ? "Last sent " + JSON.stringify(root.result.args || []) + "\n" + root.effect() : "The response confirms command acceptance. Telemetry confirms the physical effect."
            color: "#192541"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }
    Panel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: "COMMAND HISTORY"
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: orbit.commands
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width - 14
                height: 62
                color: "#f3f5f9"
                radius: 5
                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 5
                    Text {
                        width: parent.width
                        text: "#" + modelData.sequence + " " + modelData.name
                        color: "#192541"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: modelData.status + " · " + JSON.stringify(modelData.args) + " · opcode " + modelData.opcode
                        color: modelData.status === "OK" ? "#087762" : "#a33a36"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AlwaysOn
            }
        }
    }
}
