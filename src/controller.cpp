// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Bounded local transport, stale-data detection, native command catalogue and evidence
/// actions.
#include "controller.h"
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QUrl>
#include <QUuid>
#include <cmath>
#ifdef Q_OS_WIN
#include <qt_windows.h>
#endif

Controller::Controller(QString root, quint16 port, bool autoStartBackend, QString distribution,
                       QObject *parent)
    : QObject(parent), m_root(std::move(root)), m_distribution(std::move(distribution)),
      m_port(port), m_inspector(m_root, port), m_autoStartBackend(autoStartBackend)
{
    m_recordingWorkspace = m_root + "/workspace";
    QFile plans(m_root + "/workspace/sequence-plans.json");
    if (plans.open(QIODevice::ReadOnly) && plans.size() < 1024 * 1024)
        m_sequencePlans = QJsonDocument::fromJson(plans.readAll())
                              .object()
                              .value("plans")
                              .toArray()
                              .toVariantList();
    m_telemetryProxy.setSourceModel(&m_telemetryModel);
    m_telemetryProxy.setFilterRole(TelemetryModel::NameRole);
    m_telemetryProxy.setFilterCaseSensitivity(Qt::CaseInsensitive);
    m_status = {
        {"playing", false},          {"busy", false},  {"speed", 60}, {"fprime_running", false},
        {"basilisk_running", false}, {"mode", "LIVE"}, {"error", ""}};
    connect(&m_socket, &QTcpSocket::connected, this,
            [this]
            {
                m_connected = true;
                m_status.insert("backend_starting", false);
                m_buffer.clear();
                m_message = "Connected · awaiting confirmed backend state";
                request("hello", {{"role", "operator"}});
                emit stateChanged();
            });
    connect(&m_socket, &QTcpSocket::disconnected, this,
            [this]
            {
                m_connected = false;
                m_role.clear();
                m_message = "Mission service disconnected · telemetry retained as stale";
                emit stateChanged();
            });
    connect(&m_socket, &QTcpSocket::readyRead, this, &Controller::receive);
    connect(&m_socket, &QTcpSocket::errorOccurred, this,
            [this]
            {
                m_message = "Mission service unavailable. Click Reconnect service.";
                if (m_socket.error() == QAbstractSocket::ConnectionRefusedError)
                    ensureBackend();
                emit stateChanged();
            });
    connect(
        &m_backend, &QProcess::errorOccurred, this,
        [this]
        {
            qWarning().noquote() << "Backend startup:" << m_backend.errorString();
            m_message =
                "Unable to start the mission service. Check WSL setup and click Reconnect service.";
            m_status.insert("backend_starting", false);
            emit stateChanged();
        });
    connect(&m_backend, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus)
            {
                if (code != 0)
                {
                    qWarning() << "Backend exit code:" << code;
                    m_message = "The mission service stopped. Click Reconnect service.";
                    m_status.insert("backend_starting", false);
                    emit stateChanged();
                }
            });
    connect(
        &m_pathResolver, &QProcess::finished, this,
        [this](int code, QProcess::ExitStatus)
        {
            const auto linuxRoot =
                QString::fromUtf8(m_pathResolver.readAllStandardOutput()).trimmed();
            if (code == 0 && linuxRoot.startsWith('/'))
                startBackend(linuxRoot);
            else
            {
                qWarning().noquote()
                    << "Linux checkout resolution:"
                    << QString::fromUtf8(m_pathResolver.readAllStandardError()).trimmed();
                m_message =
                    "Unable to locate the project in WSL. Check the installation and reconnect.";
                m_status.insert("backend_starting", false);
                emit stateChanged();
            }
        });
    connect(&m_retry, &QTimer::timeout, this,
            [this]
            {
                if (m_socket.state() == QAbstractSocket::UnconnectedState)
                    m_socket.connectToHost("127.0.0.1", m_port);
                emit stateChanged();
            });
    m_retry.start(1500);
    m_socket.connectToHost("127.0.0.1", m_port);
}

