class_name UnitFactory
extends RefCounted
## Builds Units from lancer-data (frames, weapons, systems, mods) and checks loadouts.
##
## A loadout lists what goes in each of the frame's mounts, in the frame's mount order:
##   {"mounts": [{"weapons": ["mw_assault_rifle"], "mod": ""}, ...],
##    "systems": ["ms_pattern_a_smoke_charges", ...]}
## A pilot gives License Level, license ranks, talents and mech skills:
##   {"ll": 2, "licenses": {"mf_raleigh": 2}, "talents": {"t_...": 1},
##    "hull": 0, "agility": 0, "systems": 0, "engineering": 0}
## License keys are lancer-data license ids (the frame id, e.g. "mf_raleigh"); the license
## name ("Raleigh") also works.
##
## The built Unit carries copies of its weapon profiles in loadout["weapons"] (see Weapons),
## so the rules engine never needs ContentDB.

const REF_MOUNTS := "rules.json: mount_fittings"
const REF_SP := "glossary: System Points"
const REF_LICENSE := "lancer-data: license / license_level"
## One license rank per License Level, ranks I-III per license (Core p.31).
const REF_LICENSE_RANKS := "Core p.31 License ranks"
const MAX_LICENSE_RANK := 3
## How many weapons each mount holds (Core p.32); which sizes fit comes from rules.json.
## "Flex" holds one Main or two Auxiliary; Main/Aux holds Main + Aux or two Aux.
const MOUNT_SLOTS := {
	"Main": ["Main"],
	"Heavy": ["Heavy"],
	"Flex": ["Flex"],
	"Main/Aux": ["Main", "Auxiliary"],
	"Aux/Aux": ["Auxiliary", "Auxiliary"],
}
const NPC_TEMPLATES := "res://data/game/npc_templates.json"
const FRAME_EFFECTS := "res://data/game/frame_effects.json"
const GEAR_EFFECTS := "res://data/game/gear_effects.json"
const ACTIVATION_EFFECTS := "res://data/game/activation_effects.json"
const WEAPON_EFFECTS := "res://data/game/weapon_effects.json"
## lancer-data core_system active_bonuses ids -> the roll type they give Accuracy on.
const BONUS_ROLLS := {"attack": "attack", "check": "check", "save": "save", "tech_attack": "tech_attack"}


static func grit(ll: int) -> int:
	return ceili(ll / 2.0)  # glossary: GRIT (half LL, rounded up)


## Total SP: frame SP + GRIT + 1 per 2 SYSTEMS (glossary: System Points).
static func total_sp(frame: Dictionary, pilot: Dictionary) -> int:
	return int(frame.get("stats", {}).get("sp", 0)) + grit(int(pilot.get("ll", 0))) + int(pilot.get("systems", 0)) / 2


