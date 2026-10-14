// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Embed Godot 4.5 using --wid; report process errors and actual applied viewer frames.
#include "godot_inspector.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkDatagram>
#ifdef Q_OS_WIN
#include <qt_windows.h>
namespace
{
struct ChildSearch
{
    DWORD process;
    HWND result = nullptr;
};
BOOL CALLBACK findGodotChild(HWND child, LPARAM parameter)
{
    auto &search = *reinterpret_cast<ChildSearch *>(parameter);
    DWORD process = 0;
    GetWindowThreadProcessId(child, &process);
    wchar_t windowClass[64]{};
    GetClassName(child, windowClass, 64);
    if (process == search.process && QString::fromWCharArray(windowClass) == "Engine")
    {
        search.result = child;
        return FALSE;
    }
    return TRUE;
}
} // namespace
#endif

GodotInspector::GodotInspector(QString root, quint16 port, QObject *parent)
    : QObject(parent), m_root(std::move(root)), m_port(port), m_window(std::make_unique<QWindow>())
{
    m_window->setFlags(Qt::FramelessWindowHint);
    m_presentationSocket.bind(QHostAddress::LocalHost, 0);
    connect(&m_presentationSocket, &QUdpSocket::readyRead, this,
            [this]
            {
                while (m_presentationSocket.hasPendingDatagrams())
                {
                    const auto packet = m_presentationSocket.receiveDatagram(2048);
                    if (!packet.senderAddress().isLoopback() ||
                        packet.senderPort() != m_presentationPort)
                        continue;
                    const auto value = QJsonDocument::fromJson(packet.data()).object();
                    if (value.value("component").isString())
                    {
                        m_selectedComponent = value.value("component").toString();
                        emit changed();
                    }
                }
            });
#ifdef Q_OS_WIN
    m_job = CreateJobObject(nullptr, nullptr);
    if (m_job)
    {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(static_cast<HANDLE>(m_job), JobObjectExtendedLimitInformation,
                                &limits, sizeof(limits));
    }
    connect(&m_process, &QProcess::started, this,
            [this]
            {
                const auto process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE,
                                                 static_cast<DWORD>(m_process.processId()));
                if (process)
                {
                    if (m_job && !AssignProcessToJobObject(static_cast<HANDLE>(m_job), process))
                        log("Viewer process job assignment unavailable; normal process cleanup "
                            "remains active.\n");
                    CloseHandle(process);
                }
            });
