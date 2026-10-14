// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Present observation progress and the actual stored product from confirmed mission telemetry.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Panel {
    id: workflow
    title: "OBSERVATION · FROM TARGET TO DELIVERED IMAGE"
    signal showData
    signal showScene
    signal inspectImage(string filename)
    readonly property bool started: orbit.state.run_id !== "—"
    readonly property var focusedTarget: {
        const targets = orbit.state.targets || [];
        const current = targets.find(t => Number(t.id) === Number(orbit.state.target_id) && !["retired", "expired"].includes(t.status));
        if (current && (["pending", "cooldown"].includes(current.status) || [5, 6].includes(Number(orbit.state.phase_id))))
            return current;
        const pending = targets.find(t => ["pending", "cooldown"].includes(t.status));
        if (pending)
            return pending;
        const products = orbit.state.products || [];
        const product = products.length ? products[products.length - 1] : null;
        if (product)
            return targets.find(t => Number(t.id) === Number(product.target_id)) || {
                id: product.target_id,
                name: product.target_name || "Target T" + product.target_id,
                status: product.status,
                acquired: 1
            };
        return current || targets[0] || ({});
    }
    readonly property bool awaitingSelection: focusedTarget.status === "pending" && Number(focusedTarget.id) !== Number(orbit.state.target_id)
    readonly property var queuedTargets: (orbit.state.targets || []).filter(t => ["pending", "cooldown"].includes(t.status) && Number(t.id) !== Number(orbit.state.target_id))
    readonly property var latest: {
        const products = (orbit.state.products || []).filter(p => Number(p.target_id) === Number(focusedTarget.id));
        return products.length ? products[products.length - 1] : {};
    }
    readonly property string targetName: {
        return focusedTarget.name || "No scheduled target";
    }
    readonly property string phaseTitle: {
        if (!started)
            return "Choose a target and start the observation";
        if (orbit.status.mode === "REPLAY")
            return "Recording replay";
        if (!orbit.status.playing && orbit.status.fprime_running)
            return "Mission paused";
        if (awaitingSelection)
            return "Target queued";
        const mode = Number((orbit.state.vehicle || {}).maneuver_mode || 0);
        if (mode && [2, 3, 10].indexOf(Number(orbit.state.phase_id)) < 0)
            return orbit.state.pointing_error_deg < 0.5 ? "Attitude reached" : ["", "Sun pointing", "Earth pointing", "Commanded rotation"][mode];
        if (orbit.state.reason === "OPTICAL_PAYLOAD_DISABLED")
            return "Optical instrument disabled";
        const titles = ["Preparing", "Waiting for access", "Waiting for energy", "Sensor unavailable", "Target pointing", "Image acquisition", "Image saved onboard", "Waiting for ground contact", "Image downlink", "Observation complete", "Satellite protection"];
        return titles[Number(orbit.state.phase_id)] || "Preparing";
    }
    readonly property string phaseDescription: {
        if (!started)
            return "The satellite will observe the target, create a simulated image and send it to the ground station. Click Start observation on the left.";
        if (orbit.status.mode === "REPLAY")
            return "The image and state follow the recording's timeline.";
        if (!orbit.status.playing && orbit.status.fprime_running)
            return "Click Resume to continue from the same point.";
        if (awaitingSelection)
            return "F Prime evaluates the new target on the next physics frame, considering access, priority and energy.";
        if (Number((orbit.state.vehicle || {}).maneuver_mode || 0) && orbit.state.phase_id === 4)
            return "F Prime commands the maneuver and Basilisk integrates motion. Click Resume automatic mission in the 3D view to continue observations.";
        if (orbit.state.reason === "OPTICAL_PAYLOAD_DISABLED")
            return "The operator disabled the instrument. Enable it from the 3D view to resume observation.";
        if (orbit.state.reason === "DOWNLINK_DISABLED_BY_OPERATOR")
            return "The operator disabled downlink. Data remains onboard.";
        switch (Number(orbit.state.phase_id)) {
        case 1:
            const remaining = Number(orbit.state.window_start_s) - Number(orbit.state.time_s);
            return remaining > 0 ? "The satellite needs a suitable pass over the target: approximately " + Math.ceil(remaining) + " simulated seconds until access." : orbit.state.window_start_s < 0 ? "No suitable pass predicted for this target. Choose another target in Targets and data." : "F Prime waits for suitable observation geometry.";
        case 2:
            return "The battery cannot support the activity: F Prime defers it and reduces consumption.";
        case 3:
            return "The attitude sensor is temporarily unavailable. Observation resumes when it recovers.";
        case 4:
            return "F Prime commands the reaction wheels; Basilisk computes the satellite attitude.";
        case 5:
            return "The sensor generates a simulated image and saves it onboard.";
        case 6:
            return "The image is in onboard storage. It now needs to reach the ground station.";
        case 7:
            return "The image is ready onboard; downlink waits for a ground station contact.";
        case 8:
            return "The file is being downlinked. Delivery is confirmed after integrity verification.";
        case 9:
            return "The data reached the ground. Open received data, add a target or finish the report.";
        case 10:
            return "The software suspended activities to protect the satellite. Check battery and events for the cause.";
        default:
            return "Preparing the satellite and instrument.";
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: ["1 · Target", "2 · Pointing", "3 · Image onboard", "4 · Delivered"]
            Rectangle {
                required property string modelData
                required property int index
                readonly property bool done: workflow.started && (index === 0 && workflow.focusedTarget.id !== undefined || index === 1 && workflow.latest.filename !== undefined || index === 2 && workflow.latest.filename !== undefined || index === 3 && workflow.latest.status === "delivered")
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 5
                color: done ? "#e4f4ec" : "#edf0f7"
                Text {
                    anchors.fill: parent
                    anchors.margins: 7
                    text: (parent.done ? "✓ " : "") + modelData
                    color: "#192541"
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20
        ColumnLayout {
            Layout.fillWidth: true
            Text {
                objectName: "observationPhaseTitle"
                Layout.fillWidth: true
                text: workflow.phaseTitle
                color: "#192541"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "missionActiveTarget"
                Layout.fillWidth: true
                text: (workflow.awaitingSelection ? "Queued target: " : "Target: ") + workflow.targetName + (workflow.focusedTarget.id !== undefined ? " · T" + workflow.focusedTarget.id : "")
                color: "#4c4ed7"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "missionQueuedTargets"
                Layout.fillWidth: true
                visible: workflow.queuedTargets.length > 0
                text: "Queued: " + workflow.queuedTargets.slice(0, 3).map(t => t.name + " (priority " + t.priority + ")").join(" · ") + (workflow.queuedTargets.length > 3 ? " · others " + (workflow.queuedTargets.length - 3) : "")
                color: "#56647a"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: workflow.phaseDescription
                color: "#56647a"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "observationResultStatus"
                Layout.fillWidth: true
                text: !workflow.latest.filename ? "Result: no image acquired" : workflow.latest.status === "delivered" ? "Image delivered to ground · integrity verified" : "Image saved onboard · " + Math.round(100 * Number(workflow.latest.sent_bytes) / Number(workflow.latest.size)) + "% transferred"
                color: workflow.latest.status === "delivered" ? "#087762" : "#4c4ed7"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            RowLayout {
                ActionButton {
                    text: workflow.latest.status === "delivered" ? "Open received data" : "Open onboard data"
                    enabled: workflow.latest.filename !== undefined
                    objectName: "observationOpenDataButton"
                    onClicked: orbit.openProducts()
                }
                ActionButton {
                    text: "Satellite in 3D"
                    onClicked: workflow.showScene()
                }
                ActionButton {
                    text: "More targets"
                    onClicked: workflow.showData()
                }
            }
        }
        ColumnLayout {
            Layout.preferredWidth: 224
            Layout.minimumWidth: 190
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 145
                color: "#edf0f7"
                radius: 6
                Image {
                    id: resultPreview
                    objectName: "observationImagePreview"
                    anchors.fill: parent
                    anchors.margins: 6
                    source: workflow.latest.filename ? orbit.productUrl(workflow.latest.preview_filename || workflow.latest.filename) : ""
                    fillMode: Image.PreserveAspectFit
                    MouseArea {
                        objectName: "observationPreviewButton"
                        anchors.fill: parent
                        enabled: workflow.latest.filename !== undefined
                        cursorShape: Qt.PointingHandCursor
                        onClicked: workflow.inspectImage(workflow.latest.preview_filename || workflow.latest.filename)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !workflow.latest.filename
                    text: "The image\nwill appear here"
                    color: "#56647a"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            Text {
                Layout.fillWidth: true
                text: workflow.latest.filename ? "Simulated Earth observation\nClick to enlarge · " + workflow.targetName : "No image for " + workflow.targetName
                color: "#56647a"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