Controller::~Controller()
{
    m_retry.stop();
    // Process completion callbacks must not access destroyed state containers.
    disconnect(&m_socket, nullptr, this, nullptr);
    disconnect(&m_pathResolver, nullptr, this, nullptr);
    disconnect(&m_backend, nullptr, this, nullptr);
    const auto stopProcess = [](QProcess &process)
    {
        if (process.state() == QProcess::NotRunning)
            return;
        process.terminate();
        if (!process.waitForFinished(1000))
        {
            process.kill();
            process.waitForFinished(1000);
        }
    };
    stopProcess(m_pathResolver);
    if (m_backendAttempted && m_backend.state() != QProcess::NotRunning && m_role == "operator")
    {
        request("shutdown");
        m_socket.waitForBytesWritten(1000);
        m_backend.waitForFinished(4000);
    }
    stopProcess(m_backend);
    m_socket.disconnectFromHost();
}

void Controller::ensureBackend()
{
    if (!m_autoStartBackend || m_backendAttempted)
        return;
    m_backendAttempted = true;
    QDir().mkpath(m_root + "/workspace");
    m_backend.setStandardOutputFile(m_root + "/workspace/desktop-service.log");
    m_backend.setStandardErrorFile(m_root + "/workspace/desktop-service-errors.log",
                                   QIODevice::Truncate);
#ifdef Q_OS_WIN
    // Resolve Windows paths independently; no nested shell quoting is needed to launch WSL.
    m_pathResolver.setProgram("wsl.exe");
    m_pathResolver.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments)
                                                     { arguments->flags |= CREATE_NO_WINDOW; });
    m_pathResolver.setArguments(
        {"-d", m_distribution, "--", "wslpath", "-a", "-u", QDir::fromNativeSeparators(m_root)});
    m_pathResolver.start();
#else
    startBackend(m_root);
#endif
    m_message = "Starting the Linux mission service...";
    m_status.insert("backend_starting", true);
}

void Controller::startBackend(const QString &linuxRoot)
{
#ifdef Q_OS_WIN
    m_backend.setProgram("wsl.exe");
    m_backend.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments)
                                                { arguments->flags |= CREATE_NO_WINDOW; });
    m_backend.setArguments({"-d", m_distribution, "--", "bash",
                            linuxRoot + "/scripts/start-backend.sh", "--port",
                            QString::number(m_port)});
#else
    m_backend.setProgram("bash");
    m_backend.setArguments(
        {linuxRoot + "/scripts/start-backend.sh", "--port", QString::number(m_port)});
#endif
    m_backend.start();
}

bool Controller::stale() const
{
    return !m_connected || !m_lastSnapshotMs ||
           QDateTime::currentMSecsSinceEpoch() - m_lastSnapshotMs > 3000;
}
QString Controller::controlStatus() const
{
    if (!m_connected)
        return m_status.value("backend_starting").toBool()
                   ? "Preparing the mission service..."
                   : "Service disconnected. Click Reconnect service.";
    if (m_role.isEmpty())
        return "Connecting operator...";
    if (m_role != "operator")
        return "Another window controls the mission. Close it and click Reconnect service.";
    if (m_status.value("busy").toBool())
        return "Verification running. Wait for the campaign to complete.";
    return "Ready to start the mission";
}
void Controller::reconnect()
{
    if (m_connected)
    {
        request("hello", {{"role", "operator"}});
        return;
    }
    if (m_backend.state() == QProcess::NotRunning && m_pathResolver.state() == QProcess::NotRunning)
        m_backendAttempted = false;
    m_socket.abort();
    m_socket.connectToHost("127.0.0.1", m_port);
}

