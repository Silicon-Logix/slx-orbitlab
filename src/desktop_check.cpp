// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Require enabled QML actions, real native acknowledgements, physical motion and delivery.
#include "desktop_check.h"
#include "controller.h"
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSaveFile>
#include <QScreen>
#include <QtTest/QTest>
#include <cmath>
#include <iostream>
DesktopCheck::DesktopCheck(Controller &controller, QQuickWindow &window, QString report,
                           const QStringList &diagnostics, QString screenshot, bool operations,
                           bool console, bool sequences, bool orbits)
    : m_controller(controller), m_window(window), m_report(std::move(report)),
      m_screenshot(std::move(screenshot)), m_diagnostics(diagnostics), m_operations(operations),
      m_console(console), m_sequences(sequences), m_orbits(orbits)
{
    connect(&m_window, &QQuickWindow::frameSwapped, this, [this] { m_frameReady = true; });
    connect(&m_timer, &QTimer::timeout, this, &DesktopCheck::poll);
    m_elapsed.start();
    m_timer.start(100);
}
void DesktopCheck::poll()
{
    if (m_elapsed.elapsed() > (m_console || m_orbits ? 90000 : 45000))
        return finish("Desktop mission timed out: " + m_controller.message() + " · " +
                      m_controller.inspector()->message());
    if (!m_diagnostics.isEmpty())
        return finish("QML diagnostics: " + m_diagnostics.join("; "));
    if (!m_controller.status().value("error").toString().isEmpty())
        return finish(m_controller.status().value("error").toString());
    if (m_stage >= 60)
        return pollOrbits();
    if (m_stage >= 40)
        return pollSequences();
    if (m_stage >= 7)
        return pollConsole();
    if (m_stage == 0)
    {
        if (!m_controller.canControl() || m_controller.stale())
            return;
        if (m_window.property("page").toInt() != 0)
        {
            m_window.setProperty("page", 0);
            return;
        }
        if (!m_frameReady || !m_window.isActive())
        {
            m_window.requestActivate();
            return;
        }
        auto *start = m_window.findChild<QObject *>("missionStartButton");
        if (!start || !start->property("enabled").toBool())
            return finish("Mission start action is unavailable for the default valid target");
        if (!m_startGuideVerified)
        {
            if (!click(m_window.findChild<QQuickItem *>("quickHelpButton")))
                return finish("The optional help action is unavailable");
            auto *guide = m_window.findChild<QObject *>("quickHelpDialog");
            if (!guide || !guide->property("visible").toBool() ||
                guide->property("modal").toBool() || guide->property("dim").toBool())
                return finish("First-run help blocks the mission start control");
            m_startGuideVerified = true;
            return;
        }
        m_previousRun = m_controller.state().value("run_id").toString();
        if (!click(qobject_cast<QQuickItem *>(start)))
            return finish("Mission action is outside the visible window: " +
                          QString::number(m_window.width()) + " x " +
                          QString::number(m_window.height()));
        m_stage = 1;
        return;
    }
    const auto state = m_controller.state();
    if (state.value("run_id").toString() == m_previousRun ||
        !m_controller.status().value("fprime_running").toBool())
        return;
    if (m_stage == 1)
    {
        m_firstAttitude = state.value("quaternion_body_to_eci").toList();
        auto *speed = m_window.findChild<QQuickItem *>("missionSpeedSelector");
        if (!speed)
            return finish("Mission speed control is missing");
        if (!click(speed))
            return finish("Could not open the QML time-scale selector");
        m_stage = 2;
        return;
    }
    if (m_stage == 2)
    {
        auto *option = findItem(m_window.contentItem(), "missionSpeedSelector-option-3");
        if (!option || !option->isVisible())
        {
            if (m_elapsed.elapsed() > 15000)
            {
                auto *selector = m_window.findChild<QObject *>("missionSpeedSelector");
                auto *popup = selector->property("popup").value<QObject *>();
                return finish(QString("Time-scale popup: visible=%1, delegate=%2, active_window=%3")
                                  .arg(popup && popup->property("visible").toBool())
                                  .arg(option != nullptr)
                                  .arg(m_window.isActive()));
            }
            return;
        }
        if (!click(option))
            return finish("The QML time-scale popup is not reachable");
        m_stage = 3;
    }
    if (m_controller.status().value("speed").toDouble() != 600)
        return;
    if (m_stage == 4)
    {
        if (m_controller.status().value("playing").toBool())
            return;
        auto *jobName = m_window.findChild<QObject *>("observationJobName");
        if (!jobName)
            return finish("The new observation name cannot be edited");
        jobName->setProperty("text", "Second observation");
        auto *schedule = m_window.findChild<QQuickItem *>("scheduleTargetButton");
        if (!click(schedule))
            return finish("The observation scheduling control is unavailable");
        m_stage = 5;
        return;
    }
    if (m_stage == 5)
    {
        bool scheduled = false;
        for (const auto &target : state.value("targets").toList())
            scheduled |= target.toMap().value("id").toInt() > 1;
        if (!scheduled)
            return;
        if (!m_jobLabelVerified)
        {
            if (m_window.property("page").toInt() != 0)
            {
                if (!click(findItem(m_window.contentItem(), "pageButton-0")))
                    return finish("Could not inspect the new goal on the mission page");
                return;
            }
            const auto *label = m_window.findChild<QObject *>("missionActiveTarget");
            const auto *result = m_window.findChild<QObject *>("observationResultStatus");
            if (!label || !label->property("text").toString().contains("Second observation") ||
                !result || !result->property("text").toString().contains("no image"))
                return finish(
                    "The mission still presents the previous target or its image as the new goal");
            m_jobLabelVerified = true;
            if (!m_screenshot.isEmpty())
                m_window.grabWindow().save(m_screenshot + ".new-target.png");
            if (!click(findItem(m_window.contentItem(), "pageButton-4")))
                return finish("Could not return to the observation controls");
            return;
        }
        if (!click(m_window.findChild<QQuickItem *>("operationsPauseButton")))
            return finish("The operations resume control is unavailable");
        m_stage = 6;
        return;
    }
    const auto attitude = state.value("quaternion_body_to_eci").toList();
    if (attitude.size() == 4 && m_firstAttitude.size() == 4)
    {
        double difference = 0;
        for (int i = 0; i < 4; ++i)
            difference += std::abs(attitude[i].toDouble() - m_firstAttitude[i].toDouble());
        m_attitudeChanged |= difference > 0.01;
    }
    if (state.value("completed").toInt() < 1)
        return;
    if (m_stage == 3)
    {
        if (m_window.property("page").toInt() != 0)
        {
            m_window.setProperty("page", 0);
            return;
        }
        const auto *resultLabel = m_window.findChild<QObject *>("observationResultStatus");
        const auto *preview = m_window.findChild<QObject *>("observationImagePreview");
        if (!resultLabel ||
            !resultLabel->property("text").toString().contains("delivered to ground") || !preview ||
            preview->property("status").toInt() != 1)
            return finish("The received observation is not explained or its actual image preview "
                          "is unavailable");
        m_resultPreview = true;
        if (!m_enlargedPreview)
        {
            if (!click(m_window.findChild<QQuickItem *>("observationPreviewButton")))
                return finish("The observation preview cannot be enlarged");
            const auto *dialog = m_window.findChild<QObject *>("observationPreviewDialog");
            if (!dialog || !dialog->property("visible").toBool())
                return finish("The enlarged observation is unavailable");
            if (!click(m_window.findChild<QQuickItem *>("observationPreviewClose")))
                return finish("The enlarged observation cannot be closed");
            m_enlargedPreview = true;
        }
    }
    if (m_stage == 3 && !m_screenshot.isEmpty())
        m_window.grabWindow().save(m_screenshot + ".observation.png");
    if (m_operations && m_stage == 3)
    {
        if (!click(m_window.findChild<QQuickItem *>("missionPauseButton")) ||
            !click(findItem(m_window.contentItem(), "pageButton-4")))
            return finish("Could not pause and enter the operations page");
        m_stage = 4;
        return;
    }
    if (m_operations && state.value("completed").toInt() < 2)
        return;
    if (!m_attitudeChanged || m_controller.channels().size() < 11 ||
        m_controller.commands().isEmpty() || m_controller.catalogue().isEmpty() ||
        state.value("delivered_bytes").toInt() <= 0 || state.value("acquired").toInt() < 1 ||
        state.value("queue_depth").toInt() != 0)
        return finish("Incomplete native command, physical response or data-delivery evidence");
    const auto pivots = state.value("visual").toMap().value("pivots_native_deg").toMap();
    if (!pivots.contains("Solar_Left_Fold") ||
        std::abs(pivots.value("Solar_Left_Fold").toDouble()) > 0.001)
        return finish("Physical solar-panel deployment was not confirmed");
    if (m_orbits)
    {
        m_controller.setSpeed(60);
        m_window.setProperty("page", 8);
        m_stage = 60;
        return;
    }
    if (m_sequences)
    {
        if (!click(m_window.findChild<QQuickItem *>("missionPauseButton")))
            return finish("Could not pause before composing a sequence");
        m_stage = 40;
        return;
    }
    if (m_console)
    {
        if (!click(m_window.findChild<QQuickItem *>(m_operations ? "operationsPauseButton"
                                                                 : "missionPauseButton")) ||
            !click(findItem(m_window.contentItem(), "pageButton-1")))
            return finish("Could not pause and enter the native command console");
        m_stage = 7;
        return;
    }
    finish();
}
void DesktopCheck::pollOrbits()
{
    const auto state = m_controller.state();
    const auto orbit = state.value("orbit").toMap();
    if (m_stage == 60)
    {
        m_orbitInitialAxis = orbit.value("semimajor_axis_m").toDouble();
        m_orbitInitialFuel = state.value("propellant_kg").toDouble();
        if (!click(m_window.findChild<QQuickItem *>("orbitBurnSendButton")))
            return finish("The guided orbital burn action is unavailable");
        m_stage = 61;
        return;
    }
    if (m_stage == 61)
    {
        m_orbitThrustObserved |= state.value("applied_thrust_n").toDouble() > 0;
        if (m_orbitThrustObserved && !m_propulsion3D)
        {
            m_controller.action("pause");
            m_window.setProperty("page", 6);
            m_controller.openViewer(0);
            m_stage = 68;
            return;
        }
        if (orbit.value("burn_state").toInt() != 3)
            return;
        const auto result = m_controller.commandResult();
        if (result.value("name").toString() != "OrbitLab.mission.ORBIT_BURN" ||
            result.value("response").toInt() != 0 || !m_orbitThrustObserved ||
            std::abs(state.value("delivered_delta_v_mps").toDouble() - 2) > 1e-7 ||
            m_orbitInitialFuel - state.value("propellant_kg").toDouble() < 0.05 ||
            orbit.value("semimajor_axis_m").toDouble() - m_orbitInitialAxis < 1000)
            return finish("The orbital command lacks measured thrust, fuel debit or orbit change");
        m_orbitVerified = true;
        if (!m_screenshot.isEmpty())
            m_window.grabWindow().save(m_screenshot + ".burn.png");
        m_controller.action("pause");
        m_window.setProperty("page", 4);
        m_stage = 62;
        return;
    }
    if (m_stage == 68)
    {
        if (m_controller.status().value("playing").toBool() || !m_controller.inspector()->ready())
            return;
        const auto frame = m_controller.inspector()->frame();
        if (frame.value("time_s").toDouble() != state.value("time_s").toDouble() ||
            !frame.value("propulsion_visible").toBool())
            return;
        m_propulsion3D = true;
        if (!m_screenshot.isEmpty())
        {
            const auto position =
                m_window.mapToGlobal(QPoint{}) - m_window.screen()->geometry().topLeft();
            m_window.screen()
                ->grabWindow(0, position.x(), position.y(), m_window.width(), m_window.height())
                .save(m_screenshot + ".thrust-3d.png");
        }
        m_window.setProperty("page", 8);
        m_controller.action("resume");
        m_stage = 61;
        return;
    }
    if (m_stage == 62)
    {
        if (!click(m_window.findChild<QQuickItem *>("observationCityPreset")))
            return finish("The target city selector is unavailable");
        m_stage = 63;
        return;
    }
    if (m_stage == 63)
    {
        auto *option = findItem(m_window.contentItem(), "observationCityPreset-option-2");
        if (!option)
            return;
        if (!click(option))
            return finish("The New York preset is outside the visible popup");
        m_stage = 64;
        return;
    }
    if (m_stage == 64)
    {
        const auto *name = m_window.findChild<QObject *>("observationJobName");
        const auto *latitude = m_window.findChild<QObject *>("observationJobLatitude");
        const auto *longitude = m_window.findChild<QObject *>("observationJobLongitude");
        if (!name || name->property("text").toString() != "New York" || !latitude ||
            std::abs(latitude->property("text").toDouble() - 40.7128) > 1e-6 || !longitude ||
            std::abs(longitude->property("text").toDouble() + 74.0060) > 1e-6)
            return finish("The New York preset does not fill the correct name and coordinates");
        if (!click(m_window.findChild<QQuickItem *>("scheduleTargetButton")))
            return finish("The New York observation cannot be scheduled");
        m_stage = 65;
        return;
    }
    if (m_stage == 65)
    {
        bool found = false;
        for (const auto &target : state.value("targets").toList())
            found |= target.toMap().value("name").toString() == "New York";
        if (!found)
            return;
        m_controller.command("OrbitLab.mission.REPLAN", "[]", true);
        m_window.setProperty("page", 8);
        m_stage = 66;
        return;
    }
    if (m_stage == 66)
    {
        if (state.value("access_windows").toList().isEmpty())
            return;
        m_controller.action("pause");
        if (!m_window.findChild<QObject *>("orbitAccessWindows"))
            return finish("The target access windows are unavailable in the orbit page");
        m_stage = 67;
        return;
    }
    finish();
}
void DesktopCheck::pollSequences()
{
    const auto state = m_controller.state();
    if (m_stage == 40)
    {
        if (m_controller.status().value("playing").toBool())
            return;
        if (!click(findItem(m_window.contentItem(), "pageButton-7")))
            return finish("The command-sequence editor cannot be opened");
        m_stage = 41;
        return;
    }
    if (m_stage == 41)
    {
        const auto *steps = m_window.findChild<QObject *>("sequenceStepsList");
        if (!steps || steps->property("count").toInt() != 8)
            return finish("The operational sequence example is incomplete");
        if (!click(m_window.findChild<QQuickItem *>("sequenceSaveButton")) ||
            m_controller.sequencePlans().isEmpty())
            return finish("The operator plan cannot be saved for reuse");
        if (!click(m_window.findChild<QQuickItem *>("sequenceValidateButton")))
            return finish("The native validation action is unavailable");
        m_stage = 42;
        return;
    }
    if (m_stage == 42)
    {
        if (!m_controller.preparedSequence().value("validated").toBool())
            return;
        if (!m_screenshot.isEmpty())
            m_window.grabWindow().save(m_screenshot + ".prepared.png");
        if (!click(m_window.findChild<QQuickItem *>("sequenceRunButton")))
            return finish("A validated native sequence cannot be executed");
        m_stage = 43;
        return;
    }
    if (m_stage == 43)
    {
        const auto execution = state.value("sequence").toMap();
        if (execution.value("status").toString() != "completed")
            return;
        const auto steps = execution.value("steps").toList();
        if (steps.size() != 8 || execution.value("completed_steps").toInt() != 8)
            return finish("The sequencer did not acknowledge all eight steps");
        for (int index = 0; index < steps.size(); ++index)
        {
            const auto row = steps[index].toMap();
            if (!row.contains("executed_s") || row.value("response").toInt() != 0)
                return finish("Native step evidence is missing");
            const double previous = index == 0
                                        ? execution.value("started_s").toDouble()
                                        : steps[index - 1].toMap().value("executed_s").toDouble();
            if (std::abs(row.value("executed_s").toDouble() - previous -
                         row.value("delay_s").toDouble()) > 0.51)
                return finish("The native sequencer did not preserve simulated relative timing");
        }
        m_sequenceVerified = true;
        m_controller.action("pause");
        m_captureAfterMs = m_elapsed.elapsed() + 400;
        m_stage = 44;
        return;
    }
    if (m_stage == 44)
    {
        if (m_controller.status().value("playing").toBool() ||
            m_elapsed.elapsed() < m_captureAfterMs)
            return;
        if (!m_screenshot.isEmpty())
            m_window.grabWindow().save(m_screenshot + ".executed.png");
        m_controller.action("finish");
        if (!click(findItem(m_window.contentItem(), "pageButton-2")))
            return finish("The recordings page is unreachable");
        m_stage = 45;
        return;
    }
    auto *list = m_window.findChild<QQuickItem *>("recordingsList");
    if (m_stage == 45)
    {
        if (m_controller.status().value("fprime_running").toBool())
            return;
        auto *card = findItem(m_window.contentItem(), "recordingCard-0");
        auto *replay = findItem(m_window.contentItem(), "recordingReplay-0");
        auto *report = findItem(m_window.contentItem(), "recordingReport-0");
        if (!list || !card || !replay || !report || !replay->isEnabled())
            return;
        const auto replayPosition = replay->mapToItem(card, QPointF{});
        const auto reportPosition = report->mapToItem(card, QPointF{});
        if (replayPosition.y() + replay->height() > card->height() - 8 ||
            reportPosition.y() + report->height() > card->height() - 8 ||
            replayPosition.x() + replay->width() > reportPosition.x() + 1)
            return finish("Recording actions overlap or extend outside their card");
        m_recordingScroll = std::min(
            150.0, std::max(0.0, list->property("contentHeight").toDouble() - list->height()));
        list->setProperty("contentY", m_recordingScroll);
        m_captureAfterMs = m_elapsed.elapsed() + 1300;
        m_stage = 46;
        return;
    }
    if (m_stage == 46)
    {
        if (m_elapsed.elapsed() < m_captureAfterMs)
            return;
        if (!list || std::abs(list->property("contentY").toDouble() - m_recordingScroll) > 1)
            return finish("Recording scroll was reset by a telemetry heartbeat");
        m_recordingsVerified = true;
        list->setProperty("contentY", 0);
        m_stage = 47;
        return;
    }
    if (m_stage == 47)
    {
        if (!click(findItem(m_window.contentItem(), "recordingReplay-0")))
            return finish("The first recording cannot be replayed from its card");
        m_stage = 48;
        return;
    }
    if (m_stage == 48 && m_controller.status().value("mode").toString() == "REPLAY")
    {
        m_replayTargetTime = state.value("duration_s").toDouble();
        m_controller.seek(m_replayTargetTime);
        m_captureAfterMs = m_elapsed.elapsed() + 400;
        m_stage = 49;
        return;
    }
    if (m_stage == 49 && m_elapsed.elapsed() >= m_captureAfterMs)
    {
        if (state.value("time_s").toDouble() < m_replayTargetTime - 0.001)
            return;
        if (state.value("sequence").toMap().value("status").toString() != "completed")
            return finish("The synchronized replay lost the native sequence outcome");
        finish();
    }
}

