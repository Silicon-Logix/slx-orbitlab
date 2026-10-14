// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Compose vehicle commands and monitor the real Svc.CmdSequencer execution contract.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: 14
    property int revision: 0
    property int requestedRevision: -1
    property int validatedRevision: -1
    readonly property var execution: orbit.state.sequence || ({})
    readonly property bool live: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
    readonly property bool active: ["loaded", "running", "waiting_step"].includes(execution.status)
    readonly property bool validated: orbit.preparedSequence.validated === true && orbit.preparedSequence.run_id === orbit.state.run_id && validatedRevision === revision
    readonly property var vehicleOptions: [
        {
            title: "Solar panels",
            name: "OrbitLab.mission.DEPLOY"
        },
        {
            title: "Satellite attitude",
            name: "OrbitLab.mission.MANEUVER"
        },
        {
            title: "Optical instrument",
            name: "OrbitLab.mission.SET_PAYLOAD"
        },
        {
            title: "Downlink",
            name: "OrbitLab.mission.SET_DOWNLINK"
        },
        {
            title: "Beacon",
            name: "OrbitLab.mission.SET_BEACON"
        },
        {
            title: "Check command and response",
            name: "OrbitLab.cmdDisp.CMD_NO_OP"
        }
    ]
    readonly property var options: vehicleOptions.concat(orbit.catalogue.filter(c => c.sequence_allowed && !vehicleOptions.some(v => v.name === c.name)))
    readonly property string extraError: {
        if (command.currentIndex < 6)
            return "";
        try {
            const values = JSON.parse(extraArgs.text);
            if (!Array.isArray(values) || values.length !== root.options[command.currentIndex].arguments.length)
                return "Check the number and order of parameters.";
            return "";
        } catch (error) {
            return "Enter a valid JSON array or reselect the command to load the example.";
        }
    }
    function changed() {
        revision++;
    }
    function steps() {
        let result = [];
        for (let i = 0; i < plan.count; ++i) {
            const row = plan.get(i);
            result.push({
                name: row.name,
                args: JSON.parse(row.argsJson),
                delay_s: row.delaySec
            });
        }
        return result;
    }
    function arguments() {
        if (command.currentIndex >= 6)
            return JSON.parse(extraArgs.text);
        if (command.currentIndex === 5)
            return [];
        if (command.currentIndex === 1)
            return [maneuver.currentIndex, angle.value];
        if (command.currentIndex === 4)
            return [permission.currentIndex === 0 ? 1 : 0, period.value];
        return [permission.currentIndex === 0 ? 1 : 0];
    }
    function describe(name, argsJson) {
        const args = JSON.parse(argsJson);
        if (name.endsWith("MANEUVER"))
            return ["Automatic mission", "Sun pointing", "Earth pointing", "Relative rotation " + args[1] + "°"][args[0]];
        if (name.endsWith("SET_BEACON"))
            return args[0] ? "Enable beacon · period " + args[1] + " s" : "Disable beacon";
        if (name.endsWith("DEPLOY"))
            return args[0] ? "Deploy panels" : "Stow panels";
        if (name.endsWith("SET_PAYLOAD"))
            return args[0] ? "Enable optical instrument" : "Suspend optical instrument";
        if (name.endsWith("SET_DOWNLINK"))
            return args[0] ? "Enable downlink" : "Suspend downlink";
        return "Check command link";
    }
    function loadSteps(name, rows) {
        plan.clear();
        planName.text = name;
        for (let row of rows)
            plan.append({
                name: row.name,
                argsJson: JSON.stringify(row.args),
                delaySec: row.delay_s || 0
            });
        commandList.currentIndex = -1;
        changed();
    }
    function preset(index) {
        const prefix = "OrbitLab.mission.";
        if (index === 0)
            loadSteps("Attitude and beacon demonstration", [
                {
                    name: prefix + "DEPLOY",
                    args: [1]
                },
                {
                    name: prefix + "SET_PAYLOAD",
                    args: [0]
                },
                {
                    name: prefix + "MANEUVER",
                    args: [1, 0]
                },
                {
                    name: prefix + "SET_BEACON",
                    args: [1, 4],
                    delay_s: 5
                },
                {
                    name: prefix + "MANEUVER",
                    args: [3, 30],
                    delay_s: 45
                },
                {
                    name: prefix + "SET_BEACON",
                    args: [0, 4],
                    delay_s: 60
                },
                {
                    name: prefix + "SET_PAYLOAD",
                    args: [1]
                },
                {
                    name: prefix + "MANEUVER",
                    args: [0, 0]
                }
            ]);
        else if (index === 1)
            loadSteps("Observation preparation", [
                {
                    name: prefix + "DEPLOY",
                    args: [1]
                },
                {
                    name: prefix + "SET_PAYLOAD",
                    args: [1]
                },
                {
                    name: prefix + "SET_DOWNLINK",
                    args: [1]
                },
                {
                    name: prefix + "MANEUVER",
                    args: [0, 0]
                }
            ]);
        else
            loadSteps("Check link", [
                {
                    name: "OrbitLab.cmdDisp.CMD_NO_OP",
                    args: []
                }
            ]);
    }
    function edit(index) {
        commandList.currentIndex = index;
        const row = plan.get(index);
        const args = JSON.parse(row.argsJson);
        command.currentIndex = options.findIndex(option => option.name === row.name);
        if (command.currentIndex >= 6)
            extraArgs.text = row.argsJson;
        delay.value = row.delaySec;
        if (command.currentIndex === 1) {
            maneuver.currentIndex = args[0];
            angle.value = args[1];
        } else {
            permission.currentIndex = args[0] === 0 ? 1 : 0;
            if (command.currentIndex === 4)
                period.value = args[1];
        }
    }
    function label(value) {
        return ({
                validated: "Validated by F Prime",
                loaded: "Loaded · click Start first step",
                running: "Running",
                waiting_step: "Step accepted · you can advance",
                completed: "Sequence complete",
                canceled: "Sequence cancelled",
                failed: "Sequence stopped after an error"
            })[value] || "No sequence run";
    }
    Component.onCompleted: preset(0)
    Connections {
        target: orbit
        function onSequenceChanged() {
            root.validatedRevision = orbit.preparedSequence.validated ? root.requestedRevision : -1;
        }
    }
    ListModel {
        id: plan
    }
    Text {
        Layout.fillWidth: true
        text: "F′ · Operational sequences"
        color: "#192541"
        font.pixelSize: 25
        font.weight: Font.DemiBold
    }
    Text {
        Layout.fillWidth: true
        text: "1. Prepare the list  →  2. Validate with the dictionary and F Prime sequencer  →  3. Run and check telemetry"
        color: "#56647a"
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16
        Panel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "COMMAND PLAN"
            RowLayout {
                Layout.fillWidth: true
                ConsoleTextField {
                    id: planName
                    objectName: "sequencePlanName"
                    Layout.fillWidth: true
                    maximumLength: 64
                    placeholderText: "Plan name"
                    enabled: !root.active
                    onTextChanged: root.changed()
                }
                ActionButton {
                    objectName: "sequenceSaveButton"
                    text: "Save plan"
                    enabled: plan.count > 0 && planName.text.trim().length > 0
                    onClicked: orbit.saveSequencePlan(planName.text, root.steps())
                }
            }
            RowLayout {
                Layout.fillWidth: true
                ConsoleComboBox {
                    id: presetSelector
                    Layout.fillWidth: true
                    model: ["Example · attitude and beacon", "Example · observation preparation", "Example · check link"]
                    enabled: !root.active
                }
                ActionButton {
                    objectName: "sequencePresetButton"
                    text: "Load example"
                    enabled: !root.active
                    onClicked: root.preset(presetSelector.currentIndex)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: orbit.sequencePlans.length > 0
                ConsoleComboBox {
                    id: savedPlan
                    Layout.fillWidth: true
                    model: orbit.sequencePlans
                    textRole: "name"
                    enabled: !root.active
                }
                ActionButton {
                    text: "Load saved"
                    enabled: !root.active && savedPlan.currentIndex >= 0
                    onClicked: {
                        const saved = orbit.sequencePlans[savedPlan.currentIndex];
                        root.loadSteps(saved.name, saved.steps);
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#e3e8f0"
            }
            RowLayout {
                Layout.fillWidth: true
                ConsoleComboBox {
                    id: command
                    objectName: "sequenceCommandSelector"
                    Layout.fillWidth: true
                    model: root.options
                    textRole: "title"
                    enabled: !root.active
                    onCurrentIndexChanged: if (currentIndex >= 6) {
                        const example = (root.options[currentIndex].example || []).slice();
                        if (root.options[currentIndex].name.endsWith("ADD_TARGET") || root.options[currentIndex].name.endsWith("SCHEDULE_TARGET"))
                            example[0] = orbit.state.next_target_id || 2;
                        extraArgs.text = JSON.stringify(example);
                    }
                }
                Text {
                    text: "Delay before step (s)"
                    color: "#56647a"
                    font.pixelSize: 13
                }
                ConsoleSpinBox {
                    id: delay
                    objectName: "sequenceDelay"
                    from: 0
                    to: 86400
                    editable: true
                    enabled: !root.active
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.options[command.currentIndex].name
                color: "#56647a"
                font.pixelSize: 12
                font.family: "Consolas"
                wrapMode: Text.WrapAnywhere
            }
            RowLayout {
                Layout.fillWidth: true
                visible: command.currentIndex < 5
                ConsoleComboBox {
                    id: permission
                    Layout.fillWidth: true
                    visible: command.currentIndex !== 1
                    model: ["Enabled / deployed", "Disabled / stowed"]
                    enabled: !root.active
                }
                ConsoleComboBox {
                    id: maneuver
                    Layout.fillWidth: true
                    visible: command.currentIndex === 1
                    model: ["Automatic mission", "Toward the Sun", "Toward the Earth", "Relative rotation"]
                    enabled: !root.active
                }
                Text {
                    visible: command.currentIndex === 1
                    text: "Angle (°)"
                    color: "#56647a"
                    font.pixelSize: 13
                }
                ConsoleSpinBox {
                    id: angle
                    visible: command.currentIndex === 1
                    from: -180
                    to: 180
                    value: 30
                    editable: true
                    enabled: !root.active && maneuver.currentIndex === 3
                }
                Text {
                    visible: command.currentIndex === 4
                    text: "Period (s)"
                    color: "#56647a"
                    font.pixelSize: 13
                }
                ConsoleSpinBox {
                    id: period
                    visible: command.currentIndex === 4
                    from: 1
                    to: 60
                    value: 4
                    editable: true
                    enabled: !root.active
                }
            }
            ConsoleTextField {
                id: extraArgs
                objectName: "sequenceExtraArguments"
                Layout.fillWidth: true
                visible: command.currentIndex >= 6
                enabled: !root.active
                text: "[]"
                placeholderText: "Parameters in dictionary order"
            }
            Text {
                Layout.fillWidth: true
                visible: command.currentIndex >= 6
                text: root.extraError || (root.options[command.currentIndex] ? root.options[command.currentIndex].parameter_help || "" : "")
                color: "#56647a"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            RowLayout {
                ActionButton {
                    objectName: "sequenceAddButton"
                    text: "Add step"
                    enabled: !root.active && plan.count < 64 && !root.extraError
                    onClicked: {
                        plan.append({
                            name: root.options[command.currentIndex].name,
                            argsJson: JSON.stringify(root.arguments()),
                            delaySec: delay.value
                        });
                        commandList.currentIndex = -1;
                        root.changed();
                    }
                }
                ActionButton {
                    text: "Update selected"
                    enabled: !root.active && commandList.currentIndex >= 0 && !root.extraError
                    onClicked: {
                        plan.set(commandList.currentIndex, {
                            name: root.options[command.currentIndex].name,
                            argsJson: JSON.stringify(root.arguments()),
                            delaySec: delay.value
                        });
                        root.changed();
                    }
                }
            }
            ListView {
                id: commandList
                objectName: "sequenceStepsList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 130
                clip: true
                spacing: 7
                model: plan
                delegate: Rectangle {
                    required property int index
                    required property string name
                    required property string argsJson
                    required property int delaySec
                    readonly property var confirmedStep: root.validated && root.execution.id === orbit.preparedSequence.id ? (root.execution.steps[index] || ({})) : ({})
                    width: ListView.view.width - 16
                    height: 68
                    radius: 7
                    color: commandList.currentIndex === index ? "#edf0ff" : "#f3f5f9"
                    border.color: commandList.currentIndex === index ? "#4c4ed7" : "#e3e8f0"
                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5
                        Text {
                            width: parent.width - stepResult.width - 12
                            text: (index + 1) + ". " + root.describe(name, argsJson)
                            color: "#192541"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: "Delay " + delaySec + " s · " + name
                            color: "#56647a"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        id: stepResult
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        text: parent.confirmedStep.executed_s === undefined ? "" : (parent.confirmedStep.response === 0 ? "OK · " : "Error · ") + Number(parent.confirmedStep.executed_s).toFixed(1) + " s"
                        color: parent.confirmedStep.response === 0 ? "#087762" : "#a33a36"
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.active
                        onClicked: root.edit(parent.index)
                    }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                }
            }
            RowLayout {
                ActionButton {
                    text: "↑"
                    enabled: !root.active && commandList.currentIndex > 0
                    onClicked: {
                        const i = commandList.currentIndex;
                        plan.move(i, i - 1, 1);
                        commandList.currentIndex = i - 1;
                        root.changed();
                    }
                }
                ActionButton {
                    text: "↓"
                    enabled: !root.active && commandList.currentIndex >= 0 && commandList.currentIndex < plan.count - 1
                    onClicked: {
                        const i = commandList.currentIndex;
                        plan.move(i, i + 1, 1);
                        commandList.currentIndex = i + 1;
                        root.changed();
                    }
                }
                ActionButton {
                    text: "Remove"
                    enabled: !root.active && commandList.currentIndex >= 0
                    onClicked: {
                        plan.remove(commandList.currentIndex);
                        commandList.currentIndex = -1;
                        root.changed();
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: plan.count + "/64 passi"
                    color: "#56647a"
                    font.pixelSize: 13
                }
            }
        }
        ScrollView {
            id: executionScroll
            Layout.preferredWidth: 375
            Layout.fillHeight: true
            contentWidth: availableWidth
            contentHeight: executionPanel.implicitHeight
            clip: true
            Panel {
                id: executionPanel
                width: executionScroll.availableWidth
                height: implicitHeight
                title: "NATIVE VALIDATION AND EXECUTION"
                Text {
                    Layout.fillWidth: true
                    text: root.live ? "F Prime and Basilisk connected" : "Start a mission on the Mission page to validate and run the plan."
                    color: root.live ? "#087762" : "#56647a"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    objectName: "sequenceValidateButton"
                    Layout.fillWidth: true
                    text: root.validated ? "✓ Sequence validated" : "Validate sequence"
                    primary: true
                    enabled: root.live && !root.active && plan.count > 0
                    onClicked: {
                        root.requestedRevision = root.revision;
                        orbit.prepareSequence(planName.text, root.steps());
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.validated ? "Dictionary, parameters, binary file and checksum verified · " + orbit.preparedSequence.size_bytes + " bytes · delays " + orbit.preparedSequence.delay_total_s + " s" : "Each edit requires validation again. Saved plans can be reused in other missions."
                    color: "#56647a"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    objectName: "sequenceRunButton"
                    Layout.fillWidth: true
                    text: "Run automatically"
                    enabled: root.live && root.validated && !root.active
                    onClicked: orbit.runSequence(orbit.preparedSequence.id, "auto")
                }
                ActionButton {
                    objectName: "sequenceManualButton"
                    Layout.fillWidth: true
                    text: "Load for manual steps"
                    enabled: root.live && root.validated && !root.active
                    onClicked: orbit.runSequence(orbit.preparedSequence.id, "manual")
                }
                RowLayout {
                    Layout.fillWidth: true
                    ActionButton {
                        objectName: "sequenceStepButton"
                        Layout.fillWidth: true
                        text: root.execution.status === "loaded" ? "Start first step" : "Next step"
                        enabled: root.live && root.execution.mode === "manual" && ["loaded", "waiting_step"].includes(root.execution.status)
                        onClicked: orbit.controlSequence(root.execution.status === "loaded" ? "start" : "step")
                    }
                    ActionButton {
                        objectName: "sequenceCancelButton"
                        text: "Cancel"
                        enabled: root.live && root.active
                        onClicked: orbit.controlSequence("cancel")
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#e3e8f0"
                }
                ActionButton {
                    objectName: "sequenceJoinWaitButton"
                    Layout.fillWidth: true
                    text: "Verify completion · CS_JOIN_WAIT"
                    enabled: root.live && ["running", "waiting_step"].includes(root.execution.status) && (root.execution.join_wait || {}).status !== "waiting"
                    onClicked: orbit.action("join_sequence")
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.execution.join_wait !== undefined
                    text: (root.execution.join_wait || {}).status === "confirmed" ? "Sequence completion confirmed by the F Prime dispatcher." : (root.execution.join_wait || {}).status === "rejected" ? "Completion wait rejected by the sequencer." : "CS_JOIN_WAIT is waiting for completion. In manual mode, continue with Next step."
                    color: "#087762"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    objectName: "sequenceExecutionStatus"
                    Layout.fillWidth: true
                    text: root.label(root.execution.status)
                    color: root.execution.status === "failed" ? "#a33a36" : "#192541"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: root.execution.name ? root.execution.name + " · " + (root.execution.completed_steps || 0) + "/" + (root.execution.steps || []).length + " accepted commands" : "Results come from the F Prime sequencer and dispatcher."
                    color: "#56647a"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: (root.execution.steps || []).filter(row => row.executed_s !== undefined).slice(-3)
                    Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: Number(modelData.executed_s).toFixed(1) + " s · " + root.describe(modelData.name, JSON.stringify(modelData.args)) + " · " + (modelData.response === 0 ? "ACK OK" : "rejected")
                        color: modelData.response === 0 ? "#087762" : "#a33a36"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Simulated time"
                        color: "#56647a"
                        font.pixelSize: 13
                    }
                    ConsoleComboBox {
                        Layout.fillWidth: true
                        model: ["1×", "10×", "60×", "600×"]
                        currentIndex: [1, 10, 60, 600].indexOf(orbit.status.speed)
                        enabled: root.live
                        onActivated: orbit.setSpeed([1, 10, 60, 600][currentIndex])
                    }
                    ActionButton {
                        text: orbit.status.playing ? "Pause" : "Resume"
                        enabled: root.live
                        onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Mission time " + Number(orbit.state.time_s || 0).toFixed(1) + " s · battery " + Number(orbit.state.soc_percent || 0).toFixed(1) + "%"
                    color: "#192541"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    Layout.fillWidth: true
                    text: "Check effects in the 3D view →"
                    enabled: orbit.state.run_id !== "—"
                    onClicked: {
                        window.page = 6;
                        orbit.openViewer(0);
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Delays start after the previous command completes and follow simulated time. ACK OK confirms the command; telemetry shows physical rotation, loads and beacon state. Energy can prevent activity. Cancel stops future steps; completed commands remain applied."
                    color: "#56647a"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AlwaysOn
            }
        }
    }
}
