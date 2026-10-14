// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Confirmed telemetry value and explicit engineering unit.
import QtQuick
import QtQuick.Layouts

Rectangle {
    property string label: ""
    property string value: "—"
    property string unit: ""
    property color accent: "#4c4ed7"
    color: "white"
    radius: 8
    border.color: "#e3e8f0"
    implicitHeight: 110
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: label
            color: "#56647a"
            font.pixelSize: 13
            font.letterSpacing: 0.7
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        RowLayout {
            Text {
                text: value
                color: accent
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }
            Text {
                text: unit
                color: "#56647a"
                font.pixelSize: 13
            }
        }
    }
}