## Is this loadout legal on this frame? Collects every problem in `details`.
static func check_loadout(db: ContentDB, frame_id: String, loadout: Dictionary, pilot: Dictionary = {}) -> RuleResult:
	var problems: Array = []
	var frame := db.frame(frame_id)
	if frame.is_empty():
		return RuleResult.deny("Unknown frame '%s'." % frame_id, "")
	problems.append_array(check_pilot(db, pilot))
	_license(problems, frame, pilot)
	var fittings: Dictionary = db.rules.get("mount_fittings", {})
	var frame_mounts: Array = frame.get("mounts", [])
	var mounts: Array = loadout.get("mounts", [])
	if float(frame["stats"].get("size", 1)) > float(db.rules.get("max_frame_size", 3)):
		problems.append({"reason": "Frame is larger than the largest allowed size.", "rule_ref": "rules.json: max_frame_size"})
	if mounts.size() > frame_mounts.size():
		problems.append({"reason": "%s has only %d mounts." % [frame["name"], frame_mounts.size()], "rule_ref": REF_MOUNTS})
	var sp_used := 0
	var superheavy_mounts: Array[int] = []
	var empty_mounts: Array[int] = []
	for i in range(frame_mounts.size()):
		var mount_type: String = frame_mounts[i]
		var m: Dictionary = mounts[i] if i < mounts.size() else {}
		var ids: Array = m.get("weapons", [])
		if ids.is_empty():
			empty_mounts.append(i)
		var sizes: Array[String] = []
		for wid: String in ids:
			var w := db.weapon(wid)
			if w.is_empty():
				problems.append({"reason": "Unknown weapon '%s'." % wid, "rule_ref": ""})
				continue
			sizes.append(String(w.get("mount", "")))
			sp_used += int(w.get("sp", 0))
			_license(problems, w, pilot)
			if w.get("mount", "") == "Superheavy":
				superheavy_mounts.append(i)
		var why := _mount_problem(mount_type, sizes, fittings)
		if why != "":
			problems.append({"reason": "Mount %d (%s): %s" % [i + 1, mount_type, why], "rule_ref": REF_MOUNTS})
		var mod_id: String = m.get("mod", "")
		if mod_id != "":
			var mod := db.get_entry("mods", mod_id)
			if mod.is_empty():
				problems.append({"reason": "Unknown mod '%s'." % mod_id, "rule_ref": ""})
			else:
				sp_used += int(mod.get("sp", 0))
				_license(problems, mod, pilot)
				var w0 := db.weapon(String(ids[0])) if not ids.is_empty() else {}
				if w0.is_empty():
					problems.append({"reason": "Mount %d has a mod but no weapon to put it on." % (i + 1), "rule_ref": "tags: Mod"})
				elif not (mod.get("allowed_types", []) as Array).is_empty() and not (mod["allowed_types"] as Array).has(w0.get("type", "")):
					problems.append({"reason": "%s can't go on a %s." % [mod["name"], w0.get("type", "")], "rule_ref": "tags: Mod"})
				elif (mod.get("restricted_sizes", []) as Array).has(w0.get("mount", "")):
					problems.append({"reason": "%s can't go on a %s weapon." % [mod["name"], w0.get("mount", "")], "rule_ref": "tags: Mod"})
	# A Superheavy weapon needs a Heavy mount and one other mount (Core p.32): it takes up one
	# other mount, which must be left empty.
	if superheavy_mounts.size() > empty_mounts.size():
		problems.append({"reason": "A Superheavy weapon needs a Heavy mount plus one other empty mount.", "rule_ref": "Core p.32 Mounts"})
	var seen_unique := {}
	var ai_count := 0
	for sid: String in loadout.get("systems", []):
		var s := db.system(sid)
		if s.is_empty():
			problems.append({"reason": "Unknown system '%s'." % sid, "rule_ref": ""})
			continue
		sp_used += int(s.get("sp", 0))
		_license(problems, s, pilot)
		if _has_tag(s, "tg_unique"):
			if seen_unique.has(sid):
				problems.append({"reason": "%s is Unique: only one copy." % s["name"], "rule_ref": "tags: Unique"})
			seen_unique[sid] = true
		if _has_tag(s, "tg_ai"):
			ai_count += 1
	if ai_count > 1:
		problems.append({"reason": "Only one AI system can be installed.", "rule_ref": "tags: AI"})
	var sp := total_sp(frame, pilot)
	if sp_used > sp:
		problems.append({"reason": "Uses %d SP but this mech has %d." % [sp_used, sp], "rule_ref": REF_SP})
	if problems.is_empty():
		return RuleResult.allow()
	var r := RuleResult.deny(problems[0]["reason"], problems[0]["rule_ref"])
	r.details = problems
	return r


## Problems with the pilot itself: License Level in range, license ranks add up.
static func check_pilot(db: ContentDB, pilot: Dictionary) -> Array:
	var problems: Array = []
	var ll := int(pilot.get("ll", 0))
	var max_ll := int(db.rules.get("max_pilot_level", 12))
	if ll < 0 or ll > max_ll:
		problems.append({"reason": "License Level must be 0 to %d." % max_ll, "rule_ref": "rules.json: max_pilot_level"})
	var total := 0
	var licenses: Dictionary = pilot.get("licenses", {})
	for key: String in licenses:
		var rank := int(licenses[key])
		total += rank
		if rank < 1 or rank > MAX_LICENSE_RANK:
			problems.append({"reason": "%s license rank must be 1 to %d." % [key, MAX_LICENSE_RANK], "rule_ref": REF_LICENSE_RANKS})
	if total > ll:
		problems.append({"reason": "License ranks add up to %d, but a License Level %d pilot has only %d." % [total, ll, ll], "rule_ref": REF_LICENSE_RANKS})
	return problems