QVariantMap Controller::state() const
{
    QVariantMap result{
        {"time_s", 0.0},
        {"duration_s", 1600.0},
        {"phase", "No mission loaded"},
        {"soc_percent", 0.0},
        {"energy_j", 0.0},
        {"generation_w", 0.0},
        {"consumed_w", 0.0},
        {"truth_pointing_error_deg", 0.0},
        {"completed", 0},
        {"deferred", 0},
        {"attitude_valid", false},
        {"run_id", "—"},
        {"scenario_name", "Select a scenario and load the mission"},
        {"strategy", "energy-aware"},
        {"reason", "NO_MISSION_LOADED"},
        {"stored_bytes", 0},
        {"delivered_bytes", 0},
        {"window_start_s", -1},
        {"window_end_s", -1},
        {"required_energy_j", 0},
        {"target_id", 0},
        {"phase_id", 0},
        {"acquired", 0},
        {"expired", 0},
        {"queue_depth", 0},
        {"continuous", false},
        {"safety_active", 0},
        {"storage_capacity_bytes", 2097152},
        {"forecast_min_energy_j", 0},
        {"forecast_horizon_s", 600},
        {"contact_start_s", -1},
        {"contact_end_s", -1},
        {"next_eclipse_s", -1},
        {"sunlight_fraction", 0},
        {"actuator_valid", false},
        {"link_available", false},
        {"attitude_estimation_error_deg", 0},
        {"downlink_target_id", 0},
        {"targets", QVariantList{}},
        {"products", QVariantList{}},
        {"runtime",
         QVariantMap{
             {"native_packets", 0}, {"native_bytes", 0}, {"fprime_step_ms", 0}, {"step_s", 0.5}}},
        {"recording",
         QVariantMap{{"segments", 0}, {"disk_bytes", 0}, {"quota_bytes", 0}, {"checkpoint_s", 0}}},
        {"visual", QVariantMap{}},
        {"eps", QVariantMap{{"mode", "Host reference"}, {"flags", 0}, {"heartbeat", 0}}}};
    for (auto it = m_state.cbegin(); it != m_state.cend(); ++it)
        result.insert(it.key(), it.value());
    return result;
}

void Controller::request(const QString &operation, QJsonObject values)
{
    if (!m_connected)
    {
        m_message = "The mission service is not connected";
        emit stateChanged();
        return;
    }
    values.insert("op", operation);
    values.insert("request_id", QUuid::createUuid().toString(QUuid::WithoutBraces));
    m_socket.write(QJsonDocument(values).toJson(QJsonDocument::Compact) + '\n');
}

void Controller::receive()
{
    m_buffer += m_socket.readAll();
    if (m_buffer.size() > 1024 * 1024)
    {
        m_socket.abort();
        m_message = "Backend message exceeded the transport limit";
        emit stateChanged();
        return;
    }
    qsizetype index;
    while ((index = m_buffer.indexOf('\n')) >= 0)
    {
        const auto line = m_buffer.left(index);
        m_buffer.remove(0, index + 1);
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject())
        {
            m_message = "Invalid backend message";
            continue;
        }
        const auto object = document.object();
        if (object.value("type") == "snapshot")
        {
            m_state = object.value("snapshot").toObject().toVariantMap();
            m_telemetryModel.updateChannels(channels(), m_state.value("run_id").toString());
            m_status = object.value("status").toObject().toVariantMap();
            m_history = object.value("history").toArray().toVariantList();
            m_comparison = object.value("comparison").toArray().toVariantList();
            m_campaign = object.value("campaign").toObject().toVariantMap();
            m_lastSnapshotMs = QDateTime::currentMSecsSinceEpoch();
            if (!m_status.value("error").toString().isEmpty())
                m_message = m_status.value("error").toString();
        }
        else if (object.value("type") == "reply")
        {
            if (!object.value("ok").toBool())
            {
                m_message = "Request rejected: " + object.value("error").toString();
                if (object.value("op").toString() == "command")
                {
                    m_commandResult.insert("status", "error");
                    m_commandResult.insert("message", object.value("error").toString());
                    emit commandResultChanged();
                }
            }
            else
            {
                const auto operation = object.value("op").toString();
                const auto data = object.value("data");
                if (operation == "hello")
                {
                    auto workspace = data.toObject().value("workspace").toString();
#ifdef Q_OS_WIN
                    if (workspace.startsWith("/mnt/c/"))
                        workspace = "C:/" + workspace.mid(7);
#endif
                    if (!workspace.isEmpty())
                        m_recordingWorkspace = workspace;
                    m_role = data.toObject().value("role").toString();
                    updateRuns(data.toObject().value("runs").toArray().toVariantList());
                    updateCatalogue(data.toObject().value("catalogue").toArray().toVariantList());
                    m_recoverable = data.toObject().value("recoverable").toArray().toVariantList();
                    m_message = m_role == "operator"
                                    ? "Ready to start the mission"
                                    : "Observation session · Another window has control";
                }
                if (operation == "start")
                {
                    m_commandResult.clear();
                    emit commandResultChanged();
                    m_preparedSequence.clear();
                    emit sequenceChanged();
                    updateCatalogue(data.toObject().value("catalogue").toArray().toVariantList());
                    m_message = "Mission started";
                }
                if (operation == "runs")
                    updateRuns(data.toArray().toVariantList());
                if (operation == "finish")
                    updateRuns(data.toObject().value("runs").toArray().toVariantList());
                if (operation == "replay")
                {
                    m_commandResult.clear();
                    emit commandResultChanged();
                }
                if (operation == "recordings")
                    m_recoverable = data.toArray().toVariantList();
                if (operation == "recover")
                {
                    updateRuns(data.toObject().value("runs").toArray().toVariantList());
                    m_message = "Committed recording recovered; spacecraft state was not restarted";
                    request("recordings");
                }
                if (operation == "schedule_target")
                    m_message = "New target accepted by F Prime · follow it on the Mission page";
                if (operation == "command")
                {
                    m_commandResult = data.toObject().toVariantMap();
                    m_commandResult.insert("run_id", m_state.value("run_id"));
                    emit commandResultChanged();
                    m_message = data.toObject().value("name").toString() + " · " +
                                data.toObject().value("status").toString();
                }
                if (operation == "prepare_sequence")
                {
                    m_preparedSequence = data.toObject().toVariantMap();
                    emit sequenceChanged();
                    m_message = "Sequence compiled and validated by F Prime";
                }
                if (operation == "run_sequence")
                    m_message = "Sequence loaded into the F Prime sequencer";
                if (operation == "control_sequence")
                    m_message = "Command to the F Prime sequencer confirmed";
                if (operation == "export")
                {
                    auto path = data.toObject().value("path").toString();
#ifdef Q_OS_WIN
                    if (path.startsWith("/mnt/c/"))
                        path = "C:/" + path.mid(7);
#endif
                    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
                    updateRuns(data.toObject().value("runs").toArray().toVariantList());
                    m_message = "Engineering report exported";
                }
            }
        }
    }
    emit stateChanged();
}

