class_name StoryData
extends RefCounted
## Checks the story data so a typo in a scene shows up in the tests, not mid-campaign:
## every "next" goes somewhere, every effect and condition is one we know, every "@pool"
## exists, triggers and reserves are real ids, menus offer at most 6 choices at once.

const EFFECTS := ["set_flag", "add_flag", "clear_flag", "standing", "reserve", "reserve_table", "contact", "obligation",
	"pay_obligation", "hook", "harm", "rest", "npc_dead", "log", "start_combat", "downtime", "ui", "help", "deal"]
const CONDITIONS := ["all", "any", "not", "flag", "var", "standing", "alive", "dead", "npc_alive", "trigger", "squad_trigger",
	"background", "reserve", "phase", "downtime_left", "last_outcome", "ll_min", "ll_max", "contact", "obligation",
	"missions_min", "hub_has", "role", "hook", "squad_reserve", "deal"]


## Problems in all scenes and downtime data, as plain strings (empty = all good).
static func lint() -> Array:
	var problems: Array = []
	var skills := _ids("res://data/lancer-data/skills.json")
	var reserves := _ids("res://data/lancer-data/reserves.json")
	reserves["custom"] = true
	var pools := StoryText.pools()
	for sid: String in Dialogue.scene_ids():
		var sc := Dialogue.scene(sid)
		var nodes: Dictionary = sc.get("nodes", {})
		if not nodes.has(str(sc.get("start", ""))):
			problems.append("%s: start node '%s' missing" % [sid, sc.get("start", "")])
		for nid: String in nodes:
			var where := "%s/%s" % [sid, nid]
			var n: Dictionary = nodes[nid]
			_line(problems, where, n.get("line", ""), pools)
			_next(problems, where, n.get("next", null), nodes)
			for b: Dictionary in n.get("branch", []):
				_next(problems, where, b.get("next"), nodes)
				_cond(problems, where, b.get("if"))
			_effects(problems, where, n.get("effects", []), reserves)
			var choices: Array = n.get("choices", [])
			for c: Dictionary in choices:
				var cw := "%s choice %s" % [where, c.get("id", "?")]
				_line(problems, cw, c.get("text", ""), pools)
				_cond(problems, cw, c.get("condition"))
				_effects(problems, cw, c.get("effects", []), reserves)
				if c.has("trigger") and not skills.has(str(c["trigger"])):
					problems.append("%s: unknown trigger %s" % [cw, c["trigger"]])
				if not c.has("check") and not bool(c.get("end", false)):
					_next(problems, cw, c.get("next"), nodes)
				if c.has("check"):
					var chk: Dictionary = c["check"]
					for s: Variant in chk.get("skills", []):
						if not skills.has(str(s)):
							problems.append("%s: unknown trigger %s" % [cw, s])
					_next(problems, cw, chk.get("success", c.get("next")), nodes)
					_next(problems, cw, chk.get("fail", c.get("next")), nodes)
					_effects(problems, cw, chk.get("success_effects", []), reserves)
					_effects(problems, cw, chk.get("fail_effects", []), reserves)
	for aid: String in Downtime.action_ids():
		if Downtime.book(aid).is_empty():
			problems.append("downtime: %s is not in lancer-data" % aid)
		var cfg := Downtime.action_cfg(aid)
		for t: Variant in cfg.get("triggers", []):
			if not skills.has(str(t)):
				problems.append("downtime %s: unknown trigger %s" % [aid, t])
		for band: String in cfg.get("bands", {}):
			var b: Dictionary = cfg["bands"][band]
			_effects(problems, "downtime %s/%s" % [aid, band], b.get("effects", []), reserves)
			for o: Dictionary in b.get("options", []):
				_effects(problems, "downtime %s/%s/%s" % [aid, band, o.get("id", "")], o.get("effects", []), reserves)
	for role: String in NpcGen.roles():
		var r: Dictionary = NpcGen.roles()[role]
		if Dialogue.scene(str(r.get("scene", ""))).is_empty():
			problems.append("role %s: no scene %s" % [role, r.get("scene", "")])
		for rid: Variant in (r.get("offers", []) as Array) + (r.get("trusted_offers", []) as Array):
			if not reserves.has(str(rid)):
				problems.append("role %s: unknown reserve %s" % [role, rid])
	return problems


static func _line(problems: Array, where: String, src: Variant, pools: Dictionary) -> void:
	var lines: Array = src if src is Array else [src]
	for l: Variant in lines:
		if str(l).begins_with("@") and not pools.has(str(l).substr(1)):
			problems.append("%s: no line pool %s" % [where, l])


static func _next(problems: Array, where: String, nxt: Variant, nodes: Dictionary) -> void:
	if nxt != null and str(nxt) != "" and not nodes.has(str(nxt)):
		problems.append("%s: next '%s' doesn't exist" % [where, nxt])


static func _cond(problems: Array, where: String, c: Variant) -> void:
	if c == null:
		return
	if c is Array:
		for x: Variant in c:
			_cond(problems, where, x)
		return
	var d: Dictionary = c
	var known := false
	for k: String in d:
		if CONDITIONS.has(k):
			known = true
	if not known:
		problems.append("%s: unknown condition %s" % [where, d])
	for k in ["all", "any"]:
		if d.has(k):
			_cond(problems, where, d[k])
	if d.has("not"):
		_cond(problems, where, d["not"])


static func _effects(problems: Array, where: String, effects: Array, reserves: Dictionary) -> void:
	for e: Dictionary in effects:
		var known := false
		for k: String in e:
			if EFFECTS.has(k):
				known = true
		if not known:
			problems.append("%s: unknown effect %s" % [where, e])
		if e.has("reserve") and not str(e["reserve"]).begins_with("$") and not reserves.has(str(e["reserve"])):
			problems.append("%s: unknown reserve %s" % [where, e["reserve"]])
		if e.has("hook") and not str(e["hook"]).begins_with("$") and not MissionHooks.data().get("templates", {}).has(str(e["hook"])):
			problems.append("%s: unknown hook %s" % [where, e["hook"]])


static func _ids(path: String) -> Dictionary:
	var out := {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	for x: Dictionary in (data if data is Array else []):
		out[str(x["id"])] = true
	return out
