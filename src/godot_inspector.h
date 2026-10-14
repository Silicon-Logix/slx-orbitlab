// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Own a visible read-only Godot process and its native Qt window container.
#pragma once
#include <QElapsedTimer>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QUdpSocket>
#include <QVariantMap>
#include <QWindow>
#include <memory>

class GodotInspector final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QWindow *window READ window CONSTANT)
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool embedded READ embedded CONSTANT)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QVariantMap frame READ frame NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)
    Q_PROPERTY(QString selectedComponent READ selectedComponent NOTIFY changed)
  public:
    GodotInspector(QString root, quint16 port, QObject *parent = nullptr);
    ~GodotInspector() override;
    QWindow *window() const { return m_window.get(); }
    bool running() const { return m_process.state() != QProcess::NotRunning; }
    bool ready() const;
    bool embedded() const;
    QString message() const { return m_message; }
    QVariantMap frame() const { return m_frame; }
    bool available() const;
    bool installing() const { return m_installer.state() != QProcess::NotRunning; }
    Q_INVOKABLE void install();
    Q_INVOKABLE void open(int scene);
    Q_INVOKABLE void close();
    QString selectedComponent() const { return m_selectedComponent; }
    Q_INVOKABLE void selectComponent(const QString &component);
    Q_INVOKABLE void focusComponent();
    Q_INVOKABLE void isolateComponent(bool isolate);
    Q_INVOKABLE void resetCamera();
    void probeSelection() { presentation("pick"); }
    bool nativeVisible() const;
    bool nativeSizeMatches() const;
  signals:
    void changed();

  private:
    QString m_root, m_message = "Open a view: the 3D model follows confirmed telemetry.";
    quint16 m_port;
    std::unique_ptr<QWindow> m_window;
    QProcess m_process;
    QProcess m_installer;
    QTimer m_poll;
    QUdpSocket m_presentationSocket;
    quint16 m_presentationPort = 0;
    QString m_selectedComponent = "Optical_Payload";
    QString m_pendingComponent;
    void presentation(const QString &operation, QJsonObject values = {});
    QElapsedTimer m_started;
    QByteArray m_buffer;
    QVariantMap m_frame;
    quintptr m_child = 0;
    void *m_job = nullptr;
    int m_scene = -1;
    bool m_failed = false;
    bool m_closing = false;
    void updateWindow();
    void readOutput();
    void log(const QByteArray &data);
    QString enginePath() const;
};
