class_name BuilderModel
extends RefCounted
## The pilot and mech builder without any UI. Every choice is checked live: a change that would
## make the build illegal is refused with the reason, and option lists say for each item
## whether it can be picked and, if not, why. Legality comes from UnitFactory (mounts, SP,
## licenses, License Level) plus the pilot's point budgets below.
##
## Pilot progression (Core p.18 "Leveling Up", p.35 core bonuses; starting numbers from
## rules.json): skill trigger points 4 + LL (a trigger is +2 per rank, up to +6), talent ranks
## 3 + LL (rank 1-3), mech skill (HASE) points 2 + LL (max 6 each), license ranks = LL, a core
## bonus at every third LL (3, 6, 9, 12). Core bonuses from a manufacturer other than GMS need
## 3 more license ranks with that manufacturer for each one taken (1st: 3, 2nd: 6...), spread
## over any of its licenses.
##
## Points spent at earlier License Levels stay spent (Campaign.level_up records them in
## pilot["locked"]). At each LL increase the pilot may make one reallocation (Core p.18): move
## all ranks from one talent to another, all ranks from one license to another, or swap one
## core bonus for another they qualify for. A license move that breaks a core bonus's
## requirement means that bonus must be replaced.
##
## Works on a copy of the pilot record (Compcon layout); `pilot` is the edited version.

signal changed

const HASE := ["hull", "agility", "systems", "engineering"]
## How many weapons each mount type holds (UnitFactory.MOUNT_SLOTS).
const SLOTS := {"Main": 1, "Heavy": 1, "Flex": 2, "Main/Aux": 2, "Aux/Aux": 2}
const REF := "Core p.18: Leveling Up"
const REF_CORE_BONUS := "Core p.35: Core Bonuses"

var db: ContentDB
var pilot: Dictionary
var mech_index := 0
var _quiet := false  # previewing an option: don't announce changes


func _init(content: ContentDB, pilot_record: Dictionary) -> void:
	db = content
	pilot = pilot_record.duplicate(true)
	for key in ["skills", "talents", "licenses"]:
		if not pilot.get(key) is Dictionary:
			pilot[key] = {}
	if not pilot.get("core_bonuses") is Array:
		pilot["core_bonuses"] = []
	if not pilot.get("mechs") is Array:
		pilot["mechs"] = []
	for i in range(pilot["mechs"].size()):
		if pilot["mechs"][i]["id"] == pilot.get("active_mech", ""):
			mech_index = i


func mech() -> Dictionary:
	return pilot["mechs"][mech_index] if mech_index < pilot["mechs"].size() else {}


func ll() -> int:
	return int(pilot.get("ll", 0))


# --- Budgets and problems ----------------------------------------------------------------

## {skills, talents, hase, licenses, core_bonuses: {used, max}}
func budgets() -> Dictionary:
	var r := db.rules
	return {
		"skills": {"used": _sum(pilot["skills"]), "max": int(r.get("minimum_pilot_skills", 4)) + ll()},
		"talents": {"used": _sum(pilot["talents"]), "max": int(r.get("minimum_pilot_talents", 3)) + ll()},
		"hase": {"used": _hase_total(), "max": int(r.get("minimum_mech_skills", 2)) + ll()},
		"licenses": {"used": _sum(pilot["licenses"]), "max": ll()},
		"core_bonuses": {"used": pilot["core_bonuses"].size(), "max": ll() / 3},
	}


## SP used and available on the current mech.
func sp() -> Dictionary:
	var m := mech()
	var used := 0
	for mt: Dictionary in m.get("loadout", {}).get("mounts", []):
		for wid: String in mt.get("weapons", []):
			used += int(db.weapon(wid).get("sp", 0))
		if str(mt.get("mod", "")) != "":
			used += int(db.get_entry("mods", str(mt["mod"])).get("sp", 0))
	for sid: String in m.get("loadout", {}).get("systems", []):
		used += int(db.system(sid).get("sp", 0))
	return {"used": used, "max": UnitFactory.total_sp(db.frame(str(m.get("frame", ""))), pilot)}