#endif
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &GodotInspector::readOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this,
            [this]
            {
                const auto error = m_process.readAllStandardError();
                log(error);
                if (error.contains("SCRIPT ERROR:") || error.contains("ERROR:"))
                {
                    m_failed = true;
                    m_message = "The 3D view encountered a problem. Click Reopen 3D view.";
                    emit changed();
                }
            });
    connect(&m_process, &QProcess::errorOccurred, this,
            [this]
            {
                if (m_closing)
                    return;
                m_failed = true;
                m_message = "Unable to start the 3D view. Click Repair 3D and try again.";
                log(m_message.toUtf8() + '\n');
                emit changed();
            });
    connect(&m_process, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus status)
            {
                m_poll.stop();
                m_child = 0;
                if (m_closing)
                {
                    m_message = "3D view closed. You can reopen it.";
                    emit changed();
                    return;
                }
                if (!m_failed)
                    m_message = code == 0 && status == QProcess::NormalExit
                                    ? "3D view closed. You can reopen it."
                                    : "The 3D view closed. You can reopen it.";
                emit changed();
            });
    connect(&m_poll, &QTimer::timeout, this, &GodotInspector::updateWindow);
    m_poll.setInterval(200);
    connect(&m_installer, &QProcess::finished, this,
            [this](int code, QProcess::ExitStatus)
            {
                m_message = code == 0 && available()
                                ? "3D component ready."
                                : "3D repair failed. Check the network connection and try again.";
                emit changed();
                if (code == 0 && available())
                    open(m_scene < 0 ? 3 : m_scene);
            });
    connect(&m_installer, &QProcess::errorOccurred, this,
            [this]
            {
                log("3D installer: " + m_installer.errorString().toUtf8() + '\n');
                m_message = "Unable to start 3D repair. Check the installation and try again.";
                emit changed();
            });
}
GodotInspector::~GodotInspector()
{
    disconnect(&m_process, nullptr, this, nullptr);
    disconnect(&m_installer, nullptr, this, nullptr);
    disconnect(&m_poll, nullptr, this, nullptr);
    close();
    if (installing())
    {
        m_installer.kill();
        m_installer.waitForFinished(1000);
    }
#ifdef Q_OS_WIN
    if (m_job)
        CloseHandle(static_cast<HANDLE>(m_job));
#endif
}
bool GodotInspector::embedded() const
{
#ifdef Q_OS_WIN
    return QGuiApplication::platformName() == "windows";
#else
    return false;
#endif
}
QString GodotInspector::enginePath() const
{
    QString configuredPath = QString::fromUtf8(qgetenv("SLX_GODOT")).trimmed();
    if (configuredPath.startsWith('"') && configuredPath.endsWith('"'))
        configuredPath = configuredPath.mid(1, configuredPath.size() - 2);
    const QString binary = "Godot_v4.5-stable_win64.exe";
    const QStringList candidates{
        configuredPath, QCoreApplication::applicationDirPath() + "/runtime/godot/" + binary,
        m_root + "/runtime/godot/" + binary, m_root + "/build/tools/godot/" + binary};
    for (const auto &candidate : candidates)
        if (!candidate.isEmpty() && QFileInfo(candidate).isFile())
            return QFileInfo(candidate).absoluteFilePath();
    return {};
}
bool GodotInspector::available() const
{
    return !enginePath().isEmpty();
}
void GodotInspector::install()
{
    if (installing())
        return;
    QDir().mkpath(m_root + "/workspace");
    m_installer.setWorkingDirectory(m_root);
    m_installer.setStandardOutputFile(m_root + "/workspace/viewer-install.log");
    m_installer.setStandardErrorFile(m_root + "/workspace/viewer-install-errors.log");
    m_installer.setProgram("powershell.exe");
    m_installer.setArguments({"-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                              m_root + "/scripts/bootstrap-viewer.ps1"});
#ifdef Q_OS_WIN
    m_installer.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments)
                                                  { arguments->flags |= CREATE_NO_WINDOW; });
#endif
    m_message = "Preparing the 3D component...";
    m_installer.start();
    emit changed();
}
bool GodotInspector::ready() const
{
    return running() && !m_failed && m_frame.contains("scene") && (!embedded() || m_child != 0);
}
bool GodotInspector::nativeVisible() const
{
#ifdef Q_OS_WIN
    return ready() && m_child && IsWindowVisible(reinterpret_cast<HWND>(m_child));
#else
    return ready();
#endif
}
bool GodotInspector::nativeSizeMatches() const
{
#ifdef Q_OS_WIN
    if (!m_child)
        return false;
    RECT host{}, child{};
    GetClientRect(reinterpret_cast<HWND>(m_window->winId()), &host);
    GetClientRect(reinterpret_cast<HWND>(m_child), &child);
    return host.right > 0 && host.bottom > 0 && host.right == child.right &&
           host.bottom == child.bottom;
#else
    return ready();
#endif
}
void GodotInspector::log(const QByteArray &data)
{
    QFile file(m_root + "/workspace/viewer.log");
    if (file.size() < 1024 * 1024 && file.open(QIODevice::WriteOnly | QIODevice::Append))
        file.write(data.left(65536));
}
void GodotInspector::close()
{
    m_poll.stop();
    m_closing = true;
    if (running())
    {
        m_process.terminate();
        if (!m_process.waitForFinished(2000))
        {
            m_process.kill();
            m_process.waitForFinished(1000);
        }
    }
    m_child = 0;
    m_closing = false;
    emit changed();
}
void GodotInspector::open(int scene)
{
    if (scene < 0 || scene > 4)
        return;
    if (running() && scene == m_scene && !m_failed)
        return;
    m_scene = scene;
    const QDir imports(m_root + "/SLX_OrbitLab_3D/.godot/imported");
    bool modelsReady = true;
    const QStringList models{"Spacecraft_Deployed", "Spacecraft_Cutaway", "Spacecraft_Exploded",
                             "OrbitalScene", "GroundStation"};
    for (const auto &model : models)
        modelsReady &=
            !imports.entryList({"SLX_OrbitLab_" + model + ".glb-*.scn"}, QDir::Files).isEmpty();
    if (available() && !modelsReady)
    {
        install();
        return;
    }
    close();
    m_failed = false;
    m_frame.clear();
    m_buffer.clear();
    m_scene = scene;
    QDir().mkpath(m_root + "/workspace");
    QFile logFile(m_root + "/workspace/viewer.log");
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
        logFile.close();
    const QString executable = enginePath();
    if (executable.isEmpty())
    {
        m_failed = true;
        m_message = "The 3D component is missing from the package. Click Repair 3D to install it.";
        log(m_message.toUtf8() + '\n');
        emit changed();
        return;
    }
    QStringList arguments{"--path", m_root + "/SLX_OrbitLab_3D", "--windowed", "--single-window"};
    if (embedded())
        arguments << "--wid" << QString::number(m_window->winId()) << "--resolution"
                  << QString("%1x%2")
                         .arg(std::max(640, m_window->width()))
                         .arg(std::max(400, m_window->height()));
    else
        arguments << "--maximized";
    arguments << "--" << "--backend-port" << QString::number(m_port) << "--view"
              << QString::number(scene);
    if (embedded())
        arguments << "--embedded";
    arguments << "--ui-port" << QString::number(m_presentationSocket.localPort());
    m_presentationPort = 0;
    m_process.setWorkingDirectory(m_root);
    m_process.setProgram(executable);
#ifdef Q_OS_WIN
    m_process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments)
                                                { arguments->flags |= CREATE_NO_WINDOW; });