void Controller::updateRuns(const QVariantList &runs)
{
    if (m_runs == runs)
        return;
    m_runs = runs;
    emit runsChanged();
}

void Controller::updateCatalogue(const QVariantList &catalogue)
{
    if (m_catalogue == catalogue)
        return;
    m_catalogue = catalogue;
    emit catalogueChanged();
}

void Controller::start(const QString &scenario, const QString &strategy, double latitude,
                       double longitude, int priority, bool rtems, bool continuous,
                       double repeatSeconds)
{
    if (!std::isfinite(latitude) || !std::isfinite(longitude))
        return;
    QJsonObject target{
        {"id", 1},
        {"name",
         std::abs(latitude - 41.9028) < 0.00001 && std::abs(longitude - 12.4964) < 0.00001 ? "Rome"
         : std::abs(latitude - 40.7128) < 0.00001 && std::abs(longitude + 74.0060) < 0.00001
             ? "New York"
         : std::abs(latitude - 48.8566) < 0.00001 && std::abs(longitude - 2.3522) < 0.00001
             ? "Paris"
         : std::abs(latitude - 35.6762) < 0.00001 && std::abs(longitude - 139.6503) < 0.00001
             ? "Tokyo"
             : "Selected target"},
        {"latitude_deg", latitude},
        {"longitude_deg", longitude},
        {"priority", priority},
        {"repeat_s", repeatSeconds}};
    request("start", {{"scenario", scenario},
                      {"strategy", strategy},
                      {"target", target},
                      {"rtems", rtems},
                      {"continuous", continuous}});
}
void Controller::action(const QString &operation)
{
    request(operation);
}
void Controller::setSpeed(double speed)
{
    request("speed", {{"value", speed}});
}
void Controller::injectFault(double duration)
{
    request("fault", {{"duration_s", duration}});
}
void Controller::injectPhysicalFault(const QString &kind, double duration)
{
    request("fault", {{"kind", kind}, {"duration_s", duration}});
}
void Controller::scheduleTarget(const QString &name, double latitude, double longitude,
                                int priority, double repeatSeconds, double deadlineSeconds)
{
    request("schedule_target",
            {{"target",
              QJsonObject{{"name", name},
                          {"latitude_deg", latitude},
                          {"longitude_deg", longitude},
                          {"priority", priority},
                          {"repeat_s", repeatSeconds},
                          {"deadline_s", deadlineSeconds > 0
                                             ? state().value("time_s").toDouble() + deadlineSeconds
                                             : 0}}}});
}
void Controller::reprioritize(int targetId, int priority)
{
    request("command",
            {{"name", "OrbitLab.mission.SET_PRIORITY"}, {"args", QJsonArray{targetId, priority}}});
}
void Controller::retireTarget(int targetId)
{
    request("command",
            {{"name", "OrbitLab.mission.REMOVE_TARGET"}, {"args", QJsonArray{targetId}}});
}
void Controller::compareStrategies(double duration)
{
    request("compare", {{"duration_s", duration}});
}
void Controller::runCampaign(int seeds)
{
    request("campaign", {{"seed_count", seeds}});
}
void Controller::recoverRecording(const QString &runId)
{
    request("recover", {{"run_id", runId}});
}
void Controller::openCampaign()
{
    const auto identifier = m_campaign.value("campaign_id").toString();
    if (identifier.size() != 12)
        return;
    QDesktopServices::openUrl(
        QUrl::fromLocalFile(m_recordingWorkspace + "/campaigns/" + identifier + "/campaign.html"));
}
QString Controller::productUrl(const QString &filename) const
{
    if (filename.isEmpty() || QDir::cleanPath(filename) != filename || filename.contains('/') ||
        filename.contains('\\') || !filename.startsWith("observation-") ||
        (!filename.endsWith(".pgm") && !filename.endsWith(".png")))
        return {};
    const auto path = m_recordingWorkspace + "/runs/" + state().value("run_id").toString() +
                      "/products/" + filename;
    return QFile::exists(path) ? QUrl::fromLocalFile(path).toString() : QString{};
}
void Controller::openProducts()
{
    const auto identifier = state().value("run_id").toString();
    if (identifier.size() != 12 || identifier.contains('/') || identifier.contains('\\'))
        return;
    const auto folder = m_recordingWorkspace + "/runs/" + identifier +
                        (state().value("completed").toInt() > 0 ? "/ground" : "/products");
    if (QDir(folder).exists())
        QDesktopServices::openUrl(QUrl::fromLocalFile(folder));
}
void Controller::seek(double seconds)
{
    request("seek", {{"time_s", seconds}});
}
void Controller::replay(const QString &runId)
{
    request("replay", {{"run_id", runId}});
}
void Controller::command(const QString &name, const QString &arguments, bool resumePhysics)
{
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(arguments.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isArray())
    {
        m_message = "Enter parameters as a JSON array, or click Use example";
        m_commandResult = {{"name", name},
                           {"status", "error"},
                           {"message", m_message},
                           {"run_id", m_state.value("run_id")}};
        emit commandResultChanged();
        emit stateChanged();
        return;
    }
    m_commandResult = {{"name", name},
                       {"args", document.array().toVariantList()},
                       {"status", "sending"},
                       {"run_id", m_state.value("run_id")}};
    emit commandResultChanged();
    request("command", {{"name", name}, {"args", document.array()}});
    if (resumePhysics && name.startsWith("OrbitLab.mission.") &&
        !m_status.value("playing").toBool())
        request("resume");
}

