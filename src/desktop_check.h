// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Verify a mission through the actual QML controls and confirmed backend telemetry.
#pragma once
#include <QElapsedTimer>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
class Controller;
class QQuickWindow;
class QQuickItem;
class DesktopCheck final : public QObject
{
  public:
    DesktopCheck(Controller &controller, QQuickWindow &window, QString report,
                 const QStringList &diagnostics, QString screenshot = {}, bool operations = false,
                 bool console = false, bool sequences = false, bool orbits = false);

  private:
    Controller &m_controller;
    QQuickWindow &m_window;
    QString m_report, m_previousRun, m_screenshot;
    const QStringList &m_diagnostics;
    QElapsedTimer m_elapsed;
    QTimer m_timer;
    QVariantList m_firstAttitude;
    int m_stage = 0;
    bool m_attitudeChanged = false;
    bool m_frameReady = false;
    bool m_startGuideVerified = false;
    bool m_resultPreview = false;
    bool m_enlargedPreview = false;
    bool m_operations = false;
    bool m_console = false;
    bool m_sequences = false, m_sequenceVerified = false, m_recordingsVerified = false;
    bool m_orbits = false, m_orbitVerified = false, m_orbitThrustObserved = false;
    bool m_propulsion3D = false;
    double m_orbitInitialAxis = 0, m_orbitInitialFuel = 0;
    double m_replayTargetTime = 0;
    bool m_jobLabelVerified = false, m_examplesVerified = false, m_beaconCaptionStable = false;
    QString m_beaconCaption;
    double m_recordingScroll = 0;
    int m_noOpIndex = -1, m_previousCommandSequence = 0, m_inspected = 0;
    bool m_nativeNames = false, m_nativeAck = false, m_hidden = false, m_resized = false;
    bool m_liveViewer = false, m_helpVisibility = false;
    bool m_scrollPreserved = false, m_vehicleComplete = false, m_componentVerified = false;
    bool m_beaconOn = false, m_beaconOff = false, m_maneuverVerified = false;
    double m_telemetryScroll = 0, m_beaconStart = 0;
    QVariantList m_maneuverStart;
    double m_viewerStartTime = 0;
    qint64 m_captureAfterMs = 0;
    QVariantList m_viewerFrames;
    void pollConsole();
    void pollSequences();
    void pollOrbits();
    void poll();
    bool click(QQuickItem *item);
    QQuickItem *findItem(QQuickItem *root, const QString &name);
    void finish(const QString &error = {});
};