## Everything illegal about the build right now, in plain words.
func problems() -> Array:
	return _problems(pilot, mech_index)


func is_legal() -> bool:
	return problems().is_empty()


# --- Pilot changes (each returns "" or why it's refused) ---------------------------------

## License Level can always change; lowering it may leave points overspent (shown in problems).
func set_ll(level: int) -> String:
	if level < 0 or level > int(db.rules.get("max_pilot_level", 12)):
		return "License Level goes from 0 to %d." % int(db.rules.get("max_pilot_level", 12))
	pilot["ll"] = level
	_changed()
	return ""


func set_skill(id: String, rank: int) -> String:
	if db.get_entry("skills", id).is_empty():
		return "Unknown skill trigger."
	return _try(func(p: Dictionary) -> void: _set_rank(p["skills"], id, rank))


func set_talent(id: String, rank: int) -> String:
	if db.get_entry("talents", id).is_empty():
		return "Unknown talent."
	return _try(func(p: Dictionary) -> void: _set_rank(p["talents"], id, rank))


func set_license(frame_id: String, rank: int) -> String:
	if db.frame(frame_id).is_empty():
		return "Unknown license."
	return _try(func(p: Dictionary) -> void: _set_rank(p["licenses"], frame_id, rank))


func set_hase(key: String, value: int) -> String:
	if not key in HASE:
		return "Unknown mech skill."
	return _try(func(p: Dictionary) -> void: p[key] = value)


func toggle_core_bonus(id: String) -> String:
	if db.get_entry("core_bonuses", id).is_empty():
		return "Unknown core bonus."
	return _try(func(p: Dictionary) -> void:
		var list: Array = p["core_bonuses"]
		if list.has(id):
			list.erase(id)
		else:
			list.append(id))


# --- Reallocation (Core p.18) ------------------------------------------------------------

## True if this pilot gained a License Level and hasn't used its one reallocation yet.
func can_reallocate() -> bool:
	return bool(pilot.get("realloc_pending", false))


## One reallocation per LL increase. kind: "talent" (move all ranks from one talent to one you
## don't have), "license" (move all ranks from one license to one you don't have) or
## "core_bonus" (swap one for another you qualify for). Returns "" or why not.
func reallocate(kind: String, from_id: String, to_id: String) -> String:
	if not can_reallocate():
		return "You can reallocate once each time the pilot gains a License Level (Core p.18)."
	var key: String = {"talent": "talents", "license": "licenses"}.get(kind, "")
	match kind:
		"talent", "license":
			var have: Dictionary = pilot[key]
			if int(have.get(from_id, 0)) <= 0:
				return "Pick a %s the pilot has." % kind
			if have.has(to_id):
				return "Move the ranks to a %s the pilot doesn't have yet." % kind
			if (db.get_entry("talents", to_id) if kind == "talent" else db.frame(to_id)).is_empty():
				return "Unknown %s." % kind
			var why := _try(func(p: Dictionary) -> void:
				_move_rank(p[key], from_id, to_id)
				var locked: Dictionary = p.get("locked", {}).get(key, {})
				_move_rank(locked, from_id, to_id),
				func(w: String) -> bool: return kind == "license" and "core bonus" in w)
			if why == "":
				pilot["realloc_pending"] = false
			return why
		"core_bonus":
			if not pilot["core_bonuses"].has(from_id):
				return "Pick a core bonus the pilot has."
			if pilot["core_bonuses"].has(to_id) or db.get_entry("core_bonuses", to_id).is_empty():
				return "Pick a core bonus the pilot doesn't have."
			var why := _try(func(p: Dictionary) -> void:
				_swap(p["core_bonuses"], from_id, to_id)
				_swap(p.get("locked", {}).get("core_bonuses", []), from_id, to_id))
			if why == "":
				pilot["realloc_pending"] = false
			return why
	return "Choose talent, license or core bonus."


func _move_rank(d: Dictionary, from_id: String, to_id: String) -> void:
	if d.has(from_id):
		var talent := db.get_entry("talents", to_id)
		var cap := (talent.get("ranks", []) as Array).size() if not talent.is_empty() else UnitFactory.MAX_LICENSE_RANK
		d[to_id] = mini(int(d[from_id]), maxi(cap, 1))
		d.erase(from_id)