## Is a frame/weapon/system/mod unlocked for this pilot? GMS gear at license level 0 is
## always available; manufacturer gear needs that frame's license at its license_level;
## talent gear needs the talent rank.
static func license_problem(item: Dictionary, pilot: Dictionary) -> String:
	if item.get("talent_item", false):
		var talent := String(item.get("talent_id", ""))
		var need := int(item.get("talent_rank", 1))
		if int(pilot.get("talents", {}).get(talent, 0)) < need:
			return "%s needs talent %s rank %d." % [item.get("name", ""), talent, need]
		return ""
	var level := int(item.get("license_level", 0))
	var lic_id := String(item.get("license_id", ""))
	var gms: bool = item.get("source", "") == "GMS" or item.get("license", "") == "GMS"
	if gms and level == 0:
		return ""
	if lic_id == "":
		return "%s isn't installable gear (integrated or special equipment)." % item.get("name", "")
	# Frames are their own license (license_id = frame id) and have no "license" name field.
	var lic_name := String(item.get("license", item.get("name", lic_id)))
	var licenses: Dictionary = pilot.get("licenses", {})
	var rank := int(licenses.get(lic_id, licenses.get(lic_name, 0)))
	if rank < level:
		return "Needs %s license rank %d." % [lic_name, level]
	return ""


static func _license(problems: Array, item: Dictionary, pilot: Dictionary) -> void:
	var why := license_problem(item, pilot)
	if why != "":
		problems.append({"reason": why, "rule_ref": REF_LICENSE, "item": item.get("id", "")})


## "" if the weapon sizes fit the mount, else why not.
static func _mount_problem(mount_type: String, sizes: Array[String], fittings: Dictionary) -> String:
	if sizes.is_empty():
		return ""
	var slots: Array = MOUNT_SLOTS.get(mount_type, [])
	if slots.is_empty():
		return "unknown mount type"
	if mount_type == "Flex" and sizes.size() == 2:
		if sizes[0] == "Auxiliary" and sizes[1] == "Auxiliary":
			return ""
		return "a Flex mount holds one Main weapon or two Auxiliary weapons"
	if sizes.size() > slots.size():
		return "holds at most %d weapon(s)" % slots.size()
	var remaining := sizes.duplicate()
	for slot: String in slots:
		var fits: Array = fittings.get(slot, [])
		for j in range(remaining.size()):
			if fits.has(remaining[j]):
				remaining.remove_at(j)
				break
	if not remaining.is_empty():
		return "%s doesn't fit" % ", ".join(remaining)
	return ""


static func _has_tag(entry: Dictionary, tag_id: String) -> bool:
	for t: Dictionary in entry.get("tags", []):
		if t.get("id", "") == tag_id:
			return true
	return false


