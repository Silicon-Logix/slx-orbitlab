# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Operator explanations and examples for commands in the generated flight dictionary."""
import copy


MISSION = {
    "CONFIGURE": ("Configure a new mission", [648000, 0.1, 0.731342, 0.2181, 1],
        "Set battery capacity, reserve, ground station and strategy. Use Mission to start a new session.",
        "capacity [J], reserve [0.02–0.5], ground station latitude and longitude [rad], strategy 0=priority / 1=energy"),
    "ADD_TARGET": ("Add a target", [2, 0.852709, 0.041054, 80],
        "Schedule an observation of Paris. The satellite waits for a suitable pass; acquisition is not immediate.",
        "Unique ID, latitude [rad], longitude [rad], priority [0–100]. Use Targets and data for coordinates in degrees and a name."),
    "DEPLOY": ("Deploy or stow the panels", [0],
        "This example stows the panels: the hinges move in the 3D view and power generation changes.",
        "enabled: 0=stow / 1=deploy. Movement takes a few simulated seconds."),
    "SET_STRATEGY": ("Change the operating strategy", [1],
        "Change the planning policy during the mission while retaining targets and data. The change is recorded; both policies respect the energy reserve.",
        "strategy: 0=priority / 1=energy. Use Tests and comparisons to compare policies."),
    "ABORT": ("Cancel scheduled targets", [],
        "Close all pending targets. Previously acquired files remain onboard and can be downlinked.",
        "No parameters. The process and simulation keep running."),
    "SCHEDULE_TARGET": ("Schedule an observation", [2, 0.852709, 0.041054, 80, 0, 0],
        "Add Paris with priority 80. This example requests one acquisition with no deadline.",
        "Unique ID, latitude [rad], longitude [rad], priority [0–100], repeat interval [s, 0=once, minimum 60], deadline [s from mission start, 0=none]"),
    "SET_PRIORITY": ("Change a target's priority", [1, 100],
        "Set the specified target's priority to 100. The planner also considers access windows and energy; it does not interrupt an exposure.",
        "Existing target ID, new priority [0–100]"),
    "REMOVE_TARGET": ("Remove a target", [1],
        "Close the specified target. Previously acquired images are retained.",
        "Existing target ID. Check the list in Targets and data."),
    "MANEUVER": ("Rotate the satellite", [3, 45],
        "This example requests a relative rotation of 45°. F Prime commands the reaction wheels and Basilisk computes the motion; automatic observations are suspended.",
        "mode: 0=automatic mission / 1=Sun / 2=Earth / 3=relative rotation; angleDeg: angle [−180–180°], used by mode 3. Use CANCEL_BURN before an attitude maneuver during an active orbital burn."),
    "SET_PAYLOAD": ("Enable the optical instrument", [0],
        "This example suspends the instrument: no new images are acquired. With 1, observations resume when access, pointing and battery conditions permit.",
        "enabled: 0=suspend / 1=enable. Acquisition is scheduled rather than immediate."),
    "SET_DOWNLINK": ("Enable downlink", [0],
        "This example suspends downlink and retains data onboard. With 1, transfer waits for ground contact and sufficient energy.",
        "enabled: 0=suspend / 1=enable. Transfer requires onboard data and ground contact."),
    "SET_BEACON": ("Enable the beacon", [1, 4],
        "The beacon flashes in the 3D view with a period of 4 simulated seconds and a 2 W load during each pulse. Use 1× to watch it.",
        "enabled: 0=off / 1=enable; periodS: period [1–60 s]. The energy reserve can prevent flashing."),
    "ORBIT_BURN": ("Execute an orbital maneuver", [0, 2, 0],
        "This example increases along-track velocity by 2 m/s. F Prime aligns the +X axis, authorizes thrust and verifies the delta-v delivered by Basilisk. Insufficient energy or unavailable sensors suspend thrust.",
        "RTN delta-v [m/s]: radial, along-track, normal to the plane. Magnitude 0.01–10; sufficient propellant and predicted perigee ≥200 km required. It changes velocity over time; reaching a specific city requires suitable orbital geometry."),
    "CANCEL_BURN": ("Cancel the orbital maneuver", [],
        "Disable thrust from the next physics step. Velocity already gained and propellant already consumed remain in the model.", "No parameters. Observation targets remain scheduled."),
    "UPDATE_TARGET": ("Correct a target's coordinates", [1, 0.710572, -1.291648],
        "Update a pending target with New York coordinates and recalculate access windows. Previously acquired images and an exposure in progress are retained.",
        "Pending target ID, latitude [rad, −π/2..π/2], longitude [rad, −π..π]. The Targets page uses degrees."),
    "REPLAN": ("Recalculate access windows", [],
        "Refresh access predictions for all targets over the next 24 simulated hours from the measured orbital state.",
        "No parameters. Windows are predictions: acquisition still requires visibility, stable pointing and energy."),
}

