// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Live observation jobs, confirmed data queue and Earth-fixed inspection.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    function productState(value) {
        return value === "delivered" ? "Delivered to ground" : value === "downlink" ? "Downlink active" : "Saved onboard";
    }
    function jobState(value) {
        const labels = {
            pending: "Waiting for access",
            cooldown: "Waiting for repeat interval",
            acquired: "Image onboard",
            delivered: "Image delivered",
            retired: "Closed",
            expired: "Expired"
        };
        return labels[value] || value;
    }
    spacing: 16
    property bool live: orbit.canControl && orbit.status.mode === "LIVE" && orbit.status.fprime_running
    property string selectedProduct: ""
    Theme {
        id: theme
    }
    Panel {
        Layout.preferredWidth: 340
        Layout.fillHeight: true
        title: "OBSERVATION TARGETS"
        ConsoleTextField {
            id: jobName
            objectName: "observationJobName"
            Layout.fillWidth: true
            text: "New target"
            maximumLength: 80
        }
        ConsoleComboBox {
            objectName: "observationCityPreset"
            Layout.fillWidth: true
            model: ["Map coordinates", "Rome", "New York", "Paris", "Tokyo"]
            onActivated: index => {
                if (index === 1) {
                    jobName.text = "Rome";
                    lat.text = "41.9028";
                    lon.text = "12.4964";
                }
                if (index === 2) {
                    jobName.text = "New York";
                    lat.text = "40.7128";
                    lon.text = "-74.0060";
                }
                if (index === 3) {
                    jobName.text = "Paris";
                    lat.text = "48.8566";
                    lon.text = "2.3522";
                }
                if (index === 4) {
                    jobName.text = "Tokyo";
                    lat.text = "35.6762";
                    lon.text = "139.6503";
                }
            }
        }
        RowLayout {
            ConsoleTextField {
                id: lat
                objectName: "observationJobLatitude"
                Layout.fillWidth: true
                text: "41.9028"
                placeholderText: "Latitude [degrees]"
                validator: DoubleValidator {
                    bottom: -90
                    top: 90
                    locale: "C"
                }
            }
            ConsoleTextField {
                id: lon
                objectName: "observationJobLongitude"
                Layout.fillWidth: true
                text: "12.4964"
                placeholderText: "Longitude [degrees]"
                validator: DoubleValidator {
                    bottom: -180
                    top: 180
                    locale: "C"
                }
            }
        }
        RowLayout {
            Text {
                text: "Priority"
                color: theme.muted
                font.pixelSize: 13
            }
            Item {
                Layout.fillWidth: true
            }
            ConsoleSpinBox {
                id: importance
                from: 0
                to: 100
                value: 80
            }
        }
        RowLayout {
            ConsoleCheckBox {
                id: repeatJob
                text: "Repeat [s]"
            }
            Item {
                Layout.fillWidth: true
            }
            ConsoleSpinBox {
                id: repeatInterval
                from: 60
                to: 604800
                value: 5400
                stepSize: 60
                enabled: repeatJob.checked
            }
        }
        RowLayout {
            ConsoleCheckBox {
                id: expireJob
                text: "Deadline [s]"
            }
            Item {
                Layout.fillWidth: true
            }
            ConsoleSpinBox {
                id: expiry
                from: 60
                to: 604800
                value: 6000
                stepSize: 60
                enabled: expireJob.checked
            }
        }
        ActionButton {
            Layout.fillWidth: true
            text: "Add observation"
            objectName: "scheduleTargetButton"
            primary: true
            enabled: root.live && lat.acceptableInput && lon.acceptableInput
            onClicked: orbit.scheduleTarget(jobName.text, Number(lat.text), Number(lon.text), importance.value, repeatJob.checked ? repeatInterval.value : 0, expireJob.checked ? expiry.value : 0)
        }
        RowLayout {
            ActionButton {
                objectName: "operationsPauseButton"
                text: orbit.status.playing ? "Pause" : "Resume"
                enabled: root.live
                onClicked: orbit.action(orbit.status.playing ? "pause" : "resume")
            }
            ActionButton {
                text: "Finish"
                enabled: root.live
                onClicked: orbit.action("finish")
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: theme.line
        }
        ConsoleComboBox {
            id: selectedJob
            Layout.fillWidth: true
            model: orbit.state.targets
            textRole: "name"
        }
        RowLayout {
            ActionButton {
                text: "Change priority"
                enabled: root.live && selectedJob.currentIndex >= 0
                onClicked: orbit.reprioritize(orbit.state.targets[selectedJob.currentIndex].id, importance.value)
            }
            ActionButton {
                text: "Remove target"
                enabled: root.live && selectedJob.currentIndex >= 0
                onClicked: orbit.retireTarget(orbit.state.targets[selectedJob.currentIndex].id)
            }
        }
        ActionButton {
            objectName: "updateTargetCoordinatesButton"
            Layout.fillWidth: true
            text: "Correct selected target coordinates"
            enabled: root.live && selectedJob.currentIndex >= 0 && lat.acceptableInput && lon.acceptableInput
            onClicked: orbit.command("OrbitLab.mission.UPDATE_TARGET", JSON.stringify([orbit.state.targets[selectedJob.currentIndex].id, Number(lat.text) * Math.PI / 180, Number(lon.text) * Math.PI / 180]), true)
        }
        ActionButton {
            Layout.fillWidth: true
            text: "View upcoming passes and orbit →"
            onClicked: window.page = 8
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: orbit.state.targets
            spacing: 6
            clip: true
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 104
                radius: 5
                color: theme.canvas
                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 5
                    Text {
                        width: parent.width
                        text: "T" + modelData.id + " · " + modelData.name
                        elide: Text.ElideRight
                        color: theme.ink
                        font.pixelSize: 14
                    }
                    Text {
                        text: "Priority " + modelData.priority + " · " + root.jobState(modelData.status)
                        color: theme.accent
                        font.pixelSize: 13
                    }
                    Text {
                        text: modelData.acquired + " images acquired / " + modelData.delivered + " delivered"
                        color: theme.muted
                        font.pixelSize: 13
                    }
                    Text {
                        width: parent.width
                        text: {
                            const window = (orbit.state.access_windows || []).find(w => w.target_id === modelData.id);
                            if (!window)
                                return "";
                            if (window.start_s < 0)
                                return "No access in the next 24 h";
                            const minutes = Math.max(0, (window.start_s - orbit.state.time_s) / 60);
                            return minutes < 1 ? "Access available now" : "Next pass in " + minutes.toFixed(0) + " simulated min";
                        }
                        color: theme.teal
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12
        GroundTrack {
            Layout.fillWidth: true
            Layout.preferredHeight: 330
            onCoordinateSelected: (latitude, longitude) => {
                lat.text = latitude.toFixed(5);
                lon.text = longitude.toFixed(5);
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Metric {
                Layout.fillWidth: true
                label: "FORECAST MINIMUM / 600 s"
                value: Number(orbit.state.forecast_min_energy_j / 3600).toFixed(1)
                unit: "Wh"
                accent: theme.teal
            }
            Metric {
                Layout.fillWidth: true
                label: "ONBOARD STORAGE"
                value: Number(orbit.state.stored_bytes / 1024).toFixed(0) + " / " + Number(orbit.state.storage_capacity_bytes / 1024).toFixed(0)
                unit: "KiB"
            }
            Metric {
                Layout.fillWidth: true
                label: "ECLIPSE / LIGHT"
                value: Number(100 * orbit.state.sunlight_fraction).toFixed(0)
                unit: "% sun"
            }
        }
        Panel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "ACQUIRED AND DELIVERED IMAGES"
            Text {
                Layout.fillWidth: true
                text: "Ground contact: " + (orbit.state.contact_start_s >= 0 ? Number(orbit.state.contact_start_s).toFixed(0) + "–" + Number(orbit.state.contact_end_s).toFixed(0) + " s" : "waiting") + " · Link " + (orbit.state.link_available ? "available" : "unavailable") + " · " + orbit.state.queue_depth + " images to downlink"
                color: theme.muted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 5
                    objectName: "productArchiveList"
                    Layout.minimumWidth: 300
                    Layout.preferredWidth: 600
                    model: orbit.state.products
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 62
                        color: theme.canvas
                        radius: 5
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 5
                                Text {
                                    text: modelData.filename + " · T" + modelData.target_id
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: theme.ink
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: "SHA-256 " + modelData.sha256.substring(0, 24) + "… · captured " + Number(modelData.capture_s).toFixed(1) + " s"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: theme.muted
                                    font.pixelSize: 12
                                }
                            }
                            Text {
                                text: modelData.sent_bytes + " / " + modelData.size + " B · " + root.productState(modelData.status)
                                color: modelData.status === "delivered" ? theme.teal : theme.accent
                                font.pixelSize: 13
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedProduct = modelData.filename
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                    ScrollBar.vertical: ScrollBar {}
                }
                ColumnLayout {
                    Layout.preferredWidth: 165
                    Layout.minimumWidth: 165
                    Layout.maximumWidth: 165
                    Layout.fillHeight: true
                    Image {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        fillMode: Image.PreserveAspectFit
                        source: {
                            const products = orbit.state.products || [];
                            const chosen = products.find(p => p.filename === root.selectedProduct) || products[0];
                            return chosen ? orbit.productUrl(chosen.preview_filename || chosen.filename) : "";
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Simulated Earth observation\nSensor view and geographic footprint"
                        color: theme.muted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