void DesktopCheck::pollConsole()
{
    const auto state = m_controller.state();
    auto *inspector = m_controller.inspector();
    if (m_stage == 7)
    {
        if (m_controller.status().value("playing").toBool())
            return;
        const auto catalogue = m_controller.catalogue();
        for (int i = 0; i < catalogue.size(); ++i)
            if (catalogue[i].toMap().value("name").toString() == "OrbitLab.cmdDisp.CMD_NO_OP")
                m_noOpIndex = i;
        if (m_noOpIndex < 0)
            return finish("Native CMD_NO_OP is missing from the actual deployment dictionary");
        auto *channels = m_window.findChild<QObject *>("nativeTelemetryList");
        if (!channels || channels->property("count").toInt() < 20)
            return;
        if (!channels->property("visible").toBool() || channels->property("width").toDouble() < 300)
            return finish("Command help hides or compresses the native telemetry table");
        channels->setProperty("contentY", 300);
        m_telemetryScroll = channels->property("contentY").toDouble();
        auto *selector = m_window.findChild<QQuickItem *>("nativeCommandSelector");
        if (!m_examplesVerified)
        {
            for (int index = 0; index < catalogue.size(); ++index)
                if (catalogue[index].toMap().value("name").toString() ==
                    "OrbitLab.mission.SET_BEACON")
                    selector->setProperty("currentIndex", index);
            m_stage = 35;
            return;
        }
        selector->setProperty("currentIndex", m_noOpIndex);
        if (!click(selector))
            return finish("Native command selector is unavailable");
        m_stage = 8;
        return;
    }
    if (m_stage == 35)
    {
        auto *arguments = m_window.findChild<QObject *>("nativeCommandArguments");
        if (!arguments || arguments->property("text").toString() != "[1,4]")
            return finish("Beacon command arguments were not populated from its example");
        if (!m_screenshot.isEmpty())
            m_window.grabWindow().save(m_screenshot + ".command-example.png");
        arguments->setProperty("text", "[1,6]");
        m_captureAfterMs = m_elapsed.elapsed() + 1300;
        m_stage = 36;
        return;
    }
    if (m_stage == 36)
    {
        if (m_elapsed.elapsed() < m_captureAfterMs)
            return;
        const auto *arguments = m_window.findChild<QObject *>("nativeCommandArguments");
        if (!arguments || arguments->property("text").toString() != "[1,6]")
            return finish("Telemetry overwrote the operator's edited command arguments");
        if (!click(m_window.findChild<QQuickItem *>("nativeCommandExampleButton")))
            return finish("The operator cannot restore the command example");
        m_examplesVerified = true;
        m_stage = 7;
        return;
    }
    if (m_stage == 8)
    {
        auto *option = findItem(m_window.contentItem(),
                                "nativeCommandSelector-option-" + QString::number(m_noOpIndex));
        if (!option || !option->isVisible())
            return;
        if (option->property("text").toString() != "OrbitLab.cmdDisp.CMD_NO_OP")
            return finish("The command popup exposes an internal object instead of its mnemonic");
        m_nativeNames = true;
        if (!click(option))
            return finish("Native command popup selection is unreachable");
        m_stage = 9;
        return;
    }
    if (m_stage == 9)
    {
        const auto *label = m_window.findChild<QObject *>("nativeCommandFullName");
        if (!label || label->property("text").toString() != "OrbitLab.cmdDisp.CMD_NO_OP")
            return finish("Selected command is not readable in full");
        for (const auto &command : m_controller.commands())
            m_previousCommandSequence =
                std::max(m_previousCommandSequence, command.toMap().value("sequence").toInt());
        if (!click(m_window.findChild<QQuickItem *>("nativeCommandSendButton")))
            return finish("The selected native command cannot be sent");
        m_stage = 10;
        return;
    }
    if (m_stage == 10)
    {
        for (const auto &command : m_controller.commands())
        {
            const auto item = command.toMap();
            if (item.value("name").toString() == "OrbitLab.cmdDisp.CMD_NO_OP" &&
                item.value("sequence").toInt() > m_previousCommandSequence &&
                item.value("status").toString() == "OK")
                m_nativeAck = true;
        }
        if (!m_nativeAck)
            return;
        const auto *channels = m_window.findChild<QObject *>("nativeTelemetryList");
        if (!channels ||
            std::abs(channels->property("contentY").toDouble() - m_telemetryScroll) > 1)
            return finish("Native telemetry update reset the operator's scroll position");
        m_scrollPreserved = true;
        const auto *effect = m_window.findChild<QObject *>("nativeCommandEffect");
        if (!effect || !effect->property("text").toString().contains("checks communication"))
            return finish("A diagnostic command does not explain its lack of a physical effect");
        if (!click(m_window.findChild<QQuickItem *>("inspectorToolbarButton")))
            return finish("The prominent 3D toolbar action is unreachable");
        m_stage = 11;
        return;
    }
    if (m_stage == 11)
    {
        if (!inspector->ready() || !inspector->nativeVisible() ||
            inspector->frame().value("scene").toInt() != 3)
            return;
        if (!inspector->nativeSizeMatches())
            return;
        const auto frame = inspector->frame();
        if (frame.value("run_id").toString() != state.value("run_id").toString() ||
            frame.value("time_s").toDouble() != state.value("time_s").toDouble() ||
            frame.value("applied_frames").toInt() < 1)
            return;
        m_viewerFrames.append(frame);
        if (!m_screenshot.isEmpty())
        {
            const auto position =
                m_window.mapToGlobal(QPoint{}) - m_window.screen()->geometry().topLeft();
            m_window.screen()
                ->grabWindow(0, position.x(), position.y(), m_window.width(), m_window.height())
                .save(m_screenshot + ".orbital.png");
        }
        m_window.resize(m_window.width() - 110, m_window.height() - 70);
        m_stage = 12;
        return;
    }
    if (m_stage == 12)
    {
        if (!inspector->nativeSizeMatches())
            return;
        m_resized = true;
        if (!click(findItem(m_window.contentItem(), "pageButton-1")))
            return finish("Could not leave the embedded inspector");
        m_stage = 13;
        return;
    }
    if (m_stage == 13)
    {
        if (inspector->nativeVisible())
            return;
        m_hidden = true;
        if (!click(findItem(m_window.contentItem(), "pageButton-6")))
            return finish("Could not return to the embedded inspector");
        m_stage = 14;
        return;
    }
    if (m_stage == 14)
    {
        if (!inspector->nativeVisible())
            return;
        if (m_inspected == 4)
        {
            m_viewerStartTime = state.value("time_s").toDouble();
            if (!click(m_window.findChild<QQuickItem *>("inspectorPauseButton")))
                return finish("Could not resume the mission from the 3D pane");
            m_stage = 17;
            return;
        }
        if (!click(m_window.findChild<QQuickItem *>("inspectorSceneSelector")))
            return finish("The 3D scene selector is unreachable");
        m_stage = 15;
        return;
    }
    const int scene = m_inspected < 3 ? m_inspected : 4;
    if (m_stage == 15)
    {
        auto *option = findItem(m_window.contentItem(),
                                "inspectorSceneSelector-option-" + QString::number(scene));
        if (!option || !option->isVisible())
            return;
        if (inspector->nativeVisible())
            return finish("The native 3D surface covers the Qt scene-selection popup");
        if (!click(option))
            return finish("Could not select an inspector scene");
        m_stage = 16;
        return;
    }
    if (m_stage == 16)
    {
        auto *about = m_window.findChild<QObject *>("aboutDialog");
        if (about && about->property("visible").toBool())
        {
            QMetaObject::invokeMethod(about, "close");
            return;
        }
        if (m_window.property("page").toInt() != 6)
        {
            m_window.setProperty("page", 6);
            return;
        }
    }
    if (m_stage == 16 && inspector->ready() && inspector->nativeVisible() &&
        inspector->frame().value("scene").toInt() == scene && inspector->nativeSizeMatches() &&
        inspector->frame().value("run_id").toString() == state.value("run_id").toString() &&
        inspector->frame().value("time_s").toDouble() == state.value("time_s").toDouble() &&
        inspector->frame().value("applied_frames").toInt() > 0)
    {
        m_viewerFrames.append(inspector->frame());
        ++m_inspected;
        m_stage = 14;
    }
    if (m_stage == 17 && inspector->ready() &&
        inspector->frame().value("time_s").toDouble() > m_viewerStartTime + 5)
    {
        m_liveViewer = true;
        if (!click(m_window.findChild<QQuickItem *>("inspectorPauseButton")))
            return finish("Could not pause the physically advancing viewer");
        m_stage = 18;
        return;
    }
    if (m_stage == 18 && !m_controller.status().value("playing").toBool() &&
        inspector->frame().value("time_s").toDouble() == state.value("time_s").toDouble())
    {
        if (!click(m_window.findChild<QQuickItem *>("quickHelpButton")))
            return finish("The first-run guide is not reachable");
        m_stage = 19;
        return;
    }
    if (m_stage == 19)
    {
        auto *help = m_window.findChild<QObject *>("quickHelpDialog");
        if (!help || !help->property("visible").toBool() || inspector->nativeVisible())
            return;
        if (!m_window.isActive())
        {
            m_window.requestActivate();
            return;
        }
        m_helpVisibility = true;
        QTest::keyClick(&m_window, Qt::Key_Escape);
        m_stage = 20;
        return;
    }
    if (m_stage == 20 && inspector->nativeVisible())
    {
        // Allow the restored native surface to repaint after closing help.
        m_window.requestActivate();
        m_window.update();
        m_captureAfterMs = m_elapsed.elapsed() + 1000;
        m_stage = 21;
        return;
    }
    if (m_stage == 21 && inspector->nativeVisible() && m_elapsed.elapsed() >= m_captureAfterMs)
    {
        const auto *selector = m_window.findChild<QObject *>("inspectorSceneSelector");
        if (!selector ||
            selector->property("currentIndex").toInt() != inspector->frame().value("scene").toInt())
            return finish("The scene selector does not match the visible 3D scene");
        if (!m_vehicleComplete)
        {
            inspector->open(1);
            m_stage = 22;
            return;
        }
        finish();
    }
    if (m_stage == 22 && inspector->ready() && inspector->frame().value("scene").toInt() == 1)
    {
        if (!click(m_window.findChild<QQuickItem *>("vehicleComponentSelector")))
            return finish("Component selector is unreachable");
        m_stage = 23;
        return;
    }
    if (m_stage == 23)
    {
        auto *option = findItem(m_window.contentItem(), "vehicleComponentSelector-option-3");
        if (!option || !option->isVisible())
            return;
        if (!click(option))
            return finish("Navigation-sensor selection is unreachable");
        m_stage = 24;
        return;
    }
    if (m_stage == 24 && inspector->selectedComponent() == "Navigation_Sensors")
    {
        if (!click(m_window.findChild<QQuickItem *>("vehicleFocusButton")) ||
            !click(m_window.findChild<QQuickItem *>("vehicleIsolateCheck")))
            return finish("Component focus or isolation is unreachable");
        m_stage = 25;
        return;
    }
    if (m_stage == 25 && inspector->frame().value("isolated").toBool() &&
        inspector->frame().value("focused").toBool())
    {
        inspector->probeSelection();
        m_stage = 26;
        return;
    }
    if (m_stage == 26 && inspector->frame().value("pick_count").toInt() > 0 &&
        inspector->frame().value("picked_component") == "Navigation_Sensors")
    {
        m_componentVerified = true;
        inspector->open(0);
        m_stage = 27;
        return;
    }
    auto scrollControls = [&](double position)
    {
        auto *scroll = m_window.findChild<QObject *>("vehicleControlsScroll");
        auto *flick = scroll ? scroll->property("contentItem").value<QObject *>() : nullptr;
        return flick && flick->setProperty("contentY", position);
    };
    if (m_stage == 27 && inspector->ready() && inspector->frame().value("scene").toInt() == 0)
    {
        m_controller.setSpeed(1);
        if (!scrollControls(260))
            return finish("Vehicle controls cannot be scrolled");
        m_stage = 28;
        return;
    }
    if (m_stage == 28 && m_controller.status().value("speed").toDouble() == 1)
    {
        m_beaconStart = state.value("time_s").toDouble();
        if (!click(m_window.findChild<QQuickItem *>("vehicleBeaconButton")))
            return finish("Beacon command is unreachable");
        m_stage = 29;
        return;
    }
    const auto vehicle = state.value("vehicle").toMap();
    if (m_stage == 29 && vehicle.value("beacon_enabled").toInt() == 1 &&
        inspector->frame().value("time_s").toDouble() > m_beaconStart)
    {
        const auto *caption = m_window.findChild<QObject *>("vehicleBeaconStatus");
        if (!caption)
            return finish("The beacon's operator status is unavailable");
        const auto text = caption->property("text").toString();
        if (m_beaconCaption.isEmpty())
            m_beaconCaption = text;
        else if (text != m_beaconCaption)
            return finish("The beacon caption changes with each lamp pulse");
        m_beaconOn |= inspector->frame().value("beacon_visible").toBool();
        m_beaconOff |= !inspector->frame().value("beacon_visible").toBool();
        if (!m_beaconOn || !m_beaconOff)
            return;
        m_beaconCaptionStable = true;
        m_controller.setSpeed(60);
        scrollControls(150);
        m_stage = 30;
        return;
    }
    if (m_stage == 30 && m_controller.status().value("speed").toDouble() == 60)
    {
        m_maneuverStart = state.value("truth_quaternion_body_to_eci").toList();
        if (!click(m_window.findChild<QQuickItem *>("vehicleSlewButton")))
            return finish("Relative slew command is unreachable");
        m_stage = 31;
        return;
    }
    if (m_stage == 31 && vehicle.value("maneuver_mode").toInt() == 3)
    {
        const auto attitude = inspector->frame().value("quaternion_body_to_eci").toList();
        double difference = 0;
        if (attitude.size() != 4 || m_maneuverStart.size() != 4)
            return;
        for (int i = 0; i < 4; ++i)
            difference += std::abs(attitude[i].toDouble() - m_maneuverStart[i].toDouble());
        if (difference < 0.03)
            return;
        m_maneuverVerified = true;
        if (!click(m_window.findChild<QQuickItem *>("vehicleAutoButton")))
            return finish("Return to autonomous mission command is unreachable");
        m_stage = 32;
        return;
    }
    if (m_stage == 32 && vehicle.value("maneuver_mode").toInt() == 0)
    {
        scrollControls(260);
        m_stage = 33;
        return;
    }
    if (m_stage == 33)
    {
        if (!click(m_window.findChild<QQuickItem *>("vehicleBeaconButton")))
            return finish("Beacon shutdown command is unreachable");
        m_stage = 34;
        return;
    }
    if (m_stage == 34 && vehicle.value("beacon_enabled").toInt() == 0)
    {
        m_vehicleComplete = true;
        if (!click(m_window.findChild<QQuickItem *>("inspectorPauseButton")))
            return finish("Mission pause after vehicle checks is unreachable");
        m_stage = 18;
    }
}
bool DesktopCheck::click(QQuickItem *item)
{
    if (!item || !item->isVisible() || !item->isEnabled())
        return false;
    const QPointF point = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
    if (point.x() < 0 || point.y() < 0 || point.x() >= m_window.width() ||
        point.y() >= m_window.height())
        return false;
    QTest::mouseClick(&m_window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return true;
}
QQuickItem *DesktopCheck::findItem(QQuickItem *root, const QString &name)
{
    if (root->objectName() == name)
        return root;
    for (auto *child : root->childItems())
        if (auto *found = findItem(child, name))
            return found;
    return nullptr;
}
void DesktopCheck::finish(const QString &error)
{
    m_timer.stop();
    const auto state = m_controller.state();
    // Capture the desktop composition: a window DC can retain stale GPU pixels after resizing.
    const auto position = m_window.mapToGlobal(QPoint{}) - m_window.screen()->geometry().topLeft();
    const auto image = m_console ? m_window.screen()
                                       ->grabWindow(0, position.x(), position.y(), m_window.width(),
                                                    m_window.height())
                                       .toImage()
                                 : m_window.grabWindow();
    const bool screenshotSaved = m_screenshot.isEmpty() || image.save(m_screenshot);
    QJsonObject result{
        {"schema", "slx.orbitlab.desktop-mission/1"},
        {"passed", error.isEmpty()},
        {"error", error},
        {"run_id", state.value("run_id").toString()},
        {"time_s", state.value("time_s").toDouble()},
        {"delivered", state.value("completed").toInt()},
        {"delivered_bytes", state.value("delivered_bytes").toInt()},
        {"observation_result_preview", m_resultPreview},
        {"observation_enlargement", m_enlargedPreview},
        {"telemetry_scroll_preserved", m_scrollPreserved},
        {"native_sequence_editor_and_timing", m_sequenceVerified},
        {"native_orbit_burn_and_city_presets", m_orbitVerified},
        {"measured_propulsion_visible", m_orbitThrustObserved},
        {"confirmed_thrust_visible_in_godot", m_propulsion3D},
        {"orbital_state", QJsonObject::fromVariantMap(state.value("orbit").toMap())},
        {"propellant_kg", state.value("propellant_kg").toDouble()},
        {"replay_requested_s", m_replayTargetTime},
        {"delivered_delta_v_mps", state.value("delivered_delta_v_mps").toDouble()},
        {"recordings_layout_scroll_and_replay", m_recordingsVerified},
        {"new_goal_replaces_previous_result", m_jobLabelVerified},
        {"command_examples_and_operator_edits", m_examplesVerified},
        {"beacon_caption_stable", m_beaconCaptionStable},
        {"component_focus_isolation_and_pick", m_componentVerified},
        {"native_maneuver_visible", m_maneuverVerified},
        {"native_beacon_visible_on_and_off", m_beaconOn && m_beaconOff},
        {"native_channels", m_controller.channels().size()},
        {"attitude_changed", m_attitudeChanged},
        {"stage", m_stage},
        {"speed", m_controller.status().value("speed").toDouble()},
        {"help_does_not_block_start", m_startGuideVerified},
        {"qml_actions", true},
        {"qml_operations", m_operations},
        {"native_popup_names", m_nativeNames},
        {"selected_command_ack", m_nativeAck},
        {"inspector_resize", m_resized},
        {"inspector_tab_hide", m_hidden},
        {"inspector_ready", m_controller.inspector()->ready()},
        {"inspector_visible", m_controller.inspector()->nativeVisible()},
        {"inspector_size_matches", m_controller.inspector()->nativeSizeMatches()},
        {"inspector_live_updates", m_liveViewer},
        {"help_over_inspector", m_helpVisibility},
        {"inspector_last_frame", QJsonObject::fromVariantMap(m_controller.inspector()->frame())},
        {"interactive_viewer_frames", QJsonArray::fromVariantList(m_viewerFrames)}};
    const auto output = QJsonDocument(result).toJson(QJsonDocument::Indented);
    QSaveFile report(m_report);
    const bool saved = report.open(QIODevice::WriteOnly) && report.write(output) == output.size() &&
                       report.commit();
    std::cout << output.constData() << std::flush;
    QCoreApplication::exit(error.isEmpty() && saved && screenshotSaved ? 0 : 5);
}