static func _swap(list: Array, from_id: String, to_id: String) -> void:
	var i := list.find(from_id)
	if i >= 0:
		list[i] = to_id


## Spent points can't be taken back (Core p.18), except through reallocation.
func _locked_problems(p: Dictionary) -> Array:
	var out: Array = []
	var locked: Dictionary = p.get("locked", {})
	if locked.is_empty():
		return out
	for pair in [["skills", "skill trigger"], ["talents", "talent"], ["licenses", "license"]]:
		var was: Dictionary = locked.get(pair[0], {})
		for id: String in was:
			if int(p[pair[0]].get(id, 0)) < int(was[id]):
				var name := str((db.get_entry("frames", id) if pair[0] == "licenses" else db.get_entry(pair[0], id)).get("name", id))
				var tail := " (or use this level's reallocation)" if pair[0] != "skills" and can_reallocate() else ""
				out.append("%s ranks were spent at an earlier License Level and stay spent%s." % [name, tail])
	for k in HASE:
		if int(p.get(k, 0)) < int(locked.get("hase", {}).get(k, 0)):
			out.append("%s points were spent at an earlier License Level and stay spent." % k.capitalize())
	for cb: String in locked.get("core_bonuses", []):
		if not p["core_bonuses"].has(cb) and not _core_bonus_broken(p, cb):
			out.append("%s was taken at an earlier License Level; swap it with this level's reallocation instead." % db.get_entry("core_bonuses", cb).get("name", cb))
	return out


## A core bonus whose manufacturer license requirement is no longer met (after a license
## reallocation): it must be replaced, so dropping it is allowed.
func _core_bonus_broken(p: Dictionary, cb: String) -> bool:
	var src := str(db.get_entry("core_bonuses", cb).get("source", "GMS"))
	if src == "GMS":
		return false
	var count := 1
	for other: String in p["core_bonuses"]:
		if str(db.get_entry("core_bonuses", other).get("source", "")) == src:
			count += 1
	var ranks := 0
	for fid: String in p["licenses"]:
		if db.frame(fid).get("source", "") == src:
			ranks += int(p["licenses"][fid])
	return ranks < 3 * count


# --- Mech changes ------------------------------------------------------------------------

## Switches the mech's frame. The mounts are emptied (they differ between frames); systems stay.
func set_frame(frame_id: String) -> String:
	var frame := db.frame(frame_id)
	if frame.is_empty():
		return "Unknown frame."
	return _try(func(p: Dictionary) -> void:
		var m: Dictionary = p["mechs"][mech_index]
		m["frame"] = frame_id
		var mounts: Array = []
		for _t: Variant in frame.get("mounts", []):
			mounts.append({"weapons": [], "mod": ""})
		m["loadout"]["mounts"] = mounts)


## Puts a weapon in a mount slot ("" empties the slot).
func set_weapon(mount: int, slot: int, weapon_id: String) -> String:
	if weapon_id != "" and db.weapon(weapon_id).is_empty():
		return "Unknown weapon."
	return _try(func(p: Dictionary) -> void:
		var mt: Dictionary = _mount(p, mount)
		var list: Array = mt["weapons"]
		if weapon_id == "":
			if slot < list.size():
				list.remove_at(slot)
			if list.is_empty():
				mt["mod"] = ""
		elif slot < list.size():
			list[slot] = weapon_id
		else:
			list.append(weapon_id))


func set_mod(mount: int, mod_id: String) -> String:
	if mod_id != "" and db.get_entry("mods", mod_id).is_empty():
		return "Unknown mod."
	return _try(func(p: Dictionary) -> void: _mount(p, mount)["mod"] = mod_id)


func add_system(system_id: String) -> String:
	if db.system(system_id).is_empty():
		return "Unknown system."
	return _try(func(p: Dictionary) -> void: (p["mechs"][mech_index]["loadout"]["systems"] as Array).append(system_id))


