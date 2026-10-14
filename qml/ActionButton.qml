// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Consistent desktop actions and interaction states.
import QtQuick
import QtQuick.Controls

Button {
    id: control

    property bool dark: false
    property bool primary: false

    font.pixelSize: 14
    font.weight: Font.DemiBold
    hoverEnabled: true
    implicitHeight: 42
    implicitWidth: label.implicitWidth + 28

    background: Rectangle {
        border.color: !control.enabled ? "#c1cad9" : control.activeFocus ? "#3436aa" : control.primary ? "#4c4ed7" : control.dark ? "#536680" : "#b8c3d4"
        border.width: control.activeFocus ? 2 : 1
        color: !control.enabled ? "#edf0f5" : control.primary ? (control.down ? "#3436aa" : control.hovered ? "#4143c2" : "#4c4ed7") : control.dark ? (control.hovered ? "#283954" : "#1c2b43") : (control.hovered ? "#edf0f8" : "white")
        radius: 6
    }
    contentItem: Text {
        id: label

        color: !control.enabled ? "#56647a" : control.primary ? "white" : control.dark ? "#dce5f8" : "#192541"
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        text: control.text
        verticalAlignment: Text.AlignVCenter
    }
}
