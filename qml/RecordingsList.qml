// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Readable mission cards sized from their content and stable between telemetry updates.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Panel {
    id: root
    title: "RECORDED MISSIONS"
    property var filteredRuns: []
    function refresh() {
        const query = search.text.trim().toLowerCase();
        filteredRuns = orbit.runs.filter(run => [run.scenario, run.strategy, run.run_id].join(" ").toLowerCase().includes(query));
    }
    function policy(value) {
        return value === "energy-aware" ? "Energy strategy" : "Priority strategy";
    }
    function duration(seconds) {
        const total = Math.round(Number(seconds || 0));
        return total < 60 ? total + " s" : Math.floor(total / 60) + " min " + total % 60 + " s";
    }
    Component.onCompleted: refresh()
    Connections {
        target: orbit
        function onRunsChanged() {
            root.refresh();
        }
    }
    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            text: "Refresh"
            enabled: orbit.connected
            onClicked: orbit.action("runs")
        }
        Text {
            Layout.fillWidth: true
            text: root.filteredRuns.length + " recordings"
            color: "#56647a"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignRight
        }
    }
    ActionButton {
        Layout.fillWidth: true
        text: "Finish and save mission"
        enabled: orbit.canControl && orbit.status.fprime_running
        onClicked: orbit.action("finish")
    }
    ConsoleTextField {
        id: search
        objectName: "recordingsSearch"
        Layout.fillWidth: true
        placeholderText: "Search scenario, strategy or ID"
        onTextChanged: root.refresh()
    }
    ListView {
        id: recordings
        objectName: "recordingsList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: root.filteredRuns
        clip: true
        spacing: 10
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            objectName: "recordingCard-" + index
            width: ListView.view.width - 16
            height: details.implicitHeight + 28
            color: modelData.run_id === orbit.state.run_id ? "#edf0ff" : "#f3f5f9"
            border.color: modelData.run_id === orbit.state.run_id ? "#4c4ed7" : "#e3e8f0"
            radius: 8
            ColumnLayout {
                id: details
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 7
                Text {
                    Layout.fillWidth: true
                    text: card.modelData.scenario
                    color: "#192541"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: root.policy(card.modelData.strategy) + " · " + (card.modelData.finalized ? "Saved" : "Interim report")
                    color: "#56647a"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: card.modelData.completed_observations + " images delivered · " + root.duration(card.modelData.duration_s)
                    color: "#087762"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: "Final battery " + Number(card.modelData.final_energy_j / 3600).toFixed(2) + " Wh · RMS " + (card.modelData.pointing_rms_deg === null || card.modelData.pointing_rms_deg === undefined ? "—" : Number(card.modelData.pointing_rms_deg).toFixed(3) + "°")
                    color: "#192541"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: "ID " + card.modelData.run_id + (card.modelData.recorded_utc ? " · " + Qt.formatDateTime(new Date(card.modelData.recorded_utc), "dd/MM/yyyy HH:mm") : "")
                    color: "#56647a"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ActionButton {
                        objectName: "recordingReplay-" + card.index
                        Layout.fillWidth: true
                        text: "Replay"
                        primary: true
                        enabled: orbit.canControl && card.modelData.finalized === true
                        onClicked: orbit.replay(card.modelData.run_id)
                    }
                    ActionButton {
                        objectName: "recordingReport-" + card.index
                        Layout.fillWidth: true
                        text: "Report ↗"
                        onClicked: orbit.openReport(card.modelData.run_id)
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 28
            visible: recordings.count === 0
            text: search.text ? "No recordings match the search." : "Start a mission, then click Finish and save to find it here."
            color: "#56647a"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOn
        }
    }
}
