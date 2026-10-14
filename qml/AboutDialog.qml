// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Product identity, evaluation terms, runtime versions and contact actions.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root

    signal legalRequested(string document)

    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    focus: true
    modal: true
    objectName: "slxAboutDialog"
    padding: 0
    width: 680

    background: Rectangle {
        border.color: "#dfe5f0"
        color: "white"
        radius: 14
    }
    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 145
            color: "#111c31"
            radius: 14

            Rectangle {
                anchors.bottom: parent.bottom
                color: parent.color
                height: 14
                width: parent.width
            }
            Rectangle {
                color: "#1c2b43"
                height: 54
                radius: 5
                width: 100
                x: 24
                y: 20

                Image {
                    anchors.fill: parent
                    anchors.margins: 5
                    fillMode: Image.PreserveAspectFit
                    source: orbit.logoUrl
                }
            }
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 24
                anchors.right: parent.right

                Text {
                    Layout.fillWidth: true
                    color: "white"
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    text: "SLX OrbitLab"
                }
                Text {
                    color: "#c8cffa"
                    font.pixelSize: 14
                    text: "v" + orbit.product.version
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                height: 3
                width: parent.width

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        color: "#4c4ed7"
                        position: 0
                    }
                    GradientStop {
                        color: "#d235e9"
                        position: 1
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            spacing: 15

            Text {
                Layout.fillWidth: true
                color: "#273754"
                font.pixelSize: 13
                lineHeight: 1.35
                text: "Mission software demonstrator with NASA F Prime, Basilisk dynamics, traceable commands and repeatable verification scenarios."
                wrapMode: Text.WordWrap
            }
            GridLayout {
                Layout.fillWidth: true
                columnSpacing: 20
                columns: 2
                rowSpacing: 9

                Repeater {
                    model: [
                        {
                            label: "AUTHOR",
                            value: orbit.product.author
                        },
                        {
                            label: "TECHNOLOGY",
                            value: "C++17 · Qt Quick · F Prime 4.3.0 · Basilisk 2.12.0 · Godot 4.5"
                        },
                        {
                            label: "RUNTIME",
                            value: "Qt " + orbit.product.qtVersion + " · scene " + orbit.product.sceneVersion
                        },
                        {
                            label: "CORE",
                            value: "SiliconLogiX.OrbitLab.Core · ABI " + orbit.product.coreAbi
                        },
                        {
                            label: "COPYRIGHT",
                            value: "© 2026 Marco Pezzullo (Silicon LogiX)"
                        }
                    ]

                    RowLayout {
                        required property var modelData

                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 18

                        Text {
                            Layout.preferredWidth: 120
                            color: "#56647a"
                            font.letterSpacing: 1
                            font.pixelSize: 13
                            text: modelData.label
                        }
                        Text {
                            Layout.fillWidth: true
                            color: "#273754"
                            font.pixelSize: 13
                            text: modelData.value
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
            RowLayout {
                ActionButton {
                    text: "F′ / NASA JPL ↗"
                    onClicked: Qt.openUrlExternally("https://fprime.jpl.nasa.gov/")
                }
                ActionButton {
                    text: "Basilisk ↗"
                    onClicked: Qt.openUrlExternally("https://avslab.github.io/basilisk/")
                }
                ActionButton {
                    text: "Qt ↗"
                    onClicked: Qt.openUrlExternally("https://www.qt.io/")
                }
                ActionButton {
                    text: "Godot ↗"
                    onClicked: Qt.openUrlExternally("https://godotengine.org/")
                }
            }
            Rectangle {
                Layout.fillWidth: true
                color: "#e3e8f0"
                height: 1
            }
            Text {
                Layout.fillWidth: true
                color: "#56647a"
                font.pixelSize: 13
                lineHeight: 1.35
                text: orbit.product.license
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true

                ActionButton {
                    text: "License"

                    onClicked: root.legalRequested("license")
                }
                ActionButton {
                    text: "Third-party notices"

                    onClicked: root.legalRequested("notices")
                }
                ActionButton {
                    text: "Qt license"

                    onClicked: root.legalRequested("qt")
                }
            }
            RowLayout {
                Layout.fillWidth: true

                ActionButton {
                    text: "Silicon LogiX website"

                    onClicked: Qt.openUrlExternally(orbit.product.website)
                }
                ActionButton {
                    primary: true
                    text: "Discuss a project ↗"

                    onClicked: Qt.openUrlExternally(orbit.product.contact)
                }
                Item {
                    Layout.fillWidth: true
                }
                ActionButton {
                    text: "Close"

                    onClicked: root.close()
                }
            }
        }
    }
}