void Controller::prepareSequence(const QString &name, const QVariantList &steps)
{
    m_preparedSequence.clear();
    emit sequenceChanged();
    request("prepare_sequence", {{"name", name}, {"steps", QJsonArray::fromVariantList(steps)}});
}
void Controller::runSequence(const QString &identifier, const QString &mode)
{
    request("run_sequence", {{"id", identifier}, {"mode", mode}});
}
void Controller::controlSequence(const QString &operation)
{
    request("control_sequence", {{"action", operation}});
}
void Controller::saveSequencePlan(const QString &name, const QVariantList &steps)
{
    if (name.trimmed().isEmpty() || name.size() > 64 || steps.isEmpty() || steps.size() > 64)
    {
        m_message = "Name the plan and add 1 to 64 steps";
        emit stateChanged();
        return;
    }
    QVariantList plans;
    plans.append(QVariantMap{{"name", name.trimmed()}, {"steps", steps}});
    for (const auto &plan : m_sequencePlans)
        if (plan.toMap().value("name").toString() != name.trimmed() && plans.size() < 32)
            plans.append(plan);
    QDir().mkpath(m_root + "/workspace");
    QSaveFile file(m_root + "/workspace/sequence-plans.json");
    const auto json = QJsonDocument(QJsonObject{{"schema", "slx.orbitlab.sequence-plans/1"},
                                                {"plans", QJsonArray::fromVariantList(plans)}})
                          .toJson();
    if (!file.open(QIODevice::WriteOnly) || file.write(json) != json.size() || !file.commit())
        m_message = "Unable to save the command plan";
    else
    {
        m_sequencePlans = plans;
        emit sequencePlansChanged();
        m_message = "Plan saved · it will be validated against the dictionary before execution";
    }
    emit stateChanged();
}