## A player mech from a frame and loadout. Doesn't check legality (call check_loadout).
## Mech skill and GRIT bonuses (Core p.34-35): HP + GRIT + 2/Hull, Repair Cap + 1 per 2 Hull,
## Evasion +1/Agility, Speed +1 per 2 Agility, E-Defense and Tech Attack +1/Systems, Heat Cap
## +1/Engineering, Save Target + GRIT, SP + GRIT + 1 per 2 Systems.
static func build_mech(db: ContentDB, id: String, frame_id: String, loadout: Dictionary, pilot: Dictionary = {}) -> Unit:
	var frame := db.frame(frame_id)
	var st: Dictionary = frame.get("stats", {})
	var u := Unit.new()
	u.id = id
	u.name = String(frame.get("name", frame_id))
	u.kind = Unit.KIND_MECH
	u.content_id = frame_id
	var g := grit(int(pilot.get("ll", 0)))
	u.hull = int(pilot.get("hull", 0))
	u.agility = int(pilot.get("agility", 0))
	u.systems = int(pilot.get("systems", 0))
	u.engineering = int(pilot.get("engineering", 0))
	u.grit = g
	u.size = float(st.get("size", 1))
	u.max_hp = int(st.get("hp", 0)) + g + 2 * u.hull
	u.hp = u.max_hp
	u.armor = int(st.get("armor", 0))
	u.evasion = int(st.get("evasion", 8)) + u.agility
	u.edef = int(st.get("edef", 8)) + u.systems
	u.heat_cap = int(st.get("heatcap", 0)) + u.engineering
	u.speed = int(st.get("speed", 4)) + u.agility / 2
	u.sensors = int(st.get("sensor_range", 10))
	u.save_target = int(st.get("save", 10)) + g
	u.tech_attack = int(st.get("tech_attack", 0)) + u.systems
	u.repairs = int(st.get("repcap", 0)) + u.hull / 2
	u.max_structure = int(st.get("structure", db.rules.get("base_structure", 4)))
	u.structure = u.max_structure
	u.max_stress = int(st.get("stress", db.rules.get("base_stress", 4)))
	u.stress = u.max_stress
	var weapons: Array = []
	var mounts: Array = []
	var frame_mounts: Array = frame.get("mounts", [])
	var given: Array = loadout.get("mounts", [])
	for i in range(frame_mounts.size()):
		var m: Dictionary = given[i] if i < given.size() else {}
		mounts.append({"mount": frame_mounts[i], "weapons": (m.get("weapons", []) as Array).duplicate(), "mod": m.get("mod", "")})
		var slot := 0
		for wid: String in m.get("weapons", []):
			var w := db.weapon(wid)
			if not w.is_empty():
				weapons.append(weapon_profile(w, "%d:%d" % [i, slot], i))
			slot += 1
	# Integrated mounts: the frame's own weapons, always included, never destroyed, removed or
	# modified (Core p.32).
	var integ := 0
	for wid: Variant in (frame.get("core_system", {}) as Dictionary).get("integrated", []):
		var w := db.weapon(String(wid))
		if w.is_empty():
			continue
		var prof := weapon_profile(w, "int:%d" % integ, -1)
		prof["integrated"] = true
		# Weapons fired only through their own rule (Apocalypse Rail: "skirmish": false; Latch
		# Drone: "can't make normal attacks").
		if w.get("skirmish", true) == false or "make normal attacks" in String(w.get("effect", "")):
			prof["no_attack"] = true
		weapons.append(prof)
		integ += 1
	var systems: Array = []
	var n := 0
	for sid: String in loadout.get("systems", []):
		var s := db.system(sid)
		if not s.is_empty():
			systems.append({"key": "s%d" % n, "id": sid, "name": s.get("name", sid), "tags": (s.get("tags", []) as Array).duplicate(true)})
			n += 1
	u.loadout = {"frame": frame_id, "mounts": mounts, "weapons": weapons, "systems": systems}
	_frame_effects(u, frame)
	# Passive effects of systems, core bonuses and talents (data/game/gear_effects.json).
	var gear_ids: Array = []
	for s: Dictionary in systems:
		gear_ids.append(s["id"])
	gear_ids.append_array(pilot.get("core_bonuses", []))
	_add_gear_effects(u, gear_ids, pilot.get("talents", {}))
	TalentRules.adjust_weapons(u)
	u.loadout["abilities"] = _abilities(db, u, frame, loadout.get("systems", []), pilot.get("talents", {}))
	if (frame_effects_data().get(frame_id, {}) as Dictionary).get("orochi_choice", false):
		# Hydra: one OROCHI drone accompanies it; Full Deployment brings all four.
		for a: Dictionary in u.loadout["abilities"]:
			if a["source_key"] == "core" and a["kind"] == "deploy":
				a["orochi"] = true
		if loadout.has("orochi"):
			u.loadout["orochi"] = String(loadout["orochi"])
	return u


static var _activation_data: Dictionary = {}


static func activation_data() -> Dictionary:
	if _activation_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTIVATION_EFFECTS))
		_activation_data = d if d is Dictionary else {}
	return _activation_data


