# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

## Read-only local transport; presentation never writes mission or physical state.
extends Node
signal state_changed(snapshot: Dictionary, status: Dictionary)
signal connection_changed(connected: bool)

var peer := StreamPeerTCP.new()
var buffer := ""
var port := 8765
var connected := false
var retry_s := 0.0
var latest: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--backend-port")
	if index >= 0 and index + 1 < args.size():
		port = int(args[index + 1])
	peer.connect_to_host("127.0.0.1", port)

func _process(delta: float) -> void:
	peer.poll()
	var state := peer.get_status()
	if state == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			buffer = ""
			peer.put_data((JSON.stringify({"op": "hello", "role": "viewer", "request_id": "godot-viewer"}) + "\n").to_utf8_buffer())
			connection_changed.emit(true)
		var available := peer.get_available_bytes()
		if available > 0:
			buffer += peer.get_utf8_string(available)
		if buffer.length() > 1048576:
			peer.disconnect_from_host()
			buffer = ""
			return
		var newline := buffer.find("\n")
		while newline >= 0:
			var line := buffer.substr(0, newline)
			buffer = buffer.substr(newline + 1)
			var packet = JSON.parse_string(line)
			if packet is Dictionary and packet.get("type") == "snapshot":
				latest = packet.get("snapshot", {})
				latest["presentation_history"] = packet.get("history", [])
				state_changed.emit(latest, packet.get("status", {}))
			newline = buffer.find("\n")
	else:
		if connected:
			connected = false
			connection_changed.emit(false)
		if state != StreamPeerTCP.STATUS_CONNECTING:
			retry_s += delta
			if retry_s >= 1.5:
				retry_s = 0
				peer.disconnect_from_host()
				peer.connect_to_host("127.0.0.1", port)
