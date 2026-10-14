// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Bounded numeric input with clear plus/minus controls and keyboard focus.
import QtQuick
import QtQuick.Controls

SpinBox {
    id: control
    implicitHeight: 42
    implicitWidth: 132
    font.pixelSize: 14
    leftPadding: 34
    rightPadding: 34
    background: Rectangle {
        color: "white"
        radius: 6
        border.color: control.activeFocus ? "#4c4ed7" : "#b8c3d4"
    }
    contentItem: TextInput {
        text: control.textFromValue(control.value, control.locale)
        font: control.font
        color: "#192541"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
    }
    up.indicator: Rectangle {
        x: control.width - width
        width: 34
        height: control.height
        radius: 5
        color: control.up.pressed ? "#dfe2fa" : "#edf0f7"
        Text {
            anchors.centerIn: parent
            text: "+"
            color: "#192541"
            font.pixelSize: 20
        }
    }
    down.indicator: Rectangle {
        width: 34
        height: control.height
        radius: 5
        color: control.down.pressed ? "#dfe2fa" : "#edf0f7"
        Text {
            anchors.centerIn: parent
            text: "−"
            color: "#192541"
            font.pixelSize: 20
        }
    }
}
