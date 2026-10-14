// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Linux deployment entry point: native ground commands and physical step boundaries.
#include <Fw/Types/MallocAllocator.hpp>
#include <Os/Os.hpp>
#include <Top/OrbitLabTopologyAc.hpp>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
int main()
{
    Os::init();
    OrbitLab::TopologyState state;
    OrbitLab::initComponents(state);
    OrbitLab::setBaseIds();
    OrbitLab::connectComponents();
    Fw::MallocAllocator allocator;
    OrbitLab::cmdSeq.allocateBuffer(0, allocator, 8192);
    OrbitLab::regCommands();
    OrbitLab::startTasks(state);
    OrbitLab::transport.ready();
    char line[4096];
    while (std::fgets(line, sizeof(line), stdin))
    {
        std::istringstream stream(line);
        std::string kind;
        stream >> kind;
        if (kind == "CMD")
        {
            unsigned sequence = 0;
            std::string hex;
            stream >> sequence >> hex;
            Fw::ComBuffer buffer;
            bool valid = hex.size() % 2 == 0 && hex.size() / 2 <= buffer.getCapacity();
            for (size_t i = 0; valid && i < hex.size() / 2; ++i)
            {
                unsigned value = 0;
                if (std::sscanf(hex.substr(i * 2, 2).c_str(), "%2x", &value) != 1)
                    valid = false;
                else
                    buffer.getBuffAddr()[i] = static_cast<U8>(value);
            }
            if (valid)
            {
                buffer.setBuffLen(static_cast<FwSizeType>(hex.size() / 2));
                OrbitLab::transport.command(buffer, sequence);
            }
            else
            {
                std::puts("ERROR INVALID_NATIVE_PACKET");
                std::fflush(stdout);
            }
        }
        else if (kind == "STEP")
        {
            SlxMeasurement m{};
            stream >> m.time_s;
            for (auto &value : m.position_eci_m)
                stream >> value;
            for (auto &value : m.velocity_eci_mps)
                stream >> value;
            for (auto &value : m.quaternion_body_to_eci)
                stream >> value;
            for (auto &value : m.angular_rate_body_radps)
                stream >> value;
            for (auto &value : m.sun_direction_eci)
                stream >> value;
            stream >> m.energy_j >> m.generation_w >> m.consumed_w >> m.attitude_valid >>
                m.product_stored >> m.downlink_confirmed;
            stream >> m.product_target_id >> m.delivered_target_id >> m.actuator_valid >>
                m.link_available >> m.storage_free_bytes >> m.storage_used_bytes >> m.queue_depth >>
                m.sunlight_fraction >> m.solar_peak_w >> m.queue_target_id;
            SlxPropulsionSample propulsion{};
            stream >> propulsion.propellant_kg >> propulsion.delivered_delta_v_mps >>
                propulsion.step_s >> propulsion.applied_thrust_n;
            SlxControl control{};
            OrbitLab::transport.setTime(m.time_s);
            OrbitLab::seqAdapter.setTime(m.time_s);
            if (!stream.fail() && OrbitLab::seqAdapter.settle(true) &&
                OrbitLab::mission.propulsionSample(propulsion) &&
                OrbitLab::mission.step(m, control))
            {
                SlxAccessWindow windows[SLX_ORBIT_MAX_TARGETS]{};
                const auto count = OrbitLab::mission.accessWindows(windows);
                OrbitLab::transport.state(control, OrbitLab::mission.vehicleStatus(),
                                          OrbitLab::mission.orbitStatus(), windows, count);
            }
            else
            {
                std::puts("ERROR INVALID_PHYSICAL_FRAME");
                std::fflush(stdout);
            }
        }
        else if (kind == "SYNC")
        {
            if (OrbitLab::seqAdapter.settle())
                OrbitLab::seqAdapter.synchronized();
            else
            {
                std::puts("ERROR NATIVE_QUEUE_TIMEOUT");
                std::fflush(stdout);
            }
        }
        else if (kind == "QUIT")
            break;
        else
        {
            std::puts("ERROR UNKNOWN_REQUEST");
            std::fflush(stdout);
        }
    }
    OrbitLab::stopTasks(state);
    OrbitLab::freeThreads(state);
    OrbitLab::cmdSeq.deallocateBuffer(allocator);
    OrbitLab::deinitComponents(state);
    return 0;
}
