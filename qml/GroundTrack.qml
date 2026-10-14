// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Earth-fixed engineering map; display coordinates never enter flight decisions.
import QtQuick

Rectangle {
    id: root
    property var snapshot: orbit.state
    property var history: orbit.history
    signal coordinateSelected(real latitude, real longitude)
    color: "#111c31"
    radius: 8
    clip: true
    onSnapshotChanged: if (visible)
        chart.requestPaint()
    onHistoryChanged: if (visible)
        chart.requestPaint()
    onVisibleChanged: if (visible)
        chart.requestPaint()
    Image {
        anchors.fill: parent
        source: "qrc:/earth/surface.png"
        fillMode: Image.Stretch
        opacity: 0.48
    }
    Canvas {
        id: chart
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.strokeStyle = "#516078";
            c.lineWidth = 0.6;
            for (let lon = -180; lon <= 180; lon += 30) {
                const x = (lon + 180) / 360 * width;
                c.beginPath();
                c.moveTo(x, 0);
                c.lineTo(x, height);
                c.stroke();
            }
            for (let lat = -60; lat <= 60; lat += 30) {
                const y = (90 - lat) / 180 * height;
                c.beginPath();
                c.moveTo(0, y);
                c.lineTo(width, y);
                c.stroke();
            }
            c.strokeStyle = "#66dec6";
            c.lineWidth = 2;
            let previous = null;
            for (let i = 0; i < root.history.length; ++i) {
                const point = root.history[i];
                if (point.latitude_deg === undefined || point.longitude_deg === undefined)
                    continue;
                const x = (point.longitude_deg + 180) / 360 * width;
                const y = (90 - point.latitude_deg) / 180 * height;
                if (previous && Math.abs(x - previous.x) < width / 2) {
                    c.beginPath();
                    c.moveTo(previous.x, previous.y);
                    c.lineTo(x, y);
                    c.stroke();
                }
                previous = {
                    x: x,
                    y: y
                };
            }
            let labels = [];
            function marker(lat, lon, color, label, size) {
                const x = (lon + 180) / 360 * chart.width;
                const y = (90 - lat) / 180 * chart.height;
                c.fillStyle = color;
                c.beginPath();
                c.arc(x, y, size, 0, 2 * Math.PI);
                c.fill();
                for (let j = 0; j < labels.length; ++j)
                    if (Math.abs(labels[j].x - x) < 65 && Math.abs(labels[j].y - y) < 18)
                        return;
                labels.push({
                    x: x,
                    y: y
                });
                c.fillStyle = "white";
                c.font = "12px Arial";
                c.fillText(label, Math.min(chart.width - 100, x + 8), Math.max(15, y - 7));
            }
            const station = root.snapshot.ground_station;
            if (station)
                marker(station.latitude_deg, station.longitude_deg, "#a6b8ff", "Ground", 4);
            const targets = root.snapshot.targets || [];
            for (let i = 0; i < targets.length; ++i)
                marker(targets[i].latitude_deg, targets[i].longitude_deg, "#ffc66d", "T" + targets[i].id, 3);
            const visual = root.snapshot.visual || {};
            if (visual.latitude_deg !== undefined)
                marker(visual.latitude_deg, visual.longitude_deg, "#66dec6", "Spacecraft", 5);
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onClicked: mouse => root.coordinateSelected(90 - mouse.y / height * 180, mouse.x / width * 360 - 180)
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 10
        width: legend.implicitWidth + 20
        height: 32
        radius: 4
        color: "#de111c31"
        Text {
            id: legend
            anchors.centerIn: parent
            text: "ECEF · teal: spacecraft · orange: targets · violet: ground · click to select"
            color: "white"
            font.pixelSize: 12
        }
    }
}