## Activated abilities from lancer-data (see Abilities): system and weapon actions and
## deployables, core system actions, unautomated trait actions, talent actions.
static func _abilities(db: ContentDB, u: Unit, frame: Dictionary, system_ids: Array, talents: Dictionary) -> Array:
	var out: Array = []
	var i := 0
	for sid: String in system_ids:
		var s := db.system(sid)
		if not s.is_empty():
			_add_source(out, s, "s%d" % i, s.get("name", sid), sid)
			i += 1
	for w: Dictionary in u.loadout.get("weapons", []):
		var raw := db.weapon(String(w.get("id", "")))
		if not raw.is_empty():
			var src := raw
			if (w.get("rules", {}) as Dictionary).has("spin_up"):
				# Spin Up as a quick action, end it as a protocol (WeaponRules).
				src = raw.duplicate(true)
				var acts: Array = (src.get("actions", []) as Array).duplicate(true)
				acts.append({"name": "Spin Up " + String(raw.get("name", "")), "activation": "Quick", "detail": "Spin up the barrels: the Spin-Up profile.", "ops": [{"op": "spin_up", "weapon": w["key"]}]})
				acts.append({"name": "Spin Down " + String(raw.get("name", "")), "activation": "Protocol", "detail": "End Spin-Up mode.", "ops": [{"op": "spin_down", "weapon": w["key"]}]})
				src["actions"] = acts
			_add_source(out, src, "w:" + String(w["key"]), raw.get("name", ""), String(raw.get("id", "")), true)
	var core: Dictionary = frame.get("core_system", {})
	var core_src := {"actions": [], "deployables": core.get("deployables", [])}
	for a: Dictionary in core.get("passive_actions", []):
		core_src["actions"].append(a)
	for a: Dictionary in core.get("active_actions", []):
		var c := a.duplicate(true)
		c["requires_core_active"] = true
		core_src["actions"].append(c)
	# Our own extra core actions (Drake: deactivate Fortress as a protocol).
	for a: Dictionary in (frame_effects_data().get(frame.get("id", ""), {}) as Dictionary).get("core_actions", []):
		var c := a.duplicate(true)
		c["requires_core_active"] = true
		core_src["actions"].append(c)
	_add_source(out, core_src, "core", String(core.get("name", "Core")), String(frame.get("id", "")))
	var automated: Dictionary = {}
	for t: Dictionary in u.loadout.get("traits", []):
		automated[t["name"]] = t.get("automated", false)
	for t: Dictionary in frame.get("traits", []):
		var src := t
		if automated.get(t.get("name", ""), false):
			# Automated traits keep only the actions you choose to take (Combat Repair).
			src = t.duplicate(true)
			src["actions"] = (t.get("actions", []) as Array).filter(func(a: Dictionary) -> bool: return Abilities.COSTS.has(String(a.get("activation", ""))))
		_add_source(out, src, "trait:" + String(t.get("name", "")), String(t.get("name", "")), String(frame.get("id", "")))
	for tid: String in talents:
		var tal := db.get_entry("talents", tid)
		for r in range(mini(int(talents[tid]), (tal.get("ranks", []) as Array).size())):
			var rank: Dictionary = tal["ranks"][r]
			_add_source(out, rank, "talent:%s:%d" % [tid, r + 1], "%s %d" % [tal.get("name", tid), r + 1], tid)
	return out


static func _add_source(out: Array, src: Dictionary, key: String, name: String, data_id: String, weapon: bool = false) -> void:
	var data := activation_data()
	var tag_freq := ""
	for tag: Dictionary in src.get("tags", []):
		if tag.get("id", "") == "tg_round":
			tag_freq = "%s/round" % str(tag.get("val", 1))
		elif tag.get("id", "") == "tg_turn":
			tag_freq = "%s/turn" % str(tag.get("val", 1))
	var n := 0
	var actions: Array = (src.get("actions", []) as Array).duplicate()
	actions.append_array(data.get("actions:%s" % data_id, []))  # our extra actions (Detonate)
	for a: Dictionary in actions:
		var act := String(a.get("activation", "") if a.get("activation") != null else "")
		if weapon and act == "":
			continue
		var aname := String(a.get("name", name) if a.get("name") != null else name)
		var ops: Variant = a.get("ops") if a.has("ops") else data.get("%s:%s" % [data_id, aname])
		if ops is Dictionary:
			# {"activation": ..., "ops": [...]}: lancer-data gives no activation (Thermal Grenade).
			act = String(ops.get("activation", act))
			ops = ops.get("ops", [])
		out.append({"key": "%s/a%d" % [key, n], "name": aname, "source_key": key, "source_name": name,
			"kind": "action", "activation": act, "frequency": a.get("frequency", tag_freq),
			"trigger": a.get("trigger", ""), "detail": a.get("detail", ""), "range": a.get("range", []),
			"requires_core_active": a.get("requires_core_active", false),
			"ops": ops if ops is Array else [], "automated": ops is Array})
		n += 1
	var m := 0
	for raw: Dictionary in src.get("deployables", []):
		# Our corrections and extras for a deployable (activation_effects "deploy:<id>:<name>").
		var d := raw.duplicate(true)
		var over: Variant = data.get("deploy:%s:%s" % [data_id, raw.get("name", "")])
		if over is Dictionary:
			d.merge(over, true)
			if over.get("skip", false):
				m += 1
				continue  # used through an action instead (Clamp Bombs)
		var dkey := "%s/d%d" % [key, m]
		out.append({"key": dkey, "name": "Deploy " + String(d.get("name", "")), "source_key": key, "source_name": name,
			"kind": "deploy", "activation": String(d.get("activation", "Quick")) if String(d.get("activation", "Quick")) != "None" else "Quick",
			"frequency": "", "detail": d.get("detail", ""), "range": d.get("range", []), "deployable": d.duplicate(true),
			"instances": int(d.get("instances", 1)), "ops": [], "automated": true})
		if d.has("recall"):
			out.append({"key": "%s/r%d" % [key, m], "name": "Recall " + String(d.get("name", "")), "source_key": key, "source_name": name,
				"kind": "recall", "activation": String(d["recall"]), "frequency": "", "recalls": dkey, "detail": "", "ops": [], "automated": true})
		m += 1


