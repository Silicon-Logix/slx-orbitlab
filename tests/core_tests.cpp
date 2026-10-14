// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Mission ABI validation, bounded target storage, energy guard and invalid sensor behavior.
#include <SiliconLogiX/OrbitLab/Core.h>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
void require(bool condition, const char *message)
{
    if (!condition)
    {
        std::cerr << message << '\n';
        std::exit(1);
    }
}
int main()
{
    SlxConfig config{SLX_ORBIT_ABI, 1, 648000, 0.05, 0, 0, 0, 0.0087};
    require(slx_orbit_abi() == SLX_ORBIT_ABI, "ABI mismatch");
    require(slx_mission_create(nullptr) == nullptr, "Null configuration accepted");
    config.abi = 99;
    require(slx_mission_create(&config) == nullptr, "Wrong ABI accepted");
    config.abi = SLX_ORBIT_ABI;
    auto *mission = slx_mission_create(&config);
    require(mission != nullptr, "Valid mission rejected");
    SlxTarget target{1, 80, 0, 0};
    require(slx_mission_add_target(mission, &target), "Valid target rejected");
    require(!slx_mission_add_target(mission, &target), "Duplicate target accepted");
    target.latitude_rad = std::numeric_limits<double>::quiet_NaN();
    require(!slx_mission_add_target(mission, &target), "NaN target accepted");
    SlxMeasurement sample{};
    sample.position_eci_m[0] = 6928137;
    sample.velocity_eci_mps[1] = 7585;
    sample.quaternion_body_to_eci[0] = 1;
    sample.sun_direction_eci[0] = 1;
    sample.attitude_valid = 1;
    sample.actuator_valid = sample.link_available = 1;
    sample.storage_free_bytes = 2097152;
    sample.sunlight_fraction = 1;
    sample.solar_peak_w = 340.25;
    sample.energy_j = 40000;
    SlxControl control{};
    require(slx_mission_step(mission, &sample, &control), "Valid physical frame rejected");
    require(control.phase == SLX_RECHARGE && !control.capture, "Low energy must defer capture");
    sample.energy_j = 500000;
    sample.attitude_valid = 0;
    sample.time_s = 1;
    require(slx_mission_step(mission, &sample, &control), "Sensor outage frame rejected");
    require(control.phase == SLX_SENSOR_HOLD && !control.capture,
            "Invalid sensor must inhibit capture");
    require(control.torque_body_nm[0] == 0 && control.torque_body_nm[1] == 0 &&
                control.torque_body_nm[2] == 0,
            "Invalid attitude must inhibit torque");
    sample.time_s = 0;
    require(!slx_mission_step(mission, &sample, &control), "Backward simulation time accepted");
    sample.time_s = 2;
    sample.energy_j = -1;
    require(!slx_mission_step(mission, &sample, &control), "Negative physical energy accepted");
    require(slx_mission_priority(mission, 1, 95), "Native priority update rejected");
    require(!slx_mission_priority(mission, 1, 101), "Out-of-range priority accepted");
    require(slx_mission_remove_target(mission, 1), "Target retirement rejected");
    require(!slx_mission_remove_target(mission, 1), "Retired identifier remained active");
    require(!slx_mission_remove_target(mission, 0), "Reserved zero identifier accepted");
    SlxTarget expiring{2, 90, 0, 0, 0, 3};
    require(slx_mission_add_target(mission, &expiring), "Valid deadline rejected");
    sample.time_s = 4;
    sample.energy_j = 500000;
    sample.attitude_valid = 1;
    require(slx_mission_step(mission, &sample, &control), "Expiry frame rejected");
    require(control.expired == 1 && !control.capture, "Expired work must not be acquired");
    for (uint32_t id = 3; id < 35; ++id)
    {
        SlxTarget recycled{id, 80, 0, 0, 60, 0};
        require(slx_mission_add_target(mission, &recycled), "Retired slots were not recycled");
        require(slx_mission_remove_target(mission, id), "Recycled job retirement rejected");
    }
    slx_mission_destroy(mission);
    std::cout << "Mission ABI and safety contracts passed\n";
}
