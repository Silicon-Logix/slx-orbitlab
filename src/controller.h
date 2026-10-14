// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Qt presentation bridge to confirmed backend snapshots and operator requests.
#pragma once
#include "godot_inspector.h"
#include "telemetry_model.h"
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QSortFilterProxyModel>
#include <QTcpSocket>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class Controller final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap status READ status NOTIFY stateChanged)
    Q_PROPERTY(QVariantList events READ events NOTIFY stateChanged)
    Q_PROPERTY(QVariantList commands READ commands NOTIFY stateChanged)
    Q_PROPERTY(QVariantList channels READ channels NOTIFY stateChanged)
    Q_PROPERTY(QAbstractItemModel *telemetryModel READ telemetryModel CONSTANT)
    Q_PROPERTY(QVariantList history READ history NOTIFY stateChanged)
    Q_PROPERTY(QVariantList comparison READ comparison NOTIFY stateChanged)
    Q_PROPERTY(QVariantList runs READ runs NOTIFY runsChanged)
    Q_PROPERTY(QVariantMap preparedSequence READ preparedSequence NOTIFY sequenceChanged)
    Q_PROPERTY(QVariantList sequencePlans READ sequencePlans NOTIFY sequencePlansChanged)
    Q_PROPERTY(QVariantList catalogue READ catalogue NOTIFY catalogueChanged)
    Q_PROPERTY(QVariantMap commandResult READ commandResult NOTIFY commandResultChanged)
    Q_PROPERTY(QVariantMap campaign READ campaign NOTIFY stateChanged)
    Q_PROPERTY(QVariantList recoverable READ recoverable NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY stateChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY stateChanged)
    Q_PROPERTY(bool canControl READ canControl NOTIFY stateChanged)
    Q_PROPERTY(QString controlStatus READ controlStatus NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    Q_PROPERTY(QString logoUrl READ logoUrl CONSTANT)
    Q_PROPERTY(QVariantMap product READ product CONSTANT)
    Q_PROPERTY(QVariantList capabilities READ capabilities CONSTANT)
    Q_PROPERTY(GodotInspector *inspector READ inspector CONSTANT)
  public:
    explicit Controller(QString root, quint16 port = 8765, bool autoStartBackend = true,
                        QString distribution = "Ubuntu-22.04", QObject *parent = nullptr);
    ~Controller() override;
    QVariantMap state() const;
    QVariantMap status() const { return m_status; }
    QVariantList events() const { return m_state.value("events").toList(); }
    QVariantList commands() const { return m_state.value("commands").toList(); }
    QVariantList channels() const { return m_state.value("channels").toList(); }
    QAbstractItemModel *telemetryModel() { return &m_telemetryProxy; }
    Q_INVOKABLE void filterTelemetry(const QString &text)
    {
        m_telemetryProxy.setFilterFixedString(text);
    }
    QVariantList history() const { return m_history; }
    QVariantList comparison() const { return m_comparison; }
    QVariantList runs() const { return m_runs; }
    QVariantMap preparedSequence() const { return m_preparedSequence; }
    QVariantList sequencePlans() const { return m_sequencePlans; }
    QVariantList catalogue() const { return m_catalogue; }
    QVariantMap commandResult() const { return m_commandResult; }
    QVariantMap campaign() const { return m_campaign; }
    QVariantList recoverable() const { return m_recoverable; }
    bool connected() const { return m_connected; }
    bool stale() const;
    bool canControl() const
    {
        return m_connected && m_role == "operator" && !m_status.value("busy").toBool();
    }
    QString message() const { return m_message; }
    QString controlStatus() const;
    QString logoUrl() const;
    QVariantMap product() const;
    QVariantList capabilities() const;
    GodotInspector *inspector() { return &m_inspector; }
    Q_INVOKABLE void start(const QString &scenario, const QString &strategy, double latitude,
                           double longitude, int priority, bool rtems, bool continuous = true,
                           double repeatSeconds = 0);
    Q_INVOKABLE void action(const QString &operation);
    Q_INVOKABLE void reconnect();
    Q_INVOKABLE void setSpeed(double speed);
    Q_INVOKABLE void injectFault(double duration);
    Q_INVOKABLE void injectPhysicalFault(const QString &kind, double duration);
    Q_INVOKABLE void scheduleTarget(const QString &name, double latitude, double longitude,
                                    int priority, double repeatSeconds, double deadlineSeconds);
    Q_INVOKABLE void reprioritize(int targetId, int priority);
    Q_INVOKABLE void retireTarget(int targetId);
    Q_INVOKABLE void compareStrategies(double duration);
    Q_INVOKABLE void runCampaign(int seeds);
    Q_INVOKABLE void recoverRecording(const QString &runId);
    Q_INVOKABLE void openCampaign();
    Q_INVOKABLE QString productUrl(const QString &filename) const;
    Q_INVOKABLE void openProducts();
    Q_INVOKABLE void command(const QString &name, const QString &arguments,
                             bool resumePhysics = false);
    Q_INVOKABLE void prepareSequence(const QString &name, const QVariantList &steps);
    Q_INVOKABLE void runSequence(const QString &identifier, const QString &mode);
    Q_INVOKABLE void controlSequence(const QString &operation);
    Q_INVOKABLE void saveSequencePlan(const QString &name, const QVariantList &steps);
    Q_INVOKABLE void vehicleCommand(const QString &operation, double value = 0,
                                    double parameter = 0);
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void replay(const QString &runId);
    Q_INVOKABLE void openViewer(int scene);
    Q_INVOKABLE void openReport(const QString &runId);
    Q_INVOKABLE void saveBrief(const QVariantList &modules);
    Q_INVOKABLE QString legalText(const QString &document) const;
    QString root() const { return m_root; }
  signals:
    void stateChanged();
    void runsChanged();
    void sequenceChanged();
    void sequencePlansChanged();
    void catalogueChanged();
    void commandResultChanged();

  private:
    TelemetryModel m_telemetryModel;
    QSortFilterProxyModel m_telemetryProxy;
    QString m_root, m_message = "Connect to the local mission service", m_role, m_distribution;
    QString m_recordingWorkspace;
    quint16 m_port;
    QTcpSocket m_socket;
    QTimer m_retry;
    GodotInspector m_inspector;
    QProcess m_backend;
    QProcess m_pathResolver;
    QByteArray m_buffer;
    QVariantMap m_state, m_status;
    QVariantMap m_campaign;
    QVariantMap m_preparedSequence;
    QVariantMap m_commandResult;
    QVariantList m_sequencePlans;
    QVariantList m_recoverable;
    QVariantList m_history, m_comparison, m_runs, m_catalogue;
    bool m_connected = false;
    bool m_autoStartBackend = true, m_backendAttempted = false;
    qint64 m_lastSnapshotMs = 0;
    void request(const QString &operation, QJsonObject values = {});
    void receive();
    void updateRuns(const QVariantList &runs);
    void updateCatalogue(const QVariantList &catalogue);
    void ensureBackend();
    void startBackend(const QString &linuxRoot);
};