static var _gear_data: Dictionary = {}


static func gear_effects_data() -> Dictionary:
	if _gear_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEAR_EFFECTS))
		_gear_data = d if d is Dictionary else {}
	return _gear_data


## Adds encoded effects for gear ids (systems, core bonuses, pilot gear) and talents
## ({talent_id: rank}; ranks are cumulative). Size steps apply at once (Fomorian Frame).
static func _add_gear_effects(u: Unit, ids: Array, talents: Dictionary) -> void:
	var data := gear_effects_data()
	var effects: Array = u.loadout.get("effects", [])
	var add := func(list: Array, source: String) -> void:
		for e: Dictionary in list:
			var copy := e.duplicate(true)
			copy["label"] = source
			copy["rule_ref"] = "lancer-data: " + source
			effects.append(copy)
			if copy["kind"] == "size_step":
				u.size = minf(3.0, 1.0 if u.size < 1.0 else u.size + 1.0)
			if copy["kind"] == "hp_bonus":
				u.max_hp += int(copy.get("value", 0))  # Personalizations
				u.hp = u.max_hp
	for id: String in ids:
		if data.get(id) is Array:
			add.call(data[id], id)
	for t: String in talents:
		var ranks: Variant = data.get(t)
		if ranks is Dictionary:
			for r in range(1, int(talents[t]) + 1):
				if (ranks as Dictionary).has(str(r)):
					add.call(ranks[str(r)], "%s rank %d" % [t, r])
	u.loadout["effects"] = effects


static var _frame_data: Dictionary = {}


static func frame_effects_data() -> Dictionary:
	if _frame_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAME_EFFECTS))
		_frame_data = d if d is Dictionary else {}
	return _frame_data


