// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Readable selection fields with visible focus and consistent popup colors.
import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property real popupWidth: width
    implicitHeight: 42
    font.pixelSize: 14
    leftPadding: 12
    rightPadding: 32
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? "#192541" : "#56647a"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 12
        y: (control.height - height) / 2
        text: "▾"
        color: "#354563"
        font.pixelSize: 18
    }
    background: Rectangle {
        color: control.enabled ? "white" : "#edf0f5"
        radius: 6
        border.color: control.activeFocus ? "#4c4ed7" : control.hovered ? "#8394b0" : "#b8c3d4"
        border.width: control.activeFocus ? 2 : 1
    }
    delegate: ItemDelegate {
        id: menuItem
        objectName: control.objectName + "-option-" + index
        required property int index
        width: control.popup.width - 12
        height: 40
        // ComboBox resolves textRole for QVariantMap and string models alike.
        text: control.textAt(index)
        font.pixelSize: 14
        highlighted: control.highlightedIndex === index
        ToolTip.visible: hovered && label.truncated
        ToolTip.text: text
        contentItem: Text {
            id: label
            text: menuItem.text
            font: menuItem.font
            color: "#192541"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: menuItem.highlighted || menuItem.hovered ? "#ececff" : "white"
            radius: 4
        }
    }
    popup: Popup {
        popupType: Popup.Item
        y: control.height + 5
        width: control.popupWidth
        padding: 6
        implicitHeight: contentItem.implicitHeight + 12
        background: Rectangle {
            color: "white"
            radius: 7
            border.color: "#b8c3d4"
        }
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 320)
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
