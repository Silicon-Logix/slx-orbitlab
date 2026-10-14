// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief F Prime command handlers wrap the separable mission ABI and publish genuine channels.
#pragma once
#include <Mission/MissionComponentAc.hpp>
#include <SiliconLogiX/OrbitLab/Core.h>
namespace OrbitLab
{
class Mission final : public MissionComponentBase
{
  public:
    explicit Mission(const char *name) : MissionComponentBase(name) {}
    ~Mission() override { slx_mission_destroy(m_mission); }
    bool step(const SlxMeasurement &measurement, SlxControl &control);
    bool propulsionSample(const SlxPropulsionSample &sample)
    {
        m_propulsion = sample;
        return slx_mission_propulsion_sample(m_mission, &sample) != 0;
    }
    SlxOrbitStatus orbitStatus() const
    {
        SlxOrbitStatus status{};
        slx_mission_orbit_status(m_mission, &status);
        return status;
    }
    uint32_t accessWindows(SlxAccessWindow *windows) const
    {
        return slx_mission_access_windows(m_mission, windows, SLX_ORBIT_MAX_TARGETS);
    }
    SlxVehicleStatus vehicleStatus() const
    {
        SlxVehicleStatus status{};
        slx_mission_vehicle_status(m_mission, &status);
        return status;
    }

  private:
    SlxMission *m_mission = nullptr;
    SlxPropulsionSample m_propulsion{};
    uint32_t m_lastPhase = 99;
    char m_lastReason[96]{};
    void CONFIGURE_cmdHandler(FwOpcodeType opcode, U32 sequence, F64 capacityJ, F64 reserveFraction,
                              F64 groundLatRad, F64 groundLonRad, U32 strategy) override;
    void ADD_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, F64 latitudeRad,
                               F64 longitudeRad, U32 priority) override;
    void DEPLOY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled) override;
    void SET_STRATEGY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 strategy) override;
    void ABORT_cmdHandler(FwOpcodeType opcode, U32 sequence) override;
    void SCHEDULE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, F64 latitudeRad,
                                    F64 longitudeRad, U32 priority, F64 repeatS,
                                    F64 deadlineS) override;
    void SET_PRIORITY_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id, U32 priority) override;
    void REMOVE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 id) override;
    void MANEUVER_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 mode, F64 angleDeg) override;
    void SET_PAYLOAD_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled) override;
    void SET_DOWNLINK_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled) override;
    void SET_BEACON_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 enabled,
                               F64 periodS) override;
    void ORBIT_BURN_cmdHandler(FwOpcodeType opcode, U32 sequence, F64 radialMps, F64 alongTrackMps,
                               F64 normalMps) override;
    void CANCEL_BURN_cmdHandler(FwOpcodeType opcode, U32 sequence) override;
    void UPDATE_TARGET_cmdHandler(FwOpcodeType opcode, U32 sequence, U32 targetId, F64 latitudeRad,
                                  F64 longitudeRad) override;
    void REPLAN_cmdHandler(FwOpcodeType opcode, U32 sequence) override;
};
} // namespace OrbitLab