DIAGNOSTICS = {
    "CMD_NO_OP": ("Check the command path", [],
        "Check delivery to the F Prime dispatcher and its OK response. The satellite and instruments retain their state.", "No parameters."),
    "CMD_NO_OP_STRING": ("Check text delivery", ["OrbitLab test"],
        "Send text to the dispatcher, which echoes it in the NoOpStringReceived event. This command verifies communication.", "arg1: text in quotes."),
    "CMD_TEST_CMD_1": ("Check parameter encoding", [-10, 1.5, 3],
        "Check serialization and decoding: the TestCmd1Args event reports all three values. This command verifies communication.",
        "arg1: I32 integer; arg2: F32 number; arg3: U8 integer [0–255]."),
    "CMD_CLEAR_TRACKING": ("Reset dispatcher tracking", [],
        "Clear the pending-response table and verify the dispatcher with a subsequent CMD_NO_OP. Available after sequences have ended and pending commands have completed.", "No parameters. F Prime 4.3 provides no reset ACK: operational confirmation comes from the subsequent native OK response."),
}

SEQUENCER = {
    "CS_RUN": ("Run a sequence", ["sequence.bin", "NO_BLOCK"]),
    "CS_VALIDATE": ("Validate a sequence file", ["sequence.bin"]),
    "CS_CANCEL": ("Cancel the active sequence", []),
    "CS_START": ("Start the first manual step", []),
    "CS_STEP": ("Advance to the next step", []),
    "CS_AUTO": ("Set automatic execution", []),
    "CS_MANUAL": ("Set manual execution", []),
    "CS_JOIN_WAIT": ("Wait for sequence completion", []),
}
SEQUENCE_DESCRIPTIONS = {
    "CS_VALIDATE": "Validate the structure and CRC of the dictionary-compiled binary. Click Validate sequence on the F Prime sequences page.",
    "CS_AUTO": "Set automatic mode before loading: commands run at their scheduled delays. Use Run automatically after the previous sequence has ended.",
    "CS_MANUAL": "Set manual mode before loading. Use Load for manual steps; the first command requires Start first step.",
    "CS_RUN": "Load and run the session's validated plan with NO_BLOCK. The load ACK is separate from step ACKs and sequence completion.",
    "CS_START": "Start the first command of the sequence loaded in manual mode. Subsequent commands require Next step.",
    "CS_STEP": "Execute the next manual step after the previous ACK and the scheduled delay.",
    "CS_CANCEL": "Cancel the active sequence. Already accepted commands remain applied; also use CANCEL_BURN to stop a requested burn.",
    "CS_JOIN_WAIT": "Request a native ACK at sequence completion while the clock and GUI continue running. Use Verify completion. In manual mode, continue advancing steps.",
}


def command_help(name):
    command = name.rsplit(".", 1)[-1]
    if name.startswith("OrbitLab.mission.") and command in MISSION:
        title, example, description, parameters = MISSION[command]
        enabled = command != "CONFIGURE"
        return {"title": title, "example": copy.deepcopy(example), "description": description,
                "parameter_help": parameters, "category": "mission", "direct_enabled": enabled,
                "workflow": "mission" if not enabled else "direct"}
    if name.startswith("OrbitLab.cmdDisp.") and command in DIAGNOSTICS:
        title, example, description, parameters = DIAGNOSTICS[command]
        return {"title": title, "example": copy.deepcopy(example), "description": description,
                "parameter_help": parameters, "category": "diagnostic", "direct_enabled": True,
                "workflow": "direct"}
    if name.startswith("OrbitLab.cmdSeq.") and command in SEQUENCER:
        title, example = SEQUENCER[command]
        return {"title": title, "example": copy.deepcopy(example), "description": SEQUENCE_DESCRIPTIONS[command],
            "parameter_help": "The Sequences page prepares the file name and execution mode.",
            "category": "sequencer", "direct_enabled": False, "workflow": "sequence"}
    return {"title": name, "example": [], "description": "Consult the deployment dictionary definition.",
            "parameter_help": "", "category": "other", "direct_enabled": False, "workflow": "dictionary"}
