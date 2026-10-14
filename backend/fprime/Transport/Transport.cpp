// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Serialize native channels/events and emit correlated command acknowledgements.
#include <Fw/Log/LogPacket.hpp>
#include <Fw/Tlm/TlmPacket.hpp>
#include <Transport/Transport.hpp>
#include <chrono>
#include <cmath>
#include <cstdio>
namespace OrbitLab
{
void Transport::writePacket(const char *kind, const Fw::ComBuffer &packet)
{
    std::lock_guard<std::mutex> guard(m_output);
    std::printf("%s ", kind);
    for (FwSizeType i = 0; i < packet.getSize(); ++i)
        std::printf("%02x", packet.getBuffAddr()[i]);
    std::printf("\n");
    std::fflush(stdout);
}
void Transport::telemetryIn_handler(FwIndexType, FwChanIdType id, Fw::Time &time,
                                    Fw::TlmBuffer &value)
{
    Fw::TlmPacket packet;
    packet.resetPktSer();
    if (packet.addValue(id, time, value) == Fw::FW_SERIALIZE_OK)
        writePacket("TLM", packet.getBuffer());
}
void Transport::eventIn_handler(FwIndexType, FwEventIdType id, Fw::Time &time,
                                const Fw::LogSeverity &, Fw::LogBuffer &args)
{
    Fw::LogPacket packet;
    packet.setId(id);
    packet.setTimeTag(time);
    packet.setLogBuffer(args);
    Fw::ComBuffer buffer;
    if (packet.serializeTo(buffer) == Fw::FW_SERIALIZE_OK)
        writePacket("EVENT", buffer);
}
void Transport::responseIn_handler(FwIndexType, FwOpcodeType opcode, U32 sequence,
                                   const Fw::CmdResponse &response)
{
    std::lock_guard<std::mutex> guard(m_output);
    std::printf("ACK %u %u %u\n", static_cast<unsigned>(sequence), static_cast<unsigned>(opcode),
                static_cast<unsigned>(response.e));
    std::fflush(stdout);
}
void Transport::clockIn_handler(FwIndexType, Fw::Time &time)
{
    const auto now = m_time.load();
    const auto seconds = static_cast<U32>(std::floor(now));
    time = Fw::Time(TimeBase::TB_PROC_TIME, seconds, static_cast<U32>((now - seconds) * 1e6));
}
void Transport::sequencerCommandIn_handler(FwIndexType, Fw::ComBuffer &buffer, U32 context)
{
    ++m_dispatched;
    ++m_pending;
    sequencerCommandOut_out(0, buffer, context);
}
void Transport::sequencerResponseIn_handler(FwIndexType, FwOpcodeType opcode, U32 sequence,
                                            const Fw::CmdResponse &response)
{
    {
        std::lock_guard<std::mutex> guard(m_output);
        std::printf("SEQ_ACK %u %u %.17g\n", static_cast<unsigned>(opcode),
                    static_cast<unsigned>(response.e), m_time.load());
        std::fflush(stdout);
    }
    sequencerResponseOut_out(0, opcode, sequence, response);
    --m_pending;
}
void Transport::queueFenceReturn_handler(FwIndexType port, U32 token)
{
    std::lock_guard<std::mutex> guard(m_fenceMutex);
    m_fenceReceived[port] = token;
    m_fenceCondition.notify_all();
}
bool Transport::fence(FwIndexType port)
{
    const auto token = ++m_fenceToken;
    queueFence_out(port, token);
    std::unique_lock<std::mutex> lock(m_fenceMutex);
    return m_fenceCondition.wait_for(lock, std::chrono::seconds(2),
                                     [&] { return m_fenceReceived[port] == token; });
}
bool Transport::settle(bool tick)
{
    if (tick)
        sequenceTick_out(0, 0);
    // Drain both real active-component queues before sampling the passive mission core.
    // Sequencer responses can dispatch another immediate command, requiring another round.
    for (unsigned attempt = 0; attempt < 130; ++attempt)
    {
        const auto dispatched = m_dispatched.load();
        if (!fence(0) || !fence(1))
            return false;
        if (m_pending.load() == 0 && dispatched == m_dispatched.load())
        {
            if (tick)
            {
                dispatcherTick_out(0, 0);
                if (!fence(0))
                    return false;
            }
            return true;
        }
    }
    return false;
}
void Transport::synchronized()
{
    std::lock_guard<std::mutex> guard(m_output);
    std::puts("SYNC");
    std::fflush(stdout);
}
void Transport::ready()
{
    std::lock_guard<std::mutex> guard(m_output);
    std::puts("READY FPrime 4.3.0 ABI 2");
    std::fflush(stdout);
}
void Transport::state(const SlxControl &c, const SlxVehicleStatus &vehicle,
                      const SlxOrbitStatus &orbit, const SlxAccessWindow *windows, uint32_t count)
{
    std::lock_guard<std::mutex> guard(m_output);
    std::printf(
        "STATE "
        "{\"phase\":%u,\"target_id\":%u,\"completed\":%u,\"deferred\":%u,\"capture\":%u,"
        "\"downlink\":%u,\"deploy\":%u,\"torque_body_nm\":[%.15g,%.15g,%.15g],\"load_w\":%."
        "15g,\"pointing_error_rad\":%.15g,\"ground_azimuth_rad\":%.15g,\"ground_elevation_"
        "rad\":%.15g,\"window_start_s\":%.15g,\"window_end_s\":%.15g,\"required_energy_j\":"
        "%.15g,\"reason\":\"%s\",\"acquired\":%u,\"expired\":%u,\"safety_active\":%u,"
        "\"forecast_min_energy_j\":%.15g,\"forecast_horizon_s\":%.15g,\"next_eclipse_s\":%.15g,"
        "\"contact_start_s\":%.15g,\"contact_end_s\":%.15g,\"downlink_target_id\":%u,"
        "\"vehicle\":{\"maneuver_mode\":%u,\"payload_enabled\":%u,\"downlink_enabled\":%u,"
        "\"beacon_enabled\":%u,\"beacon_on\":%u,\"beacon_period_s\":%.15g,\"maneuver_angle_rad\":%."
        "15g}",
        c.phase, c.target_id, c.completed, c.deferred, c.capture, c.downlink, c.deploy,
        c.torque_body_nm[0], c.torque_body_nm[1], c.torque_body_nm[2], c.load_w,
        c.pointing_error_rad, c.ground_azimuth_rad, c.ground_elevation_rad, c.window_start_s,
        c.window_end_s, c.required_energy_j, c.reason, c.acquired, c.expired, c.safety_active,
        c.forecast_min_energy_j, c.forecast_horizon_s, c.next_eclipse_s, c.contact_start_s,
        c.contact_end_s, c.downlink_target_id, vehicle.maneuver_mode, vehicle.payload_enabled,
        vehicle.downlink_enabled, vehicle.beacon_enabled, vehicle.beacon_on,
        vehicle.beacon_period_s, vehicle.maneuver_angle_rad);
    std::printf(",\"orbit\":{\"burn_state\":%u,\"burn_count\":%u,\"requested_delta_v_mps\":%.15g,"
                "\"remaining_delta_v_mps\":%.15g,\"force_body_n\":[%.15g,%.15g,%.15g],"
                "\"semimajor_axis_m\":%.15g,\"eccentricity\":%.15g,\"inclination_rad\":%.15g,"
                "\"perigee_altitude_m\":%.15g,\"apogee_altitude_m\":%.15g,\"period_s\":%.15g,"
                "\"prediction_horizon_s\":%.15g},\"access_windows\":[",
                orbit.burn_state, orbit.burn_count, orbit.requested_delta_v_mps,
                orbit.remaining_delta_v_mps, orbit.force_body_n[0], orbit.force_body_n[1],
                orbit.force_body_n[2], orbit.semimajor_axis_m, orbit.eccentricity,
                orbit.inclination_rad, orbit.perigee_altitude_m, orbit.apogee_altitude_m,
                orbit.period_s, orbit.prediction_horizon_s);
    for (uint32_t i = 0; i < count; ++i)
        std::printf("%s{\"target_id\":%u,\"start_s\":%.15g,\"end_s\":%.15g}", i ? "," : "",
                    windows[i].target_id, windows[i].start_s, windows[i].end_s);
    std::puts("]}");
    std::fflush(stdout);
}
} // namespace OrbitLab