## Traits (always on) and the core system (switched on with the "core_power" action), from
## data/game/frame_effects.json plus lancer-data's own core active_bonuses. Each trait and
## the core say whether the engine automates them; "manual" ones keep their text for the UI.
static func _frame_effects(u: Unit, frame: Dictionary) -> void:
	var data: Dictionary = frame_effects_data().get(frame.get("id", ""), {})
	var trait_data: Dictionary = data.get("traits", {})
	var effects: Array = []
	var traits: Array = []
	for t: Dictionary in frame.get("traits", []):
		var name := String(t.get("name", ""))
		var enc: Variant = trait_data.get(name, "manual")
		# {"effects": [...], "manual": "what the table still applies"}: partly automated.
		var note := ""
		if enc is Dictionary:
			note = String(enc.get("manual", ""))
			enc = enc.get("effects", [])
		var automated := enc is Array
		traits.append({"name": name, "text": t.get("description", ""), "automated": automated, "manual_note": note})
		if automated:
			for e: Dictionary in enc:
				var copy := e.duplicate(true)
				copy["label"] = name
				copy["rule_ref"] = "frames: %s, %s" % [frame.get("name", ""), name]
				effects.append(copy)
				if copy["kind"] == "hover":
					u.flight = "hover"
	var core: Dictionary = frame.get("core_system", {})
	var core_name := String(core.get("name", ""))
	var core_effects: Array = []
	for b: Dictionary in core.get("active_bonuses", []):
		if BONUS_ROLLS.has(b.get("id", "")) and b.has("accuracy"):
			core_effects.append({"kind": "accuracy", "on": BONUS_ROLLS[b["id"]], "value": int(b["accuracy"])})
	var enc_core: Variant = data.get("core", "manual")
	var core_note := ""
	if enc_core is Dictionary:
		core_note = String(enc_core.get("manual", ""))
		enc_core = enc_core.get("effects", [])
	if enc_core is Array:
		core_effects.append_array((enc_core as Array).duplicate(true))
	var core_ops: Array = (data.get("core_ops", []) as Array).duplicate(true)
	if not core_ops.is_empty():
		enc_core = core_effects
	for e: Dictionary in core_effects:
		e["label"] = core_name
		e["rule_ref"] = "frames: %s core system" % frame.get("name", "")
	# Always-on core passives (Manticore: 1/round energy when it takes heat).
	for e: Dictionary in data.get("core_passive", []):
		var copy := e.duplicate(true)
		copy["label"] = String(core.get("passive_name", core_name))
		copy["rule_ref"] = "frames: %s core system" % frame.get("name", "")
		effects.append(copy)
	u.loadout["effects"] = effects
	u.loadout["traits"] = traits
	u.loadout["core"] = {"name": core_name, "power": core.get("active_name", ""), "activation": core.get("activation", "Quick"),
		"text": core.get("active_effect", ""), "effects": core_effects, "ops": core_ops, "automated": enc_core is Array,
		"manual_note": core_note, "target": (data.get("core_target", {}) as Dictionary).duplicate(true)}
	if data.get("core_sections", false):
		u.loadout["core"]["sections"] = true
	if data.get("core_deploy_all", false):
		u.loadout["core"]["deploy_all"] = true
	if data.has("core_zone"):
		u.loadout["core"]["zone"] = (data["core_zone"] as Dictionary).duplicate(true)
	# One Core Power per mission, recovered by a Full Repair (Core p.32, 82).
	u.counters["core_power"] = 1


## The fields of a lancer-data weapon the rules use. Weapons with several profiles use the
## first one (choosing a profile isn't supported yet).
static func _with_profile(w: Dictionary, i: int) -> Dictionary:
	var src := w.duplicate(true)
	src.erase("profiles")
	src.merge(w["profiles"][i], true)
	return src


static func weapon_profile(w: Dictionary, key: String, mount: int) -> Dictionary:
	var src := w
	if w.has("profiles") and not (w["profiles"] as Array).is_empty():
		src = w.duplicate(true)
		src.merge(w["profiles"][0], true)
	var out := {"key": key, "id": w.get("id", ""), "name": w.get("name", ""), "mount": mount,
		"size": w.get("mount", ""), "type": w.get("type", ""),
		"damage": (src.get("damage", []) as Array).duplicate(true),
		"range": (src.get("range", []) as Array).duplicate(true),
		"tags": (src.get("tags", []) as Array).duplicate(true)}
	# Structured on-hit / on-crit conditions and our own rules (WeaponRules).
	for field in ["on_hit", "on_crit"]:
		if src.get(field) is Dictionary:
			out["data_" + field] = (src[field] as Dictionary).duplicate(true)
	var r: Variant = weapon_effects_data().get(String(w.get("id", "")))
	if r is Dictionary:
		out["rules"] = (r as Dictionary).duplicate(true)
		if r.get("no_attack", false):
			out["no_attack"] = true  # fired only through its own rule (Autogun)
	if key != "" and w.has("profiles") and (w["profiles"] as Array).size() > 1:
		var all: Array = []
		for i in range((w["profiles"] as Array).size()):
			all.append(weapon_profile(_with_profile(w, i), "", -1))
		out["profiles"] = all
		out["profile"] = 0
	return out


static var _weapon_data: Dictionary = {}


static func weapon_effects_data() -> Dictionary:
	if _weapon_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_EFFECTS))
		_weapon_data = d if d is Dictionary else {}
	return _weapon_data


