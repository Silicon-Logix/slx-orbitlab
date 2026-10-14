// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

// Plot received time-series samples; gaps and mission time remain explicit.
import QtQuick

Rectangle {
    id: chart
    property string title: ""
    property string field: "soc_percent"
    property real maximum: 100
    property color lineColor: "#4c4ed7"
    color: "white"
    radius: 8
    border.color: "#e3e8f0"
    Text {
        x: 16
        y: 12
        text: chart.title
        color: "#56647a"
        font.pixelSize: 13
        font.letterSpacing: 0.5
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 12
        text: "0–" + chart.maximum + (chart.maximum === 10 ? " · clipped" : "")
        color: "#56647a"
        font.pixelSize: 13
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 36
        anchors.bottomMargin: 27
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = "#e3e8f0";
            ctx.lineWidth = 1;
            for (let i = 0; i < 4; ++i) {
                ctx.beginPath();
                ctx.moveTo(0, height * i / 3);
                ctx.lineTo(width, height * i / 3);
                ctx.stroke();
            }
            const samples = orbit.history;
            if (samples.length < 2)
                return;
            const start = samples[0].time_s;
            const span = Math.max(1, samples[samples.length - 1].time_s - start);
            ctx.strokeStyle = chart.lineColor;
            ctx.lineWidth = 2;
            ctx.beginPath();
            let started = false;
            for (let j = 0; j < samples.length; ++j) {
                const value = samples[j][chart.field];
                if (value === null || value === undefined || !isFinite(value)) {
                    started = false;
                    continue;
                }
                const x = (samples[j].time_s - start) / span * width;
                const y = height * (1 - Math.min(chart.maximum, Math.max(0, value)) / chart.maximum);
                if (!started)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
                started = true;
            }
            ctx.stroke();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9
        text: "Simulation time [s]"
        color: "#56647a"
        font.pixelSize: 13
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9
        text: orbit.history.length > 0 ? Number(orbit.history[0].time_s).toFixed(1) + " – " + Number(orbit.history[orbit.history.length - 1].time_s).toFixed(1) + " s" : "No samples"
        color: "#56647a"
        font.pixelSize: 13
    }
    Connections {
        target: orbit
        function onStateChanged() {
            canvas.requestPaint();
        }
    }
}