func remove_system(index: int) -> String:
	return _try(func(p: Dictionary) -> void:
		var list: Array = p["mechs"][mech_index]["loadout"]["systems"]
		if index >= 0 and index < list.size():
			list.remove_at(index))


func set_mech_name(text: String) -> void:
	if not mech().is_empty():
		mech()["name"] = text.strip_edges().left(48)
		_changed()


# --- Option lists ------------------------------------------------------------------------
# Each item: {id, name, source, license_level, ok, reason, selected, detail}

func frame_options() -> Array:
	var cur := str(mech().get("frame", ""))
	return _options(db.all("frames"), func(e: Dictionary) -> String: return set_frame_preview(e["id"]), cur, func(e: Dictionary) -> String:
		var st: Dictionary = e.get("stats", {})
		return "Size %s · HP %s · Evasion %s · Speed %s · SP %s" % [_num(st.get("size", 0)), _num(st.get("hp", 0)), _num(st.get("evasion", 0)), _num(st.get("speed", 0)), _num(st.get("sp", 0))])


## What set_frame would say, without changing anything.
func set_frame_preview(frame_id: String) -> String:
	return _preview(func() -> String: return set_frame(frame_id))


func weapon_options(mount: int, slot: int) -> Array:
	var cur_list: Array = _mount(pilot, mount).get("weapons", [])
	var cur := str(cur_list[slot]) if slot < cur_list.size() else ""
	return _options(db.all("weapons"), func(e: Dictionary) -> String: return _preview(func() -> String: return set_weapon(mount, slot, e["id"])), cur,
		func(e: Dictionary) -> String: return "%s %s · %s · %s SP" % [e.get("mount", ""), e.get("type", ""), _damage_text(e), _num(e.get("sp", 0))])


func mod_options(mount: int) -> Array:
	var cur := str(_mount(pilot, mount).get("mod", ""))
	return _options(db.all("mods"), func(e: Dictionary) -> String: return _preview(func() -> String: return set_mod(mount, e["id"])), cur,
		func(e: Dictionary) -> String: return "%s SP" % _num(e.get("sp", 0)))


func system_options() -> Array:
	return _options(db.all("systems"), func(e: Dictionary) -> String: return _preview(func() -> String: return add_system(e["id"])), "",
		func(e: Dictionary) -> String: return "%s · %s SP" % [e.get("type", "System"), _num(e.get("sp", 0))])


## Talents with their current rank; `ok` = can go up a rank.
func talent_options() -> Array:
	var out: Array = []
	for e: Dictionary in db.all("talents"):
		var rank := int(pilot["talents"].get(e["id"], 0))
		var max_rank := (e.get("ranks", []) as Array).size()
		var why := "Already at the top rank." if rank >= max_rank else _preview(func() -> String: return set_talent(e["id"], rank + 1))
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "source": "", "rank": rank, "max": max_rank,
			"ok": why == "", "reason": why, "selected": rank > 0, "detail": str(e.get("terse", ""))})
	return out


func skill_options() -> Array:
	var out: Array = []
	var max_rank := int(db.rules.get("max_trigger_rank", 3))
	for e: Dictionary in db.all("skills"):
		var rank := int(pilot["skills"].get(e["id"], 0))
		var why := "Already at +%d, the highest." % (max_rank * 2) if rank >= max_rank else _preview(func() -> String: return set_skill(e["id"], rank + 1))
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "source": "", "rank": rank, "max": max_rank,
			"ok": why == "", "reason": why, "selected": rank > 0, "detail": str(e.get("description", ""))})
	return out


## Frame licenses (GMS needs none); `ok` = can go up a rank.
func license_options() -> Array:
	var out: Array = []
	for e: Dictionary in db.all("frames"):
		if e.get("source", "") == "GMS":
			continue
		var rank := int(pilot["licenses"].get(e["id"], 0))
		var why := "Licenses go up to rank %d." % UnitFactory.MAX_LICENSE_RANK if rank >= UnitFactory.MAX_LICENSE_RANK else _preview(func() -> String: return set_license(e["id"], rank + 1))
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "source": e.get("source", ""), "rank": rank, "max": UnitFactory.MAX_LICENSE_RANK,
			"ok": why == "", "reason": why, "selected": rank > 0, "detail": ""})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["source"] + a["name"] < b["source"] + b["name"])
	return out