## Hand-written NPC templates (data/game/npc_templates.json). Not official NPC data.
static func npc_templates(path: String = NPC_TEMPLATES) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## An NPC from a template: plain stats plus weapons with their own attack bonus. Tiered
## templates ("tiers": {stat: [t1, t2, t3]}) take the values for `tier` (1-3), including
## weapon damage given as [t1, t2, t3]. Feature effects go into loadout["effects"].
static func build_npc(id: String, template: Dictionary, tier: int = 1) -> Unit:
	var u := Unit.new()
	u.id = id
	u.kind = Unit.KIND_NPC
	u.side = "enemies"
	u.name = String(template.get("name", id))
	u.content_id = String(template.get("id", ""))
	tier = clampi(tier, 1, 3)
	var stats := template.duplicate(true)
	var tiers: Dictionary = template.get("tiers", {})
	for key: String in tiers:
		stats[key] = tiers[key][tier - 1]
	for key in ["size", "armor", "evasion", "edef", "speed", "sensors", "save_target",
			"tech_attack", "hull", "agility", "systems", "engineering", "flight"]:
		if stats.has(key):
			u.set(key, Unit._coerce(u.get(key), stats[key]))
	u.max_hp = int(stats.get("hp", 10))
	u.hp = u.max_hp
	u.heat_cap = int(stats.get("heat_cap", 0))
	u.max_structure = int(template.get("structure", 1))
	u.structure = u.max_structure
	u.max_stress = int(template.get("stress", 1))
	u.stress = u.max_stress
	u.resistances = (template.get("resistances", []) as Array).duplicate()
	var weapons: Array = []
	var i := 0
	for w: Dictionary in template.get("weapons", []):
		var p := w.duplicate(true)
		p["key"] = "w%d" % i
		p["mount"] = -1
		p["attack_bonus"] = int(w.get("attack_bonus", stats.get("attack_bonus", 0)))
		for d: Dictionary in p.get("damage", []):
			if d.get("val") is Array:
				d["val"] = d["val"][tier - 1]
		weapons.append(p)
		i += 1
	var effects: Array = []
	var traits: Array = []
	var abilities: Array = []
	var fi := 0
	for f: Dictionary in template.get("features", []):
		if f.has("activation"):
			abilities.append({"key": "f%d/a0" % fi, "name": f.get("name", ""), "source_key": "f%d" % fi, "source_name": f.get("name", ""),
				"kind": "action", "activation": f["activation"], "frequency": f.get("frequency", ""), "detail": f.get("text", ""),
				"ops": [], "automated": false})
		fi += 1
		var enc: Variant = f.get("effects", "manual")
		traits.append({"name": f.get("name", ""), "text": f.get("text", ""), "automated": enc is Array})
		if enc is Array:
			for e: Dictionary in enc:
				var copy := e.duplicate(true)
				copy["label"] = f.get("name", "")
				copy["rule_ref"] = "data/game/npc_templates.json (placeholder)"
				effects.append(copy)
	u.loadout = {"weapons": weapons, "systems": [], "effects": effects, "traits": traits, "abilities": abilities, "tier": tier,
		"role": template.get("role", ""), "placeholder": template.get("placeholder", false)}
	return u


## A pilot on foot from rules.json base stats and pilot gear weapons (pilot_gear.json).
## pilot: {"name", "ll", "weapons": ["pg_light_a_c", ...]}
static func build_pilot(db: ContentDB, id: String, pilot: Dictionary, side: String = "players", controller: String = "gm") -> Unit:
	var r := db.rules
	var base := {"hp": r.get("base_pilot_hp", 6), "evasion": r.get("base_pilot_evasion", 10),
		"edef": r.get("base_pilot_edef", 10), "speed": r.get("base_pilot_speed", 4),
		"sensors": r.get("base_pilot_sensors", 5), "save_target": r.get("base_pilot_save_target", 10)}
	var p := Pilots.make_pilot(id, String(pilot.get("name", id)), side, controller, grit(int(pilot.get("ll", 0))), base)
	var weapons: Array = []
	var i := 0
	for gid: String in pilot.get("weapons", []):
		var g := db.get_entry("pilot_gear", gid)
		if g.is_empty():
			continue
		var prof := weapon_profile(g, "p%d" % i, -1)
		# Pilot gear has no weapon type; a weapon with only a Threat is melee.
		prof["type"] = "Melee" if Weapons.range_value(prof, "Range") == 0 else "Ranged"
		prof["size"] = "Pilot"
		weapons.append(prof)
		i += 1
	p.loadout = {"weapons": weapons, "systems": [], "effects": []}
	_add_gear_effects(p, pilot.get("gear", []), {})
	return p
