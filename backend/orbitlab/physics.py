# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Basilisk spacecraft, reaction wheels, navigation, eclipse, solar panels and battery."""
import math
import numpy as np
from Basilisk.architecture import messaging
from Basilisk.simulation import spacecraft, reactionWheelStateEffector, simpleNav, eclipse
from Basilisk.simulation import simpleSolarPanel, simplePowerSink, simpleBattery, extForceTorque
from Basilisk.utilities import SimulationBaseClass, macros, simIncludeGravBody, simIncludeRW
from Basilisk.utilities import RigidBodyKinematics as rbk

EARTH_RATE = 7.2921150e-5
EARTH_RADIUS = 6378137.0
PHASES = ["Idle", "Wait window", "Recharge", "Sensor hold", "Slew", "Acquire",
          "Store", "Wait contact", "Downlink", "Complete", "Safe mode"]


def ecef_point(latitude, longitude):
    n = EARTH_RADIUS / math.sqrt(1 - 6.69437999014e-3 * math.sin(latitude) ** 2)
    return np.array([n * math.cos(latitude) * math.cos(longitude),
                     n * math.cos(latitude) * math.sin(longitude),
                     n * (1 - 6.69437999014e-3) * math.sin(latitude)])


def rotate_z(vector, angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([c * vector[0] - s * vector[1], s * vector[0] + c * vector[1], vector[2]])


class Physics:
    def __init__(self, scenario):
        self.scenario = scenario
        self.time_s = 0.0
        self.dt = float(scenario["step_s"])
        self.rng = np.random.default_rng(scenario["seed"])
        self.sim = SimulationBaseClass.SimBaseClass()
        process = self.sim.CreateNewProcess("Dynamics")
        process.addTask(self.sim.CreateNewTask("Physics", macros.sec2nano(self.dt)))
        self.satellite = spacecraft.Spacecraft()
        self.satellite.ModelTag = "Spacecraft_Root"
        self.satellite.hub.mHub = 65.0
        self.satellite.hub.IHubPntBc_B = [[18, 0, 0], [0, 20, 0], [0, 0, 16]]
        self.gravity = simIncludeGravBody.gravBodyFactory()
        earth = self.gravity.createEarth()
        earth.isCentralBody = True
        self.gravity.addBodiesTo(self.satellite)
        # Initial conditions pass the first requested target at t=300 s. Live jobs never reset orbit.
        first = scenario["targets"][0]
        lat, lon = math.radians(first["latitude_deg"]), math.radians(first["longitude_deg"])
        radial = rotate_z(ecef_point(lat, lon), EARTH_RATE * 300)
        radial /= np.linalg.norm(radial)
        east = np.array([-math.sin(lon + EARTH_RATE * 300), math.cos(lon + EARTH_RATE * 300), 0])
        north = np.cross(radial, east)
        tangent = (east + north) / np.linalg.norm(east + north)
        radius = EARTH_RADIUS + scenario["altitude_m"]
        rate = math.sqrt(earth.mu / radius ** 3)
        self.satellite.hub.r_CN_NInit = radius * (radial * math.cos(rate * 300) - tangent * math.sin(rate * 300))
        self.satellite.hub.v_CN_NInit = radius * rate * (radial * math.sin(rate * 300) + tangent * math.cos(rate * 300))
        self.satellite.hub.sigma_BNInit = [0.1, -0.05, 0.08]
        self.satellite.hub.omega_BN_BInit = [0, 0, 0]
        self.factory = simIncludeRW.rwFactory()
        for i in range(3):
            axis = [float(i == j) for j in range(3)]
            wheel = self.factory.create("Honeywell_HR16", axis, maxMomentum=50.0)
            wheel.u_max = 0.2
        self.wheels = reactionWheelStateEffector.ReactionWheelStateEffector()
        self.wheels.ModelTag = "Reaction_Wheel_Assembly"
        self.factory.addToSpacecraft("Reaction_Wheel_Assembly", self.wheels, self.satellite)
        self.wheel_command = messaging.ArrayMotorTorqueMsg()
        self.wheels.rwMotorCmdInMsg.subscribeTo(self.wheel_command)
        self.sim.AddModelToTask("Physics", self.wheels, 30)
        self.propulsion = extForceTorque.ExtForceTorque()
        self.propulsion.ModelTag = "Ideal_Propulsion"
        self.satellite.addDynamicEffector(self.propulsion)
        self.sim.AddModelToTask("Physics", self.propulsion, 25)
        self.propellant_kg = scenario.get("propellant_kg", 1.0)
        self.delivered_delta_v_mps = 0.0
        self.applied_thrust_n = 0.0
        self.sim.AddModelToTask("Physics", self.satellite, 20)
        self.nav = simpleNav.SimpleNav()
        self.nav.ModelTag = "Navigation_Sensors"
        self.nav.scStateInMsg.subscribeTo(self.satellite.scStateOutMsg)
        self.nav.RNGSeed = scenario["seed"]
        self.sim.AddModelToTask("Physics", self.nav, 10)
        self.sun_message = messaging.SpicePlanetStateMsg()
        sun = messaging.SpicePlanetStateMsgPayload()
        sun.PlanetName = "sun"
        sun.PositionVector = [149597870700.0, 0, 0]
        self.sun_message.write(sun)
        self.earth_message = messaging.SpicePlanetStateMsg()
        earth_state = messaging.SpicePlanetStateMsgPayload()
        earth_state.PlanetName = "earth"
        self.earth_message.write(earth_state)
        self.eclipse = eclipse.Eclipse()
        self.eclipse.ModelTag = "EarthOccultation"
        self.eclipse.addSpacecraftToModel(self.satellite.scStateOutMsg)
        self.eclipse.addPlanetToModel(self.earth_message)
        self.eclipse.sunInMsg.subscribeTo(self.sun_message)
        self.sim.AddModelToTask("Physics", self.eclipse, 9)
        self.panels = []
        for name in ("Solar_Left_Track", "Solar_Right_Track"):
            panel = simpleSolarPanel.SimpleSolarPanel()
            panel.ModelTag = name
            panel.stateInMsg.subscribeTo(self.satellite.scStateOutMsg)
            panel.sunInMsg.subscribeTo(self.sun_message)
            panel.sunEclipseInMsg.subscribeTo(self.eclipse.eclipseOutMsgs[0])
            panel.setPanelParameters([0, 0, 1], 0.5, 0.25)
            self.sim.AddModelToTask("Physics", panel, 8)
            self.panels.append(panel)
        self.load = simplePowerSink.SimplePowerSink()
        self.load.ModelTag = "Power_Controller"
        self.load.nodePowerOut = -35
        self.sim.AddModelToTask("Physics", self.load, 7)
        self.battery = simpleBattery.SimpleBattery()
        self.battery.ModelTag = "Battery_Module"
        self.battery.storageCapacity = scenario["capacity_j"]
        self.battery.storedCharge_Init = scenario["capacity_j"] * scenario["initial_soc"]
        for panel in self.panels:
            self.battery.addPowerNodeToModel(panel.nodePowerOutMsg)
        self.battery.addPowerNodeToModel(self.load.nodePowerOutMsg)
        self.sim.AddModelToTask("Physics", self.battery, 6)
        self.deploy_deg = 90.0 if scenario.get("initial_stowed", True) else 0.0
        self.fold_deg = 180.0 if scenario.get("initial_stowed", True) else 0.0
        self.track_rad = 0.0
        self.solar_available = True
        self.wheel_available = True
        self.sim.InitializeSimulation()
        self._update_panels()
        self.sim.ConfigureStopTime(0)
        self.sim.ExecuteSimulation()
        self.last_sensor_quaternion = None

    def _update_panels(self):
        # Deployment precedes unfolding; the energy area follows the confirmed mechanism state.
        opening = (1 - self.deploy_deg / 90) * (1 - self.fold_deg / 180)
        normal = [0, -math.sin(self.track_rad), math.cos(self.track_rad)]
        for panel in self.panels:
            panel.setPanelParameters(normal, 0.5 * max(0.0, opening) * int(self.solar_available), 0.25)

    def measurement(self, stored=False, delivered=False, faults=()):
        active = {f["kind"] for f in faults if f["start_s"] <= self.time_s < f["end_s"]}
        self.solar_available = "solar_generation" not in active
        self.wheel_available = "reaction_wheel" not in active
        self._update_panels()
        trans = self.nav.transOutMsg.read()
        attitude = self.nav.attOutMsg.read()
        truth = self.satellite.scStateOutMsg.read()
        sensor_valid = not any(f["kind"] == "attitude_sensor" and f["start_s"] <= self.time_s < f["end_s"] for f in faults)
        sigma = np.array(attitude.sigma_BN) + self.rng.normal(0, 2e-6, 3)
        q = rbk.MRP2EP(sigma).tolist()
        if sensor_valid or self.last_sensor_quaternion is None:
            self.last_sensor_quaternion = q
        else:
            q = self.last_sensor_quaternion
        sample = {"time_s": self.time_s, "position_eci_m": list(trans.r_BN_N),
                  "velocity_eci_mps": list(trans.v_BN_N), "quaternion_body_to_eci": q,
                  "angular_rate_body_radps": list(attitude.omega_BN_B),
                  "sun_direction_eci": [1, 0, 0], "attitude_valid": sensor_valid,
                  "energy_j": self.battery.batPowerOutMsg.read().storageLevel,
                  "generation_w": sum(panel.nodePowerOutMsg.read().netPower for panel in self.panels),
                  "consumed_w": -self.load.nodePowerOut,
                  "product_stored": stored, "downlink_confirmed": delivered,
                  "truth_quaternion_body_to_eci": rbk.MRP2EP(truth.sigma_BN).tolist(),
                  "wheel_speeds_radps": list(self.wheels.rwSpeedOutMsg.read().wheelSpeeds)[:3],
                  "sunlight_fraction": self.eclipse.eclipseOutMsgs[0].read().shadowFactor}
        sample.update({"actuator_valid": self.wheel_available,
                       "link_available": "ground_link" not in active,
                       "solar_peak_w": 340.25 * int(self.solar_available), "active_faults": sorted(active)})
        sample.update(propellant_kg=self.propellant_kg, delivered_delta_v_mps=self.delivered_delta_v_mps,
                      applied_thrust_n=self.applied_thrust_n, step_s=self.dt)
        return sample

    def advance(self, control):
        motor = messaging.ArrayMotorTorqueMsgPayload()
        motor.motorTorque = [-float(t) * int(self.wheel_available) for t in control["torque_body_nm"]] + [0.0] * 33
        self.wheel_command.write(motor, macros.sec2nano(self.time_s))
        self.load.nodePowerOut = -control["load_w"]
        # The C++ Basilisk effector integrates a centre-of-mass body +X force, never a velocity reset.
        requested = float(control.get("orbit", {}).get("force_body_n", [0, 0, 0])[0])
        thrust = min(max(requested, 0.0), 5.0, self.propellant_kg * 220 * 9.80665 / self.dt)
        self.propulsion.extForce_B = [thrust, 0, 0]
        self.applied_thrust_n = thrust
        self.propellant_kg = max(0.0, self.propellant_kg - thrust * self.dt / (220 * 9.80665))
        self.delivered_delta_v_mps += thrust * self.dt / 65.0
        target_deploy = 0.0 if control["deploy"] else 90.0
        target_fold = 0.0 if control["deploy"] else 180.0
        if control["deploy"]:
            self.deploy_deg = max(target_deploy, self.deploy_deg - 20 * self.dt)
            if self.deploy_deg == 0:
                self.fold_deg = max(target_fold, self.fold_deg - 40 * self.dt)
        else:
            self.fold_deg = min(target_fold, self.fold_deg + 40 * self.dt)
            if self.fold_deg == 180:
                self.deploy_deg = min(target_deploy, self.deploy_deg + 20 * self.dt)
        state = self.satellite.scStateOutMsg.read()
        sun_body = rbk.MRP2C(state.sigma_BN) @ np.array([1, 0, 0])
        desired = np.clip(math.atan2(-sun_body[1], sun_body[2]), -math.pi / 6, math.pi / 6)
        if self.deploy_deg == 0 and self.fold_deg == 0:
            self.track_rad += float(np.clip(desired - self.track_rad, -0.02 * self.dt, 0.02 * self.dt))
        else:
            self.track_rad = 0
        self._update_panels()
        self.time_s = round(self.time_s + self.dt, 9)
        self.sim.ConfigureStopTime(macros.sec2nano(self.time_s))
        self.sim.ExecuteSimulation()

    def visual(self, sample, control):
        r = rotate_z(sample["position_eci_m"], -EARTH_RATE * sample["time_s"])
        radius = float(np.linalg.norm(r))
        # The orbit view uses radius ratios; metre-scale meshes remain unchanged in close-up views.
        return {"position_eci_m": sample["position_eci_m"],
                "orbit_position_ecef_display": (r / EARTH_RADIUS * 8.0).tolist(),
                "quaternion_body_to_eci": sample["truth_quaternion_body_to_eci"],
                "earth_angle_rad": EARTH_RATE * sample["time_s"],
                "beacon_on": bool(control.get("vehicle", {}).get("beacon_on", False)),
                "payload_active": control["phase"] == 5,
                "radio_active": bool(control["downlink"]),
                "sensor_available": bool(sample["attitude_valid"]),
                "propulsion_active": sample.get("applied_thrust_n", 0) > 0,
                "altitude_m": radius - EARTH_RADIUS,
                "latitude_deg": math.degrees(math.asin(r[2] / radius)),
                "longitude_deg": math.degrees(math.atan2(r[1], r[0])),
                "pivots_native_deg": {"Solar_Left_Deploy": self.deploy_deg,
                    "Solar_Right_Deploy": -self.deploy_deg, "Solar_Left_Fold": self.fold_deg,
                    "Solar_Right_Fold": self.fold_deg,
                    "Solar_Left_Track": math.degrees(self.track_rad), "Solar_Right_Track": math.degrees(self.track_rad),
                    "GroundStation_AzimuthPivot": -math.degrees(control["ground_azimuth_rad"]),
                    "GroundStation_ElevationPivot": min(85, max(10, math.degrees(control["ground_elevation_rad"])))}}