func core_bonus_options() -> Array:
	return _options(db.all("core_bonuses"), func(e: Dictionary) -> String:
		return "" if pilot["core_bonuses"].has(e["id"]) else _preview(func() -> String: return toggle_core_bonus(e["id"])),
		"", func(e: Dictionary) -> String: return _plain(str(e.get("effect", "")))).map(func(o: Dictionary) -> Dictionary:
			o["selected"] = pilot["core_bonuses"].has(o["id"])
			return o)


# --- Internals ---------------------------------------------------------------------------

## Applies `change` to the pilot if it adds no new problem; otherwise undoes it and returns
## the first new problem. `allowed` (optional) lets some new problems through.
func _try(change: Callable, allowed: Callable = Callable()) -> String:
	var before := _problems(pilot, mech_index)
	var backup := pilot.duplicate(true)
	change.call(pilot)
	var after := _problems(pilot, mech_index)
	for why: String in after:
		if not before.has(why) and not (allowed.is_valid() and allowed.call(why)):
			pilot = backup
			return why
	_changed()
	return ""


func _changed() -> void:
	if not _quiet:
		changed.emit()


## What a change would say, leaving the pilot as it was.
func _preview(attempt: Callable) -> String:
	var backup := pilot.duplicate(true)
	_quiet = true
	var why: String = attempt.call()
	_quiet = false
	pilot = backup
	return why


func _problems(p: Dictionary, index: int) -> Array:
	var out: Array = []
	var r := db.rules
	var b := _budgets_for(p)
	if b["skills"]["used"] > b["skills"]["max"]:
		out.append("Skill triggers: %d points used, %d available (%d at LL0, +1 per License Level)." % [b["skills"]["used"], b["skills"]["max"], int(r.get("minimum_pilot_skills", 4))])
	if b["talents"]["used"] > b["talents"]["max"]:
		out.append("Talents: %d ranks used, %d available (%d at LL0, +1 per License Level)." % [b["talents"]["used"], b["talents"]["max"], int(r.get("minimum_pilot_talents", 3))])
	if b["hase"]["used"] > b["hase"]["max"]:
		out.append("Mech skills: %d points used, %d available (%d at LL0, +1 per License Level)." % [b["hase"]["used"], b["hase"]["max"], int(r.get("minimum_mech_skills", 2))])
	for k in HASE:
		if int(p.get(k, 0)) > int(r.get("max_hase", 6)) or int(p.get(k, 0)) < 0:
			out.append("%s must be 0 to %d." % [k.capitalize(), int(r.get("max_hase", 6))])
	for id: String in p["skills"]:
		if int(p["skills"][id]) > int(r.get("max_trigger_rank", 3)):
			out.append("Skill triggers go up to +%d." % (int(r.get("max_trigger_rank", 3)) * 2))
	for id: String in p["talents"]:
		if int(p["talents"][id]) > (db.get_entry("talents", id).get("ranks", [1, 2, 3]) as Array).size():
			out.append("%s has only %d ranks." % [db.get_entry("talents", id).get("name", id), (db.get_entry("talents", id).get("ranks", []) as Array).size()])
	if b["core_bonuses"]["used"] > b["core_bonuses"]["max"]:
		out.append("Core bonuses: one per 3 License Levels (%d available)." % b["core_bonuses"]["max"])
	var per_maker := {}
	for cb: String in p["core_bonuses"]:
		var src := str(db.get_entry("core_bonuses", cb).get("source", "GMS"))
		if src != "GMS":
			per_maker[src] = int(per_maker.get(src, 0)) + 1
	for src: String in per_maker:
		var ranks := 0
		for fid: String in p["licenses"]:
			if db.frame(fid).get("source", "") == src:
				ranks += int(p["licenses"][fid])
		if ranks < 3 * int(per_maker[src]):
			out.append("%d %s core bonus%s need %d %s license ranks in total, 3 per bonus (you have %d)." % [
				per_maker[src], src, "" if per_maker[src] == 1 else "es", 3 * int(per_maker[src]), src, ranks])
	out.append_array(_locked_problems(p))
	if index < p["mechs"].size():
		var m: Dictionary = p["mechs"][index]
		var res := UnitFactory.check_loadout(db, str(m.get("frame", "")), m.get("loadout", {}), p)
		if not res.ok:
			for pr: Dictionary in (res.details if not res.details.is_empty() else [{"reason": res.reason}]):
				if not out.has(pr["reason"]):
					out.append(pr["reason"])
	else:
		for pr: Dictionary in UnitFactory.check_pilot(db, p):
			out.append(pr["reason"])
	return out


