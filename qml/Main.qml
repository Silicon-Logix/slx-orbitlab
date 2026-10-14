// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Mission console: flight software, numerical execution and evidence are the primary views.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    property int page: 0
    onPageChanged: if (page === 6 && !orbit.inspector.running && !orbit.inspector.installing)
        Qt.callLater(() => {
            if (window.page === 6 && !orbit.inspector.running && !orbit.inspector.installing)
                orbit.openViewer(3);
        })
    property bool aboutVisible: false
    property var selectedModules: []
    width: 1560
    height: 960
    minimumWidth: 920
    minimumHeight: 600
    visible: true
    title: "SLX OrbitLab · Silicon LogiX"
    color: theme.canvas
    font.pixelSize: 14
    palette.window: "#f3f5f9"
    palette.windowText: "#192541"
    palette.base: "white"
    palette.text: "#192541"
    palette.button: "white"
    palette.buttonText: "#192541"
    palette.highlight: "#4c4ed7"
    palette.highlightedText: "white"
    palette.mid: "#b8c3d4"
    onAboutVisibleChanged: if (aboutVisible)
        about.open()
    Theme {
        id: theme
    }
    function number(value, digits) {
        return Number(value).toFixed(digits);
    }
    function vector(values) {
        if (!values || values.length !== 4)
            return "—";
        let components = [];
        for (let i = 0; i < values.length; ++i)
            components.push(Number(values[i]).toFixed(5));
        return "[" + components.join(", ") + "]";
    }
    function nativeValue(value) {
        return typeof value === "number" ? value.toPrecision(7) : String(value || "(none)");
    }
    function missionEventText(event) {
        const match = String(event.text).match(/:\s*([A-Z_]+);/);
        const descriptions = {
            WAITING_OBSERVATION_WINDOW: "Waiting for a suitable pass over the target",
            PREPARING_OBSERVATION_WINDOW: "Preparing the observation pass",
            ENERGY_FORECAST_LOW: "Activity deferred: insufficient predicted energy",
            ENERGY_RESERVE_LOW: "Activity deferred to preserve the battery reserve",
            ATTITUDE_SENSOR_UNAVAILABLE: "Pointing held: attitude sensor unavailable",
            SLEW_TO_TARGET: "Slewing the satellite toward the target",
            POINTING_STABILITY_HOLD: "Checking pointing stability",
            EXPOSURE_IN_PROGRESS: "Generating the simulated image",
            EXPOSURE_COMPLETED: "Image acquired and saved in onboard storage",
            WAITING_GROUND_CONTACT: "Waiting for ground station contact",
            CONTACT_AND_ENERGY_CONFIRMED: "Contact and energy confirmed: transferring the file",
            DOWNLINK_ENERGY_LOW: "Downlink held: insufficient energy",
            GROUND_LINK_UNAVAILABLE: "Ground link temporarily unavailable",
            ONBOARD_STORAGE_FULL: "Onboard storage full: waiting for data transfer",
            ACTUATOR_UNAVAILABLE_SAFE_MODE: "Satellite protection: actuator unavailable",
            BATTERY_RESERVE_SAFE_MODE: "Satellite protection: battery below minimum reserve",
            OBSERVATIONS_COMPLETE_STANDBY: "Observations complete: waiting for new targets",
            NO_PENDING_TARGET: "No pending target"
        };
        return match && descriptions[match[1]] ? descriptions[match[1]] : event.text;
    }
    function unit(name) {
        if (name.indexOf("DeltaV") >= 0)
            return "m/s";
        if (name.indexOf("PropellantMass") >= 0)
            return "kg";
        if (name.indexOf("ThrustForce") >= 0 || name.indexOf("ThrustCommand") >= 0)
            return "N";
        if (name.indexOf("SemimajorAxis") >= 0 || name.indexOf("Altitude") >= 0)
            return "m";
        if (name.indexOf("Inclination") >= 0)
            return "rad";
        if (name.indexOf("Eccentricity") >= 0)
            return "fraction";
        if (name.indexOf("OrbitPeriod") >= 0)
            return "s";
        if (name.indexOf("BeaconPeriod") >= 0)
            return "s";
        if (name.indexOf("Enabled") >= 0 || name.indexOf("BeaconOn") >= 0 || name.indexOf("PanelCommand") >= 0)
            return "boolean";
        if (name.indexOf("Storage") >= 0)
            return "bytes";
        if (name.indexOf("Contact") >= 0)
            return "s";
        if (name.indexOf("Sunlight") >= 0)
            return "fraction";
        if (name.indexOf("Available") >= 0 || name.indexOf("ActuatorValid") >= 0 || name.indexOf("SafeMode") >= 0)
            return "boolean";
        if (name.indexOf("CurrentSequence") >= 0)
            return "sequence file";
        if (name.indexOf("SensorValid") >= 0)
            return "boolean";
        if (name.indexOf("Energy") >= 0)
            return "J";
        if (name.indexOf("Power") >= 0 || name.indexOf("Generation") >= 0)
            return "W";
        if (name.indexOf("Error") >= 0)
            return "rad";
        if (name.indexOf("Time") >= 0)
            return "s";
        return "count / enum";
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 78
            color: "white"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 54
                    color: theme.navy
                    radius: 5
                    Image {
                        anchors.fill: parent
                        anchors.margins: 5
                        source: orbit.logoUrl
                        fillMode: Image.PreserveAspectFit
                    }
                }
                Rectangle {
                    width: 1
                    height: 34
                    color: theme.line
                }
                ColumnLayout {
                    spacing: 3
                    Text {
                        text: "OrbitLab"
                        color: theme.ink
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: window.width < 1100 ? "F PRIME / BASILISK" : "F PRIME / BASILISK · " + (orbit.connected ? (orbit.stale ? "STALE DATA" : "SERVICE READY") : orbit.status.backend_starting ? "STARTING SERVICE..." : "SERVICE DISCONNECTED")
                        color: orbit.connected && !orbit.stale ? theme.teal : theme.muted
                        font.pixelSize: 13
                        font.letterSpacing: 0.5
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    spacing: 4
                    visible: window.width >= 1700
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "F′  F Prime 4.3  /  Basilisk 2.12  /  C++ core ABI 2"
                        color: theme.ink
                        font.pixelSize: 14
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: orbit.connected ? (orbit.stale ? "STALE DATA" : "SERVICE CONNECTED") : orbit.status.backend_starting ? "STARTING LINUX SERVICE" : "SERVICE DISCONNECTED"
                        color: orbit.connected && !orbit.stale ? theme.teal : "#955a12"
                        font.pixelSize: 13
                        font.letterSpacing: 1
                    }
                }
                ActionButton {
                    objectName: "inspectorToolbarButton"
                    text: "3D inspection"
                    primary: window.page === 6
                    onClicked: {
                        window.page = 6;
                        orbit.openViewer(3);
                    }
                }
                ActionButton {
                    objectName: "quickHelpButton"
                    text: "How it works"
                    onClicked: quickHelp.open()
                }
                ActionButton {
                    text: "About"
                    onClicked: about.open()
                }
                ActionButton {
                    text: "Open report ↗"
                    primary: true
                    enabled: orbit.canControl && orbit.state.run_id !== "—"
                    onClicked: orbit.action("export")
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: theme.line
        }
        Flickable {
            id: navigation
            Layout.fillWidth: true
            Layout.leftMargin: 26
            Layout.rightMargin: 26
            Layout.topMargin: 13
            Layout.bottomMargin: 13
            Layout.preferredHeight: 44
            contentWidth: navigationRow.implicitWidth
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
            RowLayout {
                id: navigationRow
                height: navigation.height
                spacing: 8
                Repeater {
                    model: ["01  Mission", "02  F Prime", "03  Recordings", "04  Engineering", "05  Targets and data", "06  Tests and comparisons", "07  3D view", "08  F Prime sequences", "09  Orbit and passes"]
                    ActionButton {
                        required property int index
                        required property string modelData
                        text: modelData
                        objectName: "pageButton-" + index
                        primary: window.page === index
                        onClicked: window.page = index
                    }
                }
                Text {
                    text: orbit.status.mode === "REPLAY" ? "REPLAY" : orbit.status.playing ? "MISSION RUNNING" : orbit.status.fprime_running ? "PAUSED" : "READY"
                    color: theme.muted
                    font.pixelSize: 13
                    font.letterSpacing: 1
                }
            }
        }
        ScrollView {
            id: pageScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 26
            Layout.rightMargin: 26
            Layout.bottomMargin: 16
            clip: true
            contentWidth: window.page === 6 ? availableWidth : Math.max(availableWidth, 1120)
            contentHeight: window.page === 6 ? Math.max(availableHeight, 600) : Math.max(window.height - 220, window.page === 0 ? (advanced.checked ? 1060 : 850) : 740)
            ScrollBar.vertical.policy: contentHeight > availableHeight ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
            StackLayout {
                id: pages
                width: pageScroll.contentWidth
                height: pageScroll.contentHeight
                currentIndex: window.page
                RowLayout {
                    spacing: 16
                    ScrollView {
                        id: configurationScroll
                        Layout.preferredWidth: 350
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        Layout.preferredHeight: 0
                        clip: true
                        contentWidth: availableWidth
                        contentHeight: Math.max(configurationPanel.implicitHeight, pages.height)
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
                        Panel {
                            id: configurationPanel
                            width: configurationScroll.availableWidth
                            height: configurationScroll.contentHeight
                            title: orbit.status.fprime_running ? "NEW SESSION · SETTINGS" : "1 · CHOOSE AN OBSERVATION"
                            Text {
                                Layout.fillWidth: true
                                visible: orbit.status.fprime_running
                                text: "These fields prepare a new session. Targets in the active session appear in the mission panel and in Targets and data."
                                color: theme.muted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "Test conditions"
                                color: theme.ink
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            ConsoleComboBox {
                                id: scenario
                                Layout.fillWidth: true
                                model: ["Nominal mission", "Insufficient energy", "Temporary sensor outage"]
                            }
                            ConsoleCheckBox {
                                id: advanced
                                text: "Advanced options"
                                checked: false
                            }
                            Text {
                                visible: advanced.checked
                                text: "Decision strategy"
                                color: theme.muted
                                font.pixelSize: 13
                            }
                            ConsoleComboBox {
                                id: strategy
                                visible: advanced.checked
                                Layout.fillWidth: true
                                model: ["Respect available energy", "Prioritize targets"]
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: theme.line
                            }
                            Text {
                                text: orbit.status.fprime_running ? "Initial target for the new session" : "Ground target"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: theme.ink
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            ConsoleComboBox {
                                id: targetChoice
                                objectName: "missionTargetSelector"
                                Layout.fillWidth: true
                                model: ["Rome · first observation", "Custom coordinates", "New York", "Paris", "Tokyo"]
                                onActivated: index => {
                                    if (index === 0) {
                                        latitude.text = "41.9028";
                                        longitude.text = "12.4964";
                                    }
                                    if (index === 2) {
                                        latitude.text = "40.7128";
                                        longitude.text = "-74.0060";
                                    }
                                    if (index === 3) {
                                        latitude.text = "48.8566";
                                        longitude.text = "2.3522";
                                    }
                                    if (index === 4) {
                                        latitude.text = "35.6762";
                                        longitude.text = "139.6503";
                                    }
                                }
                            }
                            RowLayout {
                                visible: true
                                ConsoleTextField {
                                    id: latitude
                                    Layout.fillWidth: true
                                    text: "41.9028"
                                    placeholderText: "Latitude [degrees]"
                                    validator: DoubleValidator {
                                        bottom: -90
                                        top: 90
                                        locale: "C"
                                    }
                                }
                                ConsoleTextField {
                                    id: longitude
                                    Layout.fillWidth: true
                                    text: "12.4964"
                                    placeholderText: "Longitude [degrees]"
                                    validator: DoubleValidator {
                                        bottom: -180
                                        top: 180
                                        locale: "C"
                                    }
                                }
                            }
                            RowLayout {
                                visible: advanced.checked
                                Text {
                                    text: "Priority"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                ConsoleSpinBox {
                                    id: priority
                                    from: 0
                                    to: 100
                                    value: 80
                                }
                            }
                            ConsoleCheckBox {
                                id: rtems
                                visible: advanced.checked
                                text: "RTEMS / Renode energy controller"
                                font.pixelSize: 13
                                enabled: orbit.status.rtems_available === true
                            }
                            ConsoleCheckBox {
                                id: continuousMission
                                visible: advanced.checked
                                text: "Continuous mission · until Finish"
                                checked: true
                            }
                            RowLayout {
                                visible: advanced.checked
                                ConsoleCheckBox {
                                    id: repeatInitial
                                    text: "Repeat target [s]"
                                    checked: false
                                }
                                ConsoleSpinBox {
                                    id: initialRepeatInterval
                                    from: 60
                                    to: 604800
                                    value: 5400
                                    stepSize: 60
                                    enabled: repeatInitial.checked
                                }
                            }
                            ActionButton {
                                Layout.fillWidth: true
                                text: orbit.status.backend_starting ? "Preparing..." : orbit.status.fprime_running ? "Start new session" : "Start observation"
                                objectName: "missionStartButton"
                                primary: true
                                enabled: orbit.canControl && latitude.acceptableInput && longitude.acceptableInput
                                onClicked: {
                                    orbit.start(["nominal", "low-energy", "sensor-outage"][scenario.currentIndex], strategy.currentIndex === 0 ? "energy-aware" : "priority-first", Number(latitude.text), Number(longitude.text), priority.value, rtems.checked, continuousMission.checked, repeatInitial.checked ? initialRepeatInterval.value : 0);
                                    orbit.setSpeed([1, 10, 60, 600][missionSpeed.currentIndex]);
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !orbit.canControl || !latitude.acceptableInput || !longitude.acceptableInput
                                text: !orbit.canControl ? orbit.controlStatus : "Enter valid latitude and longitude in decimal degrees."
                                color: theme.muted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            ActionButton {
                                objectName: "missionReconnectButton"
                                text: "Reconnect service"
                                visible: !orbit.canControl && !orbit.status.backend_starting
                                onClicked: orbit.reconnect()
                            }
                            RowLayout {
                                ActionButton {
                                    text: orbit.status.playing ? "Pause" : "Resume"
                                    objectName: "missionPauseButton"
                                    enabled: orbit.canControl && orbit.state.run_id !== "—"
                                    onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
                                }
                                ActionButton {
                                    visible: advanced.checked
                                    text: "Step"
                                    enabled: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
                                    onClicked: orbit.action("step")
                                }
                                ActionButton {
                                    text: "Finish"
                                    enabled: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
                                    onClicked: orbit.action("finish")
                                }
                            }
                            RowLayout {
                                Text {
                                    text: "Time scale"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                                ConsoleComboBox {
                                    id: missionSpeed
                                    objectName: "missionSpeedSelector"
                                    Layout.fillWidth: true
                                    model: ["1×", "10×", "60×", "600×"]
                                    currentIndex: 1
                                    onActivated: orbit.setSpeed([1, 10, 60, 600][currentIndex])
                                }
                            }
                            Rectangle {
                                visible: advanced.checked
                                Layout.fillWidth: true
                                height: 1
                                color: theme.line
                            }
                            Text {
                                visible: advanced.checked
                                text: "Inject a fault"
                                color: theme.ink
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            ConsoleComboBox {
                                id: faultKind
                                visible: advanced.checked
                                Layout.fillWidth: true
                                model: ["Attitude sensor", "Solar generation", "Reaction wheel", "Ground link"]
                            }
                            RowLayout {
                                visible: advanced.checked
                                Text {
                                    text: "Duration [s]"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                ConsoleSpinBox {
                                    id: faultDuration
                                    from: 1
                                    to: 86400
                                    value: 30
                                }
                            }
                            ActionButton {
                                visible: advanced.checked
                                Layout.fillWidth: true
                                text: "Inject fault"
                                enabled: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
                                onClicked: orbit.injectPhysicalFault(["attitude_sensor", "solar_generation", "reaction_wheel", "ground_link"][faultKind.currentIndex], faultDuration.value)
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        MissionWorkflow {
                            id: missionWorkflow
                            Layout.fillWidth: true
                            Layout.preferredHeight: 340
                            onShowData: window.page = 4
                            onInspectImage: filename => {
                                observationPreview.filename = filename;
                                observationPreview.open();
                            }
                            onShowScene: {
                                window.page = 6;
                                orbit.openViewer(0);
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 164
                            color: theme.navy
                            radius: 10
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 12
                                RowLayout {
                                    Text {
                                        text: "F′"
                                        color: "#a6b8ff"
                                        font.pixelSize: 38
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: "F PRIME  /  FLIGHT SOFTWARE"
                                        color: "white"
                                        font.pixelSize: 19
                                        font.weight: Font.DemiBold
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: orbit.status.fprime_running ? "MISSION SOFTWARE ACTIVE" : "READY TO START"
                                        color: orbit.status.fprime_running ? "#64d9c2" : "#aab8d2"
                                        font.pixelSize: 13
                                        font.letterSpacing: 1
                                    }
                                }
                                RowLayout {
                                    spacing: 10
                                    Repeater {
                                        model: [
                                            {
                                                title: "Native command dispatcher",
                                                detail: "Svc.CommandDispatcher"
                                            },
                                            {
                                                title: "Mission",
                                                detail: missionWorkflow.phaseTitle
                                            },
                                            {
                                                title: "Basilisk dynamics",
                                                detail: "Spacecraft · wheels · power"
                                            },
                                            {
                                                title: "F Prime telemetry",
                                                detail: orbit.channels.length + " native channels"
                                            }
                                        ]
                                        Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 72
                                            color: "#1c2b43"
                                            radius: 6
                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 5
                                                Text {
                                                    text: modelData.title
                                                    color: "#dce5f8"
                                                    font.pixelSize: 13
                                                }
                                                Text {
                                                    text: modelData.detail
                                                    color: "#8fa5c9"
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Metric {
                                Layout.fillWidth: true
                                label: "BATTERY"
                                value: orbit.state.run_id === "—" ? "—" : window.number(orbit.state.soc_percent, 1)
                                unit: "%"
                                accent: theme.teal
                            }
                            Metric {
                                Layout.fillWidth: true
                                label: "POINTING ERROR"
                                value: orbit.state.run_id === "—" ? "—" : orbit.state.phase_id === 4 || orbit.state.phase_id === 5 ? window.number(orbit.state.truth_pointing_error_deg, 3) : "—"
                                unit: orbit.state.phase_id === 4 || orbit.state.phase_id === 5 ? "deg" : ""
                            }
                            Metric {
                                Layout.fillWidth: true
                                label: "GENERATION / LOAD"
                                value: window.number(orbit.state.generation_w, 0) + " / " + window.number(orbit.state.consumed_w, 0)
                                unit: "W"
                            }
                            Metric {
                                Layout.fillWidth: true
                                label: "ONBOARD / DELIVERED"
                                value: orbit.state.queue_depth + " / " + orbit.state.completed
                                unit: "immagini"
                            }
                        }
                        RowLayout {
                            visible: advanced.checked
                            Layout.fillWidth: true
                            Layout.preferredHeight: 176
                            spacing: 12
                            TraceChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                title: "BATTERY STATE OF CHARGE [%]"
                                field: "soc_percent"
                                maximum: 100
                                lineColor: theme.teal
                            }
                            TraceChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                title: "ACTIVE POINTING ERROR [deg]"
                                field: "pointing_error_deg"
                                maximum: 10
                            }
                        }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            title: "MISSION EVENTS · F PRIME"
                            RowLayout {
                                Text {
                                    text: window.number(orbit.state.time_s, 1) + " s"
                                    color: theme.ink
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: missionWorkflow.phaseTitle
                                    color: theme.accent
                                    font.pixelSize: 13
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "RUN " + orbit.state.run_id
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                            }
                            ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: orbit.state.duration_s || 1
                                value: orbit.state.time_s
                                indeterminate: orbit.state.continuous && orbit.status.playing && orbit.status.mode === "LIVE"
                            }
                            Text {
                                visible: advanced.checked
                                Layout.fillWidth: true
                                text: orbit.state.reason + "   ·   available " + window.number(orbit.state.energy_j, 0) + " J / required " + window.number(orbit.state.required_energy_j, 0) + " J"
                                color: theme.muted
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: advanced.checked
                                Layout.fillWidth: true
                                text: "Observation access: " + (orbit.state.window_end_s > orbit.state.window_start_s ? window.number(orbit.state.window_start_s, 1) + "–" + window.number(orbit.state.window_end_s, 1) + " s" : "no active prediction") + " · Optical payload: " + (!orbit.state.attitude_valid ? "inhibited / sensor unavailable" : orbit.state.phase_id === 5 ? "exposing" : orbit.state.phase_id === 4 ? "pointing" : "standby") + " · Onboard " + orbit.state.stored_bytes + " B / ground " + orbit.state.delivered_bytes + " B"
                                color: theme.muted
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: orbit.events
                                spacing: 5
                                onCountChanged: positionViewAtEnd()
                                delegate: RowLayout {
                                    required property var modelData
                                    width: ListView.view.width
                                    height: 29
                                    spacing: 10
                                    Text {
                                        Layout.preferredWidth: 68
                                        text: window.number(modelData.time_s, 1) + " s"
                                        color: theme.muted
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        Layout.preferredWidth: 160
                                        text: !advanced.checked && modelData.name.endsWith("DecisionChanged") ? "F Prime decision" : modelData.name.replace("OrbitLab.", "")
                                        color: theme.accent
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: advanced.checked ? modelData.text : window.missionEventText(modelData)
                                        color: theme.ink
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }
                                ScrollBar.vertical: ScrollBar {}
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: 16
                    CommandComposer {
                        Layout.preferredWidth: 440
                        Layout.minimumWidth: 440
                        Layout.maximumWidth: 440
                        Layout.fillHeight: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14
                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 264
                            title: "F PRIME · TOPOLOGY AND MISSION CORE"
                            TopologyView {
                                Layout.fillWidth: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "FPP defines commands, channels, events and ports. The Mission component calls SiliconLogiX.OrbitLab.Core through ABI 2 for planning, energy assessment, protection and attitude control."
                                color: theme.muted
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "Basilisk step " + orbit.state.runtime.step_s + " s → F Prime " + window.number(orbit.state.runtime.fprime_step_ms, 2) + " ms · " + orbit.state.runtime.native_packets + " native packets"
                                color: theme.accent
                                font.pixelSize: 14
                            }
                        }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            title: "NATIVE TELEMETRY CHANNELS"
                            ConsoleTextField {
                                id: channelFilter
                                Layout.fillWidth: true
                                placeholderText: "Search telemetry channels…"
                                onTextChanged: orbit.filterTelemetry(text)
                            }
                            RowLayout {
                                Text {
                                    Layout.fillWidth: true
                                    text: "CHANNEL"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                                Text {
                                    Layout.preferredWidth: 150
                                    text: "CONFIRMED VALUE"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                                Text {
                                    Layout.preferredWidth: 100
                                    text: "UNITS"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                            }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                objectName: "nativeTelemetryList"
                                model: orbit.telemetryModel
                                clip: true
                                spacing: 3
                                delegate: RowLayout {
                                    required property string channelName
                                    required property var channelValue
                                    width: ListView.view.width
                                    height: 38
                                    Text {
                                        Layout.fillWidth: true
                                        text: channelName
                                        color: theme.ink
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        Layout.preferredWidth: 150
                                        text: window.nativeValue(channelValue)
                                        color: orbit.stale ? "#955a12" : theme.teal
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        Layout.preferredWidth: 100
                                        text: window.unit(channelName)
                                        color: theme.muted
                                        font.pixelSize: 13
                                    }
                                }
                                ScrollBar.vertical: ScrollBar {}
                            }
                            Text {
                                text: orbit.state.run_id === "—" ? "Load a mission to initialize sensor and EPS telemetry." : "Sensor: " + (orbit.state.attitude_valid ? "AVAILABLE" : "UNAVAILABLE") + " · EPS: " + orbit.state.eps.mode + " · flags " + orbit.state.eps.flags + " · heartbeat " + orbit.state.eps.heartbeat
                                color: orbit.state.run_id === "—" ? theme.muted : orbit.state.attitude_valid ? theme.teal : "#955a12"
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Basilisk estimated attitude q body→ECI [w,x,y,z]: " + window.vector(orbit.state.quaternion_body_to_eci)
                                color: theme.muted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Simulator truth q body→ECI: " + window.vector(orbit.state.truth_quaternion_body_to_eci) + " · navigation error " + window.number(orbit.state.attitude_estimation_error_deg, 5) + " deg"
                                color: theme.muted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: 16
                    RecordingsList {
                        Layout.preferredWidth: 445
                        Layout.fillHeight: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16
                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 206
                            title: "SYNCHRONIZED REPLAY"
                            Text {
                                text: orbit.status.mode === "REPLAY" ? "Recording loaded · integrity verified" : "Choose a recording and click Replay"
                                color: theme.ink
                                font.pixelSize: 16
                            }
                            Slider {
                                Layout.fillWidth: true
                                from: 0
                                to: orbit.state.duration_s || 1
                                value: orbit.state.time_s
                                enabled: orbit.status.mode === "REPLAY" && orbit.canControl
                                onMoved: orbit.seek(value)
                            }
                            RowLayout {
                                ActionButton {
                                    text: orbit.status.playing ? "Pause" : "Resume"
                                    enabled: orbit.status.mode === "REPLAY" && orbit.canControl
                                    onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
                                }
                                Text {
                                    text: window.number(orbit.state.time_s, 1) + " s · " + orbit.state.phase
                                    color: theme.accent
                                    font.pixelSize: 14
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Drag the slider to revisit a mission moment: 3D view, telemetry, commands and events follow the same recording."
                                color: theme.muted
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                        }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            title: "STRATEGY COMPARISON · SAME MISSION"
                            RowLayout {
                                ActionButton {
                                    text: orbit.status.busy ? "Comparison running…" : "Compare strategies"
                                    primary: true
                                    enabled: orbit.canControl && orbit.state.run_id !== "—"
                                    onClicked: orbit.action("compare")
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "Priority ↔ available energy"
                                    color: theme.muted
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Both strategies use the same targets, orbit and faults with separate F Prime processes and Basilisk simulations. Both protect the minimum battery reserve."
                                color: theme.muted
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: orbit.comparison
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 116
                                    color: theme.canvas
                                    radius: 7
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 15
                                        spacing: 8
                                        Text {
                                            text: modelData.strategy
                                            color: theme.ink
                                            font.pixelSize: 17
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: "Delivered " + modelData.completed_observations + "  ·  deferred " + modelData.deferred_observations + "  ·  remaining energy " + window.number(modelData.final_energy_j / 3600, 2) + " Wh"
                                            color: theme.teal
                                            font.pixelSize: 14
                                        }
                                        Text {
                                            text: "Acquisition pointing RMS: " + (modelData.pointing_rms_deg === null ? "no image acquired" : window.number(modelData.pointing_rms_deg, 4) + " degrees") + " · run " + modelData.run_id
                                            color: theme.muted
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "HTML reports, CSV telemetry and acquired products."
                                color: theme.muted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                ColumnLayout {
                    spacing: 16
                    Panel {
                        Layout.fillWidth: true
                        title: "SILICON LOGIX / CUSTOM MISSION SOFTWARE"
                        Text {
                            text: "Custom mission software and systems"
                            color: theme.ink
                            font.pixelSize: 23
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "F Prime components, guidance systems, energy models, embedded firmware and verification campaigns. Select areas of interest to prepare a project enquiry."
                            color: theme.muted
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 3
                        rowSpacing: 16
                        columnSpacing: 16
                        Repeater {
                            model: orbit.capabilities
                            Panel {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                title: "CUSTOM DEVELOPMENT"
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: theme.ink
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.technique
                                    color: theme.muted
                                    font.pixelSize: 14
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Inputs: " + modelData.inputs
                                    color: theme.muted
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Verification: " + modelData.validation
                                    color: theme.teal
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                                Item {
                                    Layout.fillHeight: true
                                }
                                ConsoleCheckBox {
                                    text: "Include in the project enquiry"
                                    onToggled: {
                                        let selected = window.selectedModules.slice();
                                        if (checked)
                                            selected.push(modelData.id);
                                        else
                                            selected = selected.filter(id => id !== modelData.id);
                                        window.selectedModules = selected;
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        ActionButton {
                            text: "Save project enquiry"
                            primary: true
                            enabled: window.selectedModules.length > 0
                            onClicked: orbit.saveBrief(window.selectedModules)
                        }
                        ActionButton {
                            text: "Contact Silicon LogiX ↗"
                            onClicked: Qt.openUrlExternally(orbit.product.contact)
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
                OperationsPage {}
                VerificationPage {}
                InspectorPage {
                    obscured: about.visible || quickHelp.visible || legal.visible || observationPreview.visible
                }
                SequencePage {}
                OrbitPage {}
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: "white"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                Text {
                    Layout.fillWidth: true
                    text: orbit.message
                    color: theme.muted
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Text {
                    text: "© 2026 Marco Pezzullo · Silicon LogiX"
                    color: theme.muted
                    font.pixelSize: 13
                }
            }
        }
    }
    AboutDialog {
        id: about
        objectName: "aboutDialog"
        anchors.centerIn: parent
        onLegalRequested: document => {
            legal.content = orbit.legalText(document);
            legal.open();
        }
    }
    Dialog {
        id: observationPreview
        objectName: "observationPreviewDialog"
        property string filename: ""
        title: "Simulated Earth observation"
        anchors.centerIn: parent
        width: Math.min(820, window.width - 50)
        height: Math.min(660, window.height - 70)
        modal: true
        focus: true
        Image {
            anchors.fill: parent
            source: observationPreview.filename ? orbit.productUrl(observationPreview.filename) : ""
            fillMode: Image.PreserveAspectFit
        }
        footer: DialogButtonBox {
            ActionButton {
                objectName: "observationPreviewClose"
                text: "Close"
                onClicked: observationPreview.close()
            }
        }
    }
    Dialog {
        id: quickHelp
        objectName: "quickHelpDialog"
        title: "SLX OrbitLab · Guided first observation"
        anchors.centerIn: parent
        width: Math.min(760, window.width - 50)
        height: Math.min(455, window.height - 60)
        modal: false
        dim: false
        focus: true
        onOpened: {
            window.requestActivate();
            forceActiveFocus();
        }
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        standardButtons: Dialog.Close
        ScrollView {
            id: helpScroll
            anchors.fill: parent
            contentWidth: availableWidth
            contentHeight: helpText.implicitHeight
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOn
            Text {
                id: helpText
                width: helpScroll.availableWidth
                color: theme.ink
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                text: "1. Keep Rome and Nominal mission, then click Start observation.\n\n2. Follow the workflow: target → pointing → image onboard → delivered to ground. The satellite first needs a suitable pass over the target.\n\n3. Acquisition creates a simulated sensor image and stores it onboard. The file reaches the ground during a ground station contact.\n\n4. The preview shows the generated data. Once Image delivered to ground appears, click Open received data. This simulated image verifies the full command, acquisition, storage and downlink path.\n\n5. 3D view shows the satellite. Pause stops simulated time; Resume continues; Finish prepares the report. F Prime contains the command console; Advanced options include priority, repeat intervals and faults."
            }
        }
    }
    Dialog {
        id: legal
        property string content: ""
        title: "SLX OrbitLab · License and attribution"
        anchors.centerIn: parent
        width: 800
        height: 600
        modal: true
        standardButtons: Dialog.Close
        ScrollView {
            anchors.fill: parent
            TextArea {
                text: legal.content
                readOnly: true
                wrapMode: TextEdit.Wrap
                selectByMouse: true
            }
        }
    }
}
