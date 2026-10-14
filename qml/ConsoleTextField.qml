// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Engineering input fields retain validators and use legible explicit colors.
import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: 42
    font.pixelSize: 14
    color: "#192541"
    placeholderTextColor: "#56647a"
    selectionColor: "#4c4ed7"
    selectedTextColor: "white"
    leftPadding: 12
    rightPadding: 12
    background: Rectangle {
        radius: 6
        color: control.enabled ? "white" : "#edf0f5"
        border.color: control.activeFocus ? "#4c4ed7" : "#b8c3d4"
        border.width: control.activeFocus ? 2 : 1
    }
}
