// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Checkable options keep readable text in both enabled and unavailable states.
import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: Math.max(30, contentItem.implicitHeight)
    font.pixelSize: 13
    spacing: 10
    indicator: Rectangle {
        x: control.leftPadding
        y: (control.height - height) / 2
        width: 21
        height: 21
        radius: 4
        color: control.checked ? "#4c4ed7" : "white"
        border.color: control.activeFocus || control.checked ? "#4c4ed7" : "#8394b0"
        border.width: control.activeFocus ? 2 : 1
        Text {
            anchors.centerIn: parent
            text: control.checked ? "✓" : ""
            color: "white"
            font.pixelSize: 15
        }
    }
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? "#192541" : "#56647a"
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
        wrapMode: Text.WordWrap
    }
}