#endif
    log(("Engine: " + executable + '\n').toUtf8());
    m_process.setArguments(arguments);
    m_started.start();
    m_process.start();
    m_poll.start();
    m_message = "Starting Godot 4.5 · loading geometry...";
    emit changed();
}
void GodotInspector::readOutput()
{
    const auto data = m_process.readAllStandardOutput();
    log(data);
    m_buffer += data;
    if (m_buffer.size() > 65536)
        m_buffer.clear();
    int newline = -1;
    while ((newline = m_buffer.indexOf('\n')) >= 0)
    {
        const auto line = m_buffer.left(newline).trimmed();
        m_buffer.remove(0, newline + 1);
        if (line.startsWith("SLX_VIEWER_ENDPOINT "))
            m_presentationPort = line.mid(20).toUShort();
        if (line.startsWith("SLX_VIEWER_STATE "))
        {
            const auto document = QJsonDocument::fromJson(line.mid(17));
            if (document.isObject())
            {
                m_frame = document.object().toVariantMap();
                const auto component = m_frame.value("selected_component").toString();
                if (!component.isEmpty())
                    m_selectedComponent = component;
                if (!m_failed)
                    m_message = m_frame.value("run_id").toString().isEmpty()
                                    ? "3D ready · start a mission on the Mission page."
                                    : "3D view synchronized with the mission";
                emit changed();
            }
        }
    }
}
void GodotInspector::updateWindow()
{
#ifdef Q_OS_WIN
    if (embedded() && running())
    {
        const auto host = reinterpret_cast<HWND>(m_window->winId());
        ChildSearch search{static_cast<DWORD>(m_process.processId())};
        EnumChildWindows(host, findGodotChild, reinterpret_cast<LPARAM>(&search));
        // Godot 4.5 --wid establishes ownership on Windows. A real child is
        // required for clipping, tab visibility and Qt-managed native sizing.
        if (!search.result)
        {
            EnumWindows(findGodotChild, reinterpret_cast<LPARAM>(&search));
            if (search.result)
            {
                const auto style = GetWindowLongPtr(search.result, GWL_STYLE);
                SetWindowLongPtr(search.result, GWL_STYLE,
                                 (style & ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU)) |
                                     WS_CHILD | WS_CLIPSIBLINGS);
                SetParent(search.result, host);
                if (GetParent(search.result) != host)
                {
                    m_failed = true;
                    log("3D embedding error: " + QByteArray::number(GetLastError()) + '\n');
                    m_message = "Unable to display 3D in the console. Click Reopen 3D.";
                    emit changed();
                    return;
                }
                SetWindowPos(search.result, nullptr, 0, 0, 0, 0,
                             SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOSIZE | SWP_FRAMECHANGED);
            }
        }
        m_child = reinterpret_cast<quintptr>(search.result);
        if (search.result)
        {
            RECT bounds{}, childBounds{};
            GetClientRect(host, &bounds);
            GetClientRect(search.result, &childBounds);
            if (bounds.right > 0 && bounds.bottom > 0 &&
                (bounds.right != childBounds.right || bounds.bottom != childBounds.bottom))
                SetWindowPos(search.result, nullptr, 0, 0, bounds.right, bounds.bottom,
                             SWP_NOACTIVATE | SWP_NOZORDER);
        }
    }
#endif
    if (ready() && m_presentationPort && !m_pendingComponent.isEmpty())
    {
        presentation("select", {{"component", m_pendingComponent}});
        m_pendingComponent.clear();
    }
    if (!ready() && !m_failed && m_started.elapsed() > 20000)
    {
        m_failed = true;
        m_message = "The 3D view is not responding. Click Reopen 3D view.";
    }
    emit changed();
}
void GodotInspector::presentation(const QString &operation, QJsonObject values)
{
    if (!ready() || !m_presentationPort)
        return;
    values.insert("op", operation);
    m_presentationSocket.writeDatagram(QJsonDocument(values).toJson(QJsonDocument::Compact),
                                       QHostAddress::LocalHost, m_presentationPort);
}
void GodotInspector::selectComponent(const QString &component)
{
    m_pendingComponent = component;
    if (ready() && m_presentationPort)
    {
        presentation("select", {{"component", component}});
        m_pendingComponent.clear();
    }
}
void GodotInspector::focusComponent()
{
    presentation("focus");
}
void GodotInspector::isolateComponent(bool isolate)
{
    presentation("isolate", {{"enabled", isolate}});
}
void GodotInspector::resetCamera()
{
    presentation("reset");
}