void Controller::vehicleCommand(const QString &operation, double value, double parameter)
{
    if (!canControl() || m_status.value("mode") != "LIVE" ||
        !m_status.value("fprime_running").toBool())
        return;
    QString name;
    QJsonArray args;
    if (operation == "panels")
    {
        name = "DEPLOY";
        args = {static_cast<int>(value)};
    }
    else if (operation == "maneuver")
    {
        name = "MANEUVER";
        args = {static_cast<int>(value), parameter};
    }
    else if (operation == "payload")
    {
        name = "SET_PAYLOAD";
        args = {static_cast<int>(value)};
    }
    else if (operation == "downlink")
    {
        name = "SET_DOWNLINK";
        args = {static_cast<int>(value)};
    }
    else if (operation == "beacon")
    {
        name = "SET_BEACON";
        args = {static_cast<int>(value), parameter};
    }
    else
        return;
    request("command", {{"name", "OrbitLab.mission." + name}, {"args", args}});
    if (!m_status.value("playing").toBool())
        request("resume");
}
QString Controller::logoUrl() const
{
    return "qrc:/brand/Silicon_LogiX_logo_cropped.png";
}
QVariantMap Controller::product() const
{
    return {{"version", SLX_APP_VERSION},
            {"author", "Marco Pezzullo · Silicon LogiX"},
            {"qtVersion", qVersion()},
            {"coreAbi", 2},
            {"sceneVersion", "0.1.0"},
            {"website", "https://www.siliconlogix.it/"},
            {"contact", "https://www.siliconlogix.it/contatti"},
            {"license", "Silicon LogiX Evaluation License 1.0"}};
}
QString Controller::legalText(const QString &document) const
{
    const QMap<QString, QString> resources{
        {"license", ":/legal/license"}, {"notices", ":/legal/notices"}, {"qt", ":/legal/qt"}};
    QFile file(resources.value(document));
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll())
                                          : "Document unavailable";
}
QVariantList Controller::capabilities() const
{
    QFile file(":/engineering/capabilities.json");
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll())
        .object()
        .value("modules")
        .toArray()
        .toVariantList();
}
void Controller::openViewer(int scene)
{
    m_inspector.open(scene);
}
void Controller::openReport(const QString &runId)
{
    if (runId.size() != 12 || runId.contains('/') || runId.contains('\\'))
        return;
    QDesktopServices::openUrl(
        QUrl::fromLocalFile(m_recordingWorkspace + "/runs/" + runId + "/report.html"));
}
void Controller::saveBrief(const QVariantList &modules)
{
    QDir().mkpath(m_root + "/workspace/briefs");
    const auto path = m_root + "/workspace/briefs/orbitlab-engineering-" +
                      QDateTime::currentDateTimeUtc().toString("yyyyMMdd-hhmmss") + ".json";
    QSaveFile file(path);
    const QJsonObject brief{{"schema", "slx.orbitlab.project-brief/1"},
                            {"product", "SLX OrbitLab"},
                            {"status", "project-request"},
                            {"modules", QJsonArray::fromVariantList(modules)}};
    const auto bytes = QJsonDocument(brief).toJson();
    if (file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit())
        m_message = "Local engineering brief saved: " + path;
    else
        m_message = "Could not save the engineering brief";
    emit stateChanged();
}
