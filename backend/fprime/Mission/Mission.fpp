# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

module OrbitLab {
    @ Mission decisions execute synchronously at each simulation boundary.
    passive component Mission {
        command recv port commandIn
        command reg port commandRegister
        command resp port commandResponse
        event port eventOut
        text event port textEventOut
        telemetry port telemetryOut
        time get port timeGet
        @ Configure capacity [J], ground coordinates [rad] and strategy before advancing time.
        sync command CONFIGURE(capacityJ: F64, reserveFraction: F64, groundLatRad: F64, groundLonRad: F64, strategy: U32) opcode 0
        @ Submit an Earth observation target in WGS84 radians with a bounded priority.
        sync command ADD_TARGET(targetId: U32, latitudeRad: F64, longitudeRad: F64, targetPriority: U32) opcode 1
        @ Request physical panel deployment; telemetry confirms actual hinge angles.
        sync command DEPLOY(enabled: U32) opcode 2
        @ Select priority-first [0] or energy-aware [1] without bypassing safety guards.
        sync command SET_STRATEGY(strategy: U32) opcode 3
        @ Cancel pending observations. Existing acquired files remain in the archive.
        sync command ABORT opcode 4
        @ Schedule repeated observations [s] with optional absolute expiry [s].
        sync command SCHEDULE_TARGET(targetId: U32, latitudeRad: F64, longitudeRad: F64, targetPriority: U32, repeatS: F64, deadlineS: F64) opcode 5
        @ Reprioritize a pending target without resetting the simulation.
        sync command SET_PRIORITY(targetId: U32, targetPriority: U32) opcode 6
        @ Remove an observation job; already stored products remain available for downlink.
        sync command REMOVE_TARGET(targetId: U32) opcode 7
        @ Attitude mode: autonomous [0], Sun [1], nadir [2], relative optical-axis slew [3].
        sync command MANEUVER(mode: U32, angleDeg: F64) opcode 8
        sync command SET_PAYLOAD(enabled: U32) opcode 9
        sync command SET_DOWNLINK(enabled: U32) opcode 10
        @ Pulse period is simulation time [s]; the beacon consumes 2 W while illuminated.
        sync command SET_BEACON(enabled: U32, periodS: F64) opcode 11
        @ Finite propulsion maneuver in RTN [m/s], norm 0.01..10; alignment and safety enforced.
        sync command ORBIT_BURN(radialMps: F64, alongTrackMps: F64, normalMps: F64) opcode 12
        sync command CANCEL_BURN opcode 13
        @ Update a pending target; already captured product coordinates remain immutable.
        sync command UPDATE_TARGET(targetId: U32, latitudeRad: F64, longitudeRad: F64) opcode 14
        sync command REPLAN opcode 15
        event DecisionChanged(phaseId: U32, targetId: U32, reason: string size 96, availableJ: F64, requiredJ: F64) severity activity high id 0 format "Phase {} target {}: {}; available {} J, required {} J"
        event TargetAccepted(targetId: U32, targetPriority: U32) severity command id 1 format "Target {} priority {} accepted"
        event ConfigurationAccepted(capacityJ: F64, strategy: U32) severity command id 2 format "Capacity {} J, strategy {}"
        event VehicleCommandAccepted(commandName: string size 32, commandValue: F64) severity command id 3 format "{} accepted: {}"
        telemetry SimulationTime: F64 id 0
        telemetry MissionPhase: U32 id 1
        telemetry BatteryEnergy: F64 id 2
        telemetry SolarGeneration: F64 id 3
        telemetry LoadPower: F64 id 4
        telemetry PointingError: F64 id 5
        telemetry CompletedObservations: U32 id 6
        telemetry DeferredObservations: U32 id 7
        telemetry AttitudeSensorValid: U32 id 8
        telemetry RequiredEnergy: F64 id 9
        telemetry TargetId: U32 id 10
        telemetry AcquiredObservations: U32 id 11
        telemetry ExpiredTargets: U32 id 12
        telemetry SafeMode: U32 id 13
        telemetry ForecastMinimumEnergy: F64 id 14
        telemetry OnboardStorageUsed: F64 id 15
        telemetry ProductQueueDepth: F64 id 16
        telemetry GroundLinkAvailable: U32 id 17
        telemetry ActuatorValid: U32 id 18
        telemetry ContactStart: F64 id 19
        telemetry ContactEnd: F64 id 20
        telemetry SunlightFraction: F64 id 21
        telemetry DownlinkTargetId: U32 id 22
        telemetry ManeuverMode: U32 id 23
        telemetry PayloadEnabled: U32 id 24
        telemetry DownlinkEnabled: U32 id 25
        telemetry BeaconEnabled: U32 id 26
        telemetry BeaconOn: U32 id 27
        telemetry BeaconPeriod: F64 id 28
        telemetry PanelCommand: U32 id 29
        telemetry BurnState: U32 id 30
        telemetry BurnCount: U32 id 31
        telemetry BurnRemainingDeltaV: F64 id 32
        telemetry DeliveredDeltaV: F64 id 33
        telemetry PropellantMass: F64 id 34
        telemetry ThrustCommand: F64 id 35
        telemetry SemimajorAxis: F64 id 36
        telemetry Eccentricity: F64 id 37
        telemetry Inclination: F64 id 38
        telemetry PerigeeAltitude: F64 id 39
        telemetry ApogeeAltitude: F64 id 40
        telemetry OrbitPeriod: F64 id 41
        telemetry AppliedThrustForce: F64 id 42
    }
}
