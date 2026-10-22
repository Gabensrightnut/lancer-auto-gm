class_name NetConfig
extends RefCounted
## Where online play finds its matchmaking (signaling) server and NAT helpers (STUN/TURN).
## Defaults are free public services. A player can override any of it without a new build by
## putting a net_config.json in the game's user data folder, e.g. to add a TURN relay:
##   {"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]},
##                    {"urls": ["turn:relay.example.com:3478"], "username": "u", "credential": "p"}]}

const USER_FILE := "user://net_config.json"

const DEFAULTS := {
	# PeerJS Cloud: the PeerJS project's free public signaling server. Any PeerServer works.
	"signaling": {"host": "0.peerjs.com", "port": 443, "secure": true, "path": "/", "key": "peerjs"},
	# Google's free STUN servers. No TURN relay yet (chosen 2026-10-22): players on very
	# strict networks may fail to connect until one is added here.
	"ice_servers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}],
	# Signaling ids are "<prefix>-<ROOMCODE>" for hosts, so codes don't clash with other apps.
	"id_prefix": "lancerautogm",
	"join_timeout_sec": 25.0,
}


static func load_config() -> Dictionary:
	var cfg: Dictionary = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(USER_FILE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_FILE))
		if parsed is Dictionary:
			cfg.merge(parsed, true)
		else:
			push_warning("%s is not valid JSON; using defaults." % USER_FILE)
	return cfg