func _budgets_for(p: Dictionary) -> Dictionary:
	var keep := pilot
	pilot = p
	var b := budgets()
	pilot = keep
	return b


func _options(entries: Array, check: Callable, current: String, detail: Callable) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		if not e.has("id"):
			continue
		var lp := UnitFactory.license_problem(e, pilot)
		if lp.ends_with("isn't installable gear (integrated or special equipment).") or e.get("talent_item", false) and lp != "":
			continue  # Frame-integrated and talent-only gear isn't picked from lists.
		var why: String = "" if e["id"] == current else check.call(e)
		out.append({"id": e["id"], "name": e.get("name", e["id"]), "source": str(e.get("source", "")),
			"license_level": int(e.get("license_level", 0)), "ok": why == "", "reason": why,
			"selected": e["id"] == current, "detail": detail.call(e)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ok"] != b["ok"]:
			return a["ok"]
		if a["source"] != b["source"]:
			return a["source"] == "GMS" or (b["source"] != "GMS" and a["source"] < b["source"])
		if a["license_level"] != b["license_level"]:
			return a["license_level"] < b["license_level"]
		return a["name"] < b["name"])
	return out


func _mount(p: Dictionary, index: int) -> Dictionary:
	var mounts: Array = p["mechs"][mech_index]["loadout"].get("mounts", [])
	while mounts.size() <= index:
		mounts.append({"weapons": [], "mod": ""})
	p["mechs"][mech_index]["loadout"]["mounts"] = mounts
	var mt: Dictionary = mounts[index]
	if not mt.has("weapons"):
		mt["weapons"] = []
	if not mt.has("mod"):
		mt["mod"] = ""
	return mt


## The mounts of the current mech for display: [{index, type, slots, weapons: [{id, name}], mod}]
func mounts() -> Array:
	var out: Array = []
	var frame := db.frame(str(mech().get("frame", "")))
	var types: Array = frame.get("mounts", [])
	for i in range(types.size()):
		var mt := _mount(pilot, i)
		var weapons: Array = []
		for wid: String in mt["weapons"]:
			weapons.append({"id": wid, "name": db.weapon(wid).get("name", wid), "size": db.weapon(wid).get("mount", "")})
		out.append({"index": i, "type": str(types[i]), "slots": SLOTS.get(str(types[i]), 1), "weapons": weapons,
			"mod": str(mt["mod"]), "mod_name": str(db.get_entry("mods", str(mt["mod"])).get("name", ""))})
	return out


static func _set_rank(d: Dictionary, id: String, rank: int) -> void:
	if rank <= 0:
		d.erase(id)
	else:
		d[id] = rank


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k: Variant in d:
		n += int(d[k])
	return n


func _hase_total() -> int:
	var n := 0
	for k in HASE:
		n += int(pilot.get(k, 0))
	return n


static func _damage_text(w: Dictionary) -> String:
	var parts := PackedStringArray()
	for d: Dictionary in w.get("damage", []):
		parts.append("%s %s" % [_num(d.get("val", "")), d.get("type", "")])
	return ", ".join(parts) if not parts.is_empty() else "no damage"


## 1.0 -> "1", 0.5 -> "1/2" (Size), anything else as is.
static func _num(v: Variant) -> String:
	if (v is float or v is int) and float(v) == floorf(float(v)):
		return str(int(v))
	if (v is float) and is_equal_approx(float(v), 0.5):
		return "1/2"
	return str(v)


static func _plain(html: String) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(html, "", true).strip_edges()
