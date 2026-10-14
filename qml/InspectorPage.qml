// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Visible native Godot view; every spacecraft articulation comes from confirmed telemetry.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: inspectorPage
    property bool obscured: false
    spacing: 10
    RowLayout {
        Layout.fillWidth: true
        ConsoleComboBox {
            id: inspectionView
            objectName: "inspectorSceneSelector"
            Layout.preferredWidth: 270
            model: ["Satellite close-up", "Inspectable interior", "Exploded components", "Orbital view", "Ground station"]
            currentIndex: 3
            onActivated: index => orbit.openViewer(index)
        }
        ActionButton {
            objectName: "inspectorOpenButton"
            text: orbit.inspector.running ? "Reopen 3D" : "Open 3D"
            enabled: !orbit.inspector.installing
            primary: true
            onClicked: {
                orbit.inspector.close();
                orbit.openViewer(inspectionView.currentIndex);
            }
        }
        ActionButton {
            text: orbit.inspector.installing ? "Preparing 3D..." : "Repair 3D"
            visible: !orbit.inspector.available || orbit.inspector.installing
            enabled: !orbit.inspector.installing
            onClicked: orbit.inspector.install()
        }
        ActionButton {
            text: "Close"
            enabled: orbit.inspector.running
            onClicked: orbit.inspector.close()
        }
        ActionButton {
            objectName: "inspectorPauseButton"
            text: orbit.status.playing ? "Pause" : "Resume"
            enabled: orbit.canControl && orbit.status.fprime_running
            onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: "Time"
            font.pixelSize: 13
            color: "#56647a"
        }
        ConsoleComboBox {
            objectName: "inspectorSpeedSelector"
            Layout.preferredWidth: 80
            model: ["1×", "10×", "60×", "600×"]
            currentIndex: Math.max(0, [1, 10, 60, 600].indexOf(Number(orbit.status.speed)))
            enabled: orbit.canControl
            onActivated: index => orbit.setSpeed([1, 10, 60, 600][index])
        }
        Text {
            visible: inspectorPage.width >= 1200
            text: orbit.inspector.ready ? (orbit.inspector.frame.connected ? "GODOT · BACKEND CONNECTED" : "GODOT · WAITING FOR BACKEND") : "GODOT 4.5 · INSPECTION"
            color: orbit.inspector.ready && orbit.inspector.frame.connected ? "#087762" : "#56647a"
            font.pixelSize: 13
        }
    }
    Text {
        Layout.fillWidth: true
        text: ["Satellite: watch maneuvers, panel deployment and beacon pulses", "Interior: inspect sensors, battery and instruments; select and isolate a component", "Exploded: locate subsystems and focus on a component", "Orbit: follow the trajectory, target and access window", "Station: check antenna tracking and data transfer"][inspectionView.currentIndex]
        color: "#56647a"
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        objectName: "inspectorStatus"
        text: orbit.inspector.message
        visible: !orbit.inspector.ready
        color: "#192541"
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12
        ScrollView {
            id: vehicleScroll
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            contentWidth: availableWidth
            objectName: "vehicleControlsScroll"
            contentHeight: Math.max(900, availableHeight)
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOn
            VehiclePanel {
                id: vehiclePanel
                width: vehicleScroll.availableWidth
                height: vehicleScroll.contentHeight
                onSceneRequested: scene => orbit.openViewer(scene)
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 440
            color: "#101727"
            radius: 8
            Text {
                anchors.centerIn: parent
                width: Math.min(parent.width - 70, 620)
                text: orbit.inspector.installing ? "Preparing 3D models…\nThe view will open automatically." : orbit.inspector.running ? "Loading the 3D model..." : "Select a view and click Open 3D view."
                color: "#e7edf8"
                font.pixelSize: 19
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            WindowContainer {
                objectName: "inspectorWindowContainer"
                anchors.fill: parent
                window: orbit.inspector.window
                visible: inspectorPage.visible && !inspectorPage.obscured && !inspectionView.popup.visible && !vehiclePanel.popupVisible && orbit.inspector.running && orbit.inspector.embedded
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Right drag: orbit camera · Wheel: zoom · Click: select · Commands control the mission"
            color: "#56647a"
            wrapMode: Text.WordWrap
            font.pixelSize: 13
        }
        Text {
            text: orbit.inspector.ready ? "Simulated time " + Number(orbit.inspector.frame.time_s).toFixed(1) + " s" : ""
            color: "#087762"
            font.pixelSize: 13
        }
    }
    Connections {
        target: orbit.inspector
        function onChanged() {
            if (orbit.inspector.ready && !inspectionView.popup.visible)
                inspectionView.currentIndex = Number(orbit.inspector.frame.scene);
        }
    }
}
