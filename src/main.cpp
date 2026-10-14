// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Desktop entry point, local service configuration and presentation diagnostics.
#include "controller.h"
#include "desktop_check.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QGuiApplication>
#include <QIcon>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <iostream>
#include <memory>
int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QLocale::setDefault(QLocale(QLocale::English, QLocale::UnitedStates));
    app.setOrganizationName("Silicon LogiX");
    app.setApplicationName("SLX OrbitLab");
    app.setApplicationVersion(SLX_APP_VERSION);
    app.setFont(QFont("Segoe UI"));
    app.setWindowIcon(QIcon(":/brand/orbitlab-icon.svg"));
    QQuickStyle::setStyle("Basic");
    const auto args = app.arguments();
    auto option = [&](const QString &name, const QString &fallback)
    {
        const int i = args.indexOf(name);
        return i >= 0 && i + 1 < args.size() ? args[i + 1] : fallback;
    };
    QString root = option("--root", QDir::currentPath());
    if (!QFile::exists(root + "/SLX_OrbitLab_3D/project.godot"))
        root = QDir(app.applicationDirPath() + "/../..").absolutePath();
    const QString diagnosticPath = option("--diagnostics", root + "/workspace/desktop.log");
    QDir().mkpath(QFileInfo(diagnosticPath).absolutePath());
    qputenv("SLX_ORBIT_DIAGNOSTICS", diagnosticPath.toUtf8());
    qInstallMessageHandler(
        [](QtMsgType, const QMessageLogContext &, const QString &message)
        {
            QFile log(QString::fromUtf8(qgetenv("SLX_ORBIT_DIAGNOSTICS")));
            if (log.size() < 1024 * 1024 && log.open(QIODevice::WriteOnly | QIODevice::Append))
                log.write(message.toUtf8() + '\n');
            std::cerr << message.toStdString() << '\n';
        });
    Controller controller(root, static_cast<quint16>(option("--port", "8765").toUInt()),
                          !args.contains("--no-backend-start"),
                          option("--distribution", "Ubuntu-22.04"));
    QQmlApplicationEngine engine;
    QStringList diagnostics;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [&](const QList<QQmlError> &warnings)
                     {
                         for (const auto &warning : warnings)
                             diagnostics.append(warning.toString());
                     });
    engine.rootContext()->setContextProperty("orbit", &controller);
    engine.load(QUrl("qrc:/qml/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 2;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().front());
    if (!window)
        return 3;
    const auto available = window->screen()->availableGeometry().adjusted(16, 16, -16, -16);
    window->setMinimumSize(
        QSize(std::min(920, available.width()), std::min(600, available.height())));
    window->resize(std::min(window->width(), available.width()),
                   std::min(window->height(), available.height()));
    window->setPosition(available.center() - QPoint(window->width() / 2, window->height() / 2));
    window->setProperty("page", option("--page", "0").toInt());
    if (args.contains("--mission-test") || args.contains("--operations-test") ||
        args.contains("--console-test") || args.contains("--sequence-test") ||
        args.contains("--orbit-test"))
        window->setTitle("SLX OrbitLab · Automated acceptance");
    if (args.contains("--about"))
        window->setProperty("aboutVisible", true);
    if (args.contains("--guide"))
        if (auto *guide = window->findChild<QObject *>("quickHelpDialog"))
            QMetaObject::invokeMethod(guide, "open");
    if (args.contains("--smoke-test"))
        QTimer::singleShot(std::clamp(option("--smoke-delay-ms", "1800").toInt(), 50, 10000), &app,
                           [&] { app.exit(diagnostics.isEmpty() ? 0 : 6); });
    std::unique_ptr<DesktopCheck> missionCheck;
    if (args.contains("--mission-test") || args.contains("--operations-test") ||
        args.contains("--console-test") || args.contains("--sequence-test") ||
        args.contains("--orbit-test"))
        missionCheck = std::make_unique<DesktopCheck>(
            controller, *window, option("--report", root + "/workspace/desktop-mission-check.json"),
            diagnostics, option("--screenshot", ""), args.contains("--operations-test"),
            args.contains("--console-test"), args.contains("--sequence-test"),
            args.contains("--orbit-test"));
    if (args.contains("--screenshot") && !args.contains("--mission-test") &&
        !args.contains("--operations-test") && !args.contains("--console-test") &&
        !args.contains("--sequence-test") && !args.contains("--orbit-test"))
        QTimer::singleShot(
            3500, &app,
            [&]
            {
                const auto position =
                    window->mapToGlobal(QPoint{}) - window->screen()->geometry().topLeft();
                const auto image = window->property("page").toInt() == 6
                                       ? window->screen()
                                             ->grabWindow(0, position.x(), position.y(),
                                                          window->width(), window->height())
                                             .toImage()
                                       : window->grabWindow();
                app.exit(!image.isNull() && image.save(option("--screenshot", "orbitlab.png")) ? 0
                                                                                               : 4);
            });
    return app.exec();
}
