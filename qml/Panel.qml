// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Consistent technical panels with an accessible section label.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: panel
    property string title: ""
    default property alias content: body.data
    color: "white"
    radius: 10
    border.color: "#e3e8f0"
    implicitHeight: body.implicitHeight + 64
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        Text {
            text: panel.title
            color: "#56647a"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
        }
    }
}
