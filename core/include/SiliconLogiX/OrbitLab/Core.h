// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Versioned, Qt-independent C ABI for bounded mission decisions and attitude control.
#pragma once
#include <stdint.h>
#if defined(_WIN32)
#if defined(SLX_CORE_BUILD)
#define SLX_API __declspec(dllexport)
#else
#define SLX_API __declspec(dllimport)
#endif
#else
#define SLX_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C"
{
#endif
#define SLX_ORBIT_ABI 2u
#define SLX_ORBIT_MAX_TARGETS 16u
    typedef struct SlxMission SlxMission;
    typedef enum SlxPhase
    {
        SLX_IDLE,
        SLX_WAIT_WINDOW,
        SLX_RECHARGE,
        SLX_SENSOR_HOLD,
        SLX_SLEW,
        SLX_ACQUIRE,
        SLX_STORE,
        SLX_WAIT_CONTACT,
        SLX_DOWNLINK,
        SLX_COMPLETE,
        SLX_SAFE
    } SlxPhase;
    typedef struct SlxConfig
    {
        uint32_t abi;
        uint32_t strategy; /* 0 priority-first, 1 energy-aware; both enforce the safety reserve. */
        double capacity_j;
        double reserve_fraction;
        double ground_lat_rad;
        double ground_lon_rad;
        double epoch_earth_angle_rad;
        double pointing_limit_rad;
    } SlxConfig;
    typedef struct SlxTarget
    {
        uint32_t id;
        uint32_t priority;
        double latitude_rad;
        double longitude_rad;
        double repeat_s;   /* Zero: one observation; positive: minimum interval after capture. */
        double deadline_s; /* Zero: no expiry; otherwise absolute simulation time [s]. */
    } SlxTarget;
    typedef struct SlxMeasurement
    {
        double time_s;
        double position_eci_m[3];
        double velocity_eci_mps[3];
        double quaternion_body_to_eci[4]; /* Scalar-first [w,x,y,z]; estimated sensor attitude. */
        double angular_rate_body_radps[3];
        double sun_direction_eci[3];
        double energy_j;
        double generation_w;
        double consumed_w;
        uint32_t attitude_valid;
        uint32_t product_stored;
        uint32_t downlink_confirmed;
        uint32_t product_target_id;
        uint32_t delivered_target_id;
        uint32_t actuator_valid;
        uint32_t link_available;
        double storage_free_bytes;
        double storage_used_bytes;
        double queue_depth;
        double sunlight_fraction;
        double solar_peak_w;
        uint32_t queue_target_id;
    } SlxMeasurement;
    typedef struct SlxControl
    {
        uint32_t phase;
        uint32_t target_id;
        uint32_t completed;
        uint32_t deferred;
        uint32_t capture;
        uint32_t downlink;
        uint32_t deploy;
        double torque_body_nm[3];
        double load_w;
        double pointing_error_rad;
        double ground_azimuth_rad;
        double ground_elevation_rad;
        double window_start_s;
        double window_end_s;
        double required_energy_j;
        char reason[96];
        uint32_t acquired;
        uint32_t expired;
        uint32_t downlink_target_id;
        uint32_t safety_active;
        double forecast_min_energy_j;
        double forecast_horizon_s;
        double next_eclipse_s;
        double contact_start_s;
        double contact_end_s;
    } SlxControl;
    SLX_API uint32_t slx_orbit_abi(void);
    SLX_API const char *slx_orbit_version(void);
    SLX_API SlxMission *slx_mission_create(const SlxConfig *config);
    SLX_API void slx_mission_destroy(SlxMission *mission);
    SLX_API int slx_mission_add_target(SlxMission *mission, const SlxTarget *target);
    SLX_API int slx_mission_strategy(SlxMission *mission, uint32_t strategy);
    SLX_API int slx_mission_priority(SlxMission *mission, uint32_t target_id, uint32_t priority);
    SLX_API int slx_mission_remove_target(SlxMission *mission, uint32_t target_id);
    SLX_API void slx_mission_deploy(SlxMission *mission, uint32_t deployed);
    SLX_API void slx_mission_abort(SlxMission *mission);
    /* Additive vehicle API, available from core 0.4.0; existing ABI 2 layouts are unchanged. */
    typedef struct SlxVehicleStatus
    {
        uint32_t maneuver_mode; /* 0 autonomous, 1 Sun pointing, 2 nadir, 3 relative slew. */
        uint32_t payload_enabled;
        uint32_t downlink_enabled;
        uint32_t beacon_enabled;
        uint32_t beacon_on;
        double beacon_period_s;
        double maneuver_angle_rad;
    } SlxVehicleStatus;
    SLX_API int slx_mission_maneuver(SlxMission *mission, uint32_t mode, double angle_rad);
    SLX_API int slx_mission_payload(SlxMission *mission, uint32_t enabled);
    SLX_API int slx_mission_downlink(SlxMission *mission, uint32_t enabled);
    SLX_API int slx_mission_beacon(SlxMission *mission, uint32_t enabled, double period_s);
    SLX_API int slx_mission_vehicle_status(const SlxMission *mission, SlxVehicleStatus *status);
    /* Additive orbital API, core 0.6.0. RTN: radial, along-track, orbit normal. */
    typedef struct SlxPropulsionSample
    {
        double propellant_kg;
        double delivered_delta_v_mps; /* Cumulative scalar integral of thrust/mass. */
        double step_s;
        double applied_thrust_n; /* Applied force in the preceding physics quantum. */
    } SlxPropulsionSample;
    typedef struct SlxOrbitStatus
    {
        uint32_t burn_state; /* 0 idle, 1 aligning, 2 thrusting, 3 complete, 4 canceled, 5 held. */
        uint32_t burn_count;
        double requested_delta_v_mps;
        double remaining_delta_v_mps;
        double force_body_n[3];
        double semimajor_axis_m;
        double eccentricity;
        double inclination_rad;
        double perigee_altitude_m;
        double apogee_altitude_m;
        double period_s;
        double prediction_horizon_s;
    } SlxOrbitStatus;
    typedef struct SlxAccessWindow
    {
        uint32_t target_id;
        double start_s;
        double end_s;
    } SlxAccessWindow;
    SLX_API int slx_mission_propulsion_sample(SlxMission *mission,
                                              const SlxPropulsionSample *sample);
    SLX_API int slx_mission_orbit_burn(SlxMission *mission, double radial_mps,
                                       double along_track_mps, double normal_mps);
    SLX_API int slx_mission_cancel_burn(SlxMission *mission);
    SLX_API int slx_mission_orbit_status(const SlxMission *mission, SlxOrbitStatus *status);
    SLX_API uint32_t slx_mission_access_windows(const SlxMission *mission, SlxAccessWindow *windows,
                                                uint32_t capacity);
    SLX_API int slx_mission_replan(SlxMission *mission);
    SLX_API int slx_mission_update_target(SlxMission *mission, uint32_t target_id,
                                          double latitude_rad, double longitude_rad);
    SLX_API int slx_mission_step(SlxMission *mission, const SlxMeasurement *input,
                                 SlxControl *output);
#ifdef __cplusplus
}
#endif
