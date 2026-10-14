// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Validate native commands and expose mission decisions through F Prime telemetry and
/// events.
#include <Mission/Mission.hpp>
#include <cstring>
namespace OrbitLab
{
void Mission::CONFIGURE_cmdHandler(FwOpcodeType opcode, U32 sequence, F64 capacityJ,
                                   F64 reserveFraction, F64 groundLatRad, F64 groundLonRad,
                                   U32 strategy)
{
    const SlxConfig config{SLX_ORBIT_ABI, strategy,     capacityJ, reserveFraction,
                           groundLatRad,  groundLonRad, 0,         0.008726646259971648};
    auto *replacement = slx_mission_create(&config);
    if (!replacement)
    {
        cmdResponse_out(opcode, sequence, Fw::CmdResponse::VALIDATION_ERROR);
        return;
    }
    slx_mission_destroy(m_mission);
    m_mission = replacement;
    m_lastPhase = 99;
    m_lastReason[0] = 0;
    log_COMMAND_ConfigurationAccepted(capacityJ, strategy);
    cmdResponse_out(opcode, sequence, Fw::CmdResponse::OK);
}
void Mission::ADD_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, F64 latitudeRad,
                                    F64 longitudeRad, U32 priority)
{
    const SlxTarget target{id, priority, latitudeRad, longitudeRad};
    const bool accepted = slx_mission_add_target(m_mission, &target) != 0;
    if (accepted)
        log_COMMAND_TargetAccepted(id, priority);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::DEPLOY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled)
{
    if (!m_mission || enabled > 1)
    {
        cmdResponse_out(opcode, sequence, Fw::CmdResponse::VALIDATION_ERROR);
        return;
    }
    slx_mission_deploy(m_mission, enabled);
    log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("PANELS"), enabled);
    cmdResponse_out(opcode, sequence, Fw::CmdResponse::OK);
}
void Mission::SET_STRATEGY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 strategy)
{
    cmdResponse_out(opcode, sequence,
                    slx_mission_strategy(m_mission, strategy) ? Fw::CmdResponse::OK
                                                              : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::ABORT_cmdHandler(FwOpcodeType opcode, U32 sequence)
{
    slx_mission_abort(m_mission);
    cmdResponse_out(opcode, sequence,
                    m_mission ? Fw::CmdResponse::OK : Fw::CmdResponse::EXECUTION_ERROR);
}
bool Mission::step(const SlxMeasurement &in, SlxControl &out)
{
    if (!slx_mission_step(m_mission, &in, &out))
        return false;
    if (out.phase != m_lastPhase || std::strcmp(out.reason, m_lastReason) != 0)
    {
        Fw::LogStringArg reason(out.reason);
        log_ACTIVITY_HI_DecisionChanged(out.phase, out.target_id, reason, in.energy_j,
                                        out.required_energy_j);
        m_lastPhase = out.phase;
        std::strncpy(m_lastReason, out.reason, sizeof(m_lastReason) - 1);
    }
    tlmWrite_SimulationTime(in.time_s);
    tlmWrite_MissionPhase(out.phase);
    tlmWrite_BatteryEnergy(in.energy_j);
    tlmWrite_SolarGeneration(in.generation_w);
    tlmWrite_LoadPower(in.consumed_w);
    tlmWrite_PointingError(out.pointing_error_rad);
    tlmWrite_CompletedObservations(out.completed);
    tlmWrite_DeferredObservations(out.deferred);
    tlmWrite_AttitudeSensorValid(in.attitude_valid);
    tlmWrite_RequiredEnergy(out.required_energy_j);
    tlmWrite_TargetId(out.target_id);
    tlmWrite_AcquiredObservations(out.acquired);
    tlmWrite_ExpiredTargets(out.expired);
    tlmWrite_SafeMode(out.safety_active);
    tlmWrite_ForecastMinimumEnergy(out.forecast_min_energy_j);
    tlmWrite_OnboardStorageUsed(in.storage_used_bytes);
    tlmWrite_ProductQueueDepth(in.queue_depth);
    tlmWrite_GroundLinkAvailable(in.link_available);
    tlmWrite_ActuatorValid(in.actuator_valid);
    tlmWrite_ContactStart(out.contact_start_s);
    tlmWrite_ContactEnd(out.contact_end_s);
    tlmWrite_SunlightFraction(in.sunlight_fraction);
    tlmWrite_DownlinkTargetId(out.downlink_target_id);
    const auto vehicle = vehicleStatus();
    tlmWrite_ManeuverMode(vehicle.maneuver_mode);
    tlmWrite_PayloadEnabled(vehicle.payload_enabled);
    tlmWrite_DownlinkEnabled(vehicle.downlink_enabled);
    tlmWrite_BeaconEnabled(vehicle.beacon_enabled);
    tlmWrite_BeaconOn(vehicle.beacon_on);
    tlmWrite_BeaconPeriod(vehicle.beacon_period_s);
    tlmWrite_PanelCommand(out.deploy);
    const auto orbit = orbitStatus();
    tlmWrite_BurnState(orbit.burn_state);
    tlmWrite_BurnCount(orbit.burn_count);
    tlmWrite_BurnRemainingDeltaV(orbit.remaining_delta_v_mps);
    tlmWrite_DeliveredDeltaV(m_propulsion.delivered_delta_v_mps);
    tlmWrite_PropellantMass(m_propulsion.propellant_kg);
    tlmWrite_ThrustCommand(orbit.force_body_n[0]);
    tlmWrite_AppliedThrustForce(m_propulsion.applied_thrust_n);
    tlmWrite_SemimajorAxis(orbit.semimajor_axis_m);
    tlmWrite_Eccentricity(orbit.eccentricity);
    tlmWrite_Inclination(orbit.inclination_rad);
    tlmWrite_PerigeeAltitude(orbit.perigee_altitude_m);
    tlmWrite_ApogeeAltitude(orbit.apogee_altitude_m);
    tlmWrite_OrbitPeriod(orbit.period_s);
    return true;
}
void Mission::SCHEDULE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, F64 latitudeRad,
                                         F64 longitudeRad, U32 priority, F64 repeatS, F64 deadlineS)
{
    const SlxTarget target{id, priority, latitudeRad, longitudeRad, repeatS, deadlineS};
    const bool accepted = slx_mission_add_target(m_mission, &target) != 0;
    if (accepted)
        log_COMMAND_TargetAccepted(id, priority);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::SET_PRIORITY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, U32 priority)
{
    cmdResponse_out(opcode, sequence,
                    slx_mission_priority(m_mission, id, priority)
                        ? Fw::CmdResponse::OK
                        : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::REMOVE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id)
{
    cmdResponse_out(opcode, sequence,
                    slx_mission_remove_target(m_mission, id) ? Fw::CmdResponse::OK
                                                             : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::MANEUVER_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 mode, F64 angleDeg)
{
    const bool accepted = slx_mission_maneuver(m_mission, mode, angleDeg * 0.017453292519943295);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("MANEUVER"), mode);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::SET_PAYLOAD_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled)
{
    const bool accepted = slx_mission_payload(m_mission, enabled);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("PAYLOAD"), enabled);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::SET_DOWNLINK_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled)
{
    const bool accepted = slx_mission_downlink(m_mission, enabled);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("DOWNLINK"), enabled);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::SET_BEACON_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled, F64 periodS)
{
    const bool accepted = slx_mission_beacon(m_mission, enabled, periodS);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("BEACON"), enabled);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::ORBIT_BURN_cmdHandler(FwOpcodeType opcode, U32 sequence, F64 radial, F64 along,
                                    F64 normal)
{
    const bool accepted = slx_mission_orbit_burn(m_mission, radial, along, normal);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("ORBIT_BURN"),
                                           orbitStatus().requested_delta_v_mps);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::CANCEL_BURN_cmdHandler(FwOpcodeType opcode, U32 sequence)
{
    const bool accepted = slx_mission_cancel_burn(m_mission);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("CANCEL_BURN"), 0);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::EXECUTION_ERROR);
}
void Mission::UPDATE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, F64 lat, F64 lon)
{
    const bool accepted = slx_mission_update_target(m_mission, id, lat, lon);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("UPDATE_TARGET"), id);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::VALIDATION_ERROR);
}
void Mission::REPLAN_cmdHandler(FwOpcodeType opcode, U32 sequence)
{
    const bool accepted = slx_mission_replan(m_mission);
    if (accepted)
        log_COMMAND_VehicleCommandAccepted(Fw::LogStringArg("REPLAN"), 86400);
    cmdResponse_out(opcode, sequence,
                    accepted ? Fw::CmdResponse::OK : Fw::CmdResponse::EXECUTION_ERROR);
}
} // namespace OrbitLab
