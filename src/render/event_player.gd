class_name EventPlayer
extends Node
## Animates rules-engine events (docs/ARCHITECTURE.md "Event types") one after another:
## movement, attacks by weapon style, tech attacks, damage numbers, heat, statuses,
## structure/stress checks, deployables and destruction. Every event also writes a
## plain-language line to the combat log. Speed: Fx.speed (1 full, 2.5 quick, 0 instant).
## The player only shows what the events say; it never decides outcomes.

signal event_started(event: Dictionary)
signal event_finished(event: Dictionary)
## Emitted when an attack's animation starts (the shot or swing begins).
signal firing(event: Dictionary)
## Emitted when an attack's hit (or miss) lands, for staging screenshots and sound later.
signal impact(event: Dictionary)

const SPEED_FULL := 1.0
const SPEED_QUICK := 2.5
const SPEED_INSTANT := 0.0
## Player-facing speed settings (DESIGN "Play feel"); "debug" is for tests and demos only.
const SPEEDS := {"cinematic": 0.7, "normal": 1.0, "fast": 1.8, "debug": 4.0, "instant": 0.0}

var battle: BattleView
## Roll results pop up as numbers over the board (no dice graphics).
var popups: RollPopups
## Last damage roll per target, so the damage pop-up's breakdown can show the dice.
var _last_damage_roll: Dictionary = {}
var combat_log: CombatLog
## Called with (attacker_name) when a unit in `local_units` is hacked (HUD glitch).
var on_local_hacked: Callable
var local_units: Array = []
var playing := false
## Persistent effects by id (smoke clouds, walls, lock-on reticles), so they can be removed.
var lasting: Dictionary = {}
var _generation := 0
## Camera that follows each action (null = leave the camera alone).
var camera: TacticalCamera
## Pause before an attack resolves, so you see who shoots whom before the dice (seconds).
var pre_attack_pause := 0.7
## "Skip to my turn": play everything instantly until one of `local_units` starts a turn.
var skip_to_my_turn := false
## Called with (text) for big banners ("Goblin's turn", "Round 2").
var on_banner: Callable
## (source, rule text, guidance) for effects the table resolves (a pop-up).
var on_table_note: Callable
## Returns the rules' current BattleMap (host side) for terrain_destroyed; optional.
var on_map_changed: Callable
## Returns the seat's current mission view ({zones, deployment}) for objectives_changed.
var on_mission_view: Callable
## Returns the current terrain damage table ({"x,y": damage}, GameState.terrain_damage) on
## the host; clients without it add up the terrain_damaged events they've seen.
var on_terrain_damage: Callable
var _terrain_damage: Dictionary = {}
## Called with (unit_id) when a unit's turn starts.
var on_turn_started: Callable
var _saved_speed := 1.0
var _skipping := false


func _init(view: BattleView, roll_popups: RollPopups, log_panel: CombatLog) -> void:
	battle = view
	popups = roll_popups
	combat_log = log_panel
	name = "EventPlayer"


func play(events: Array) -> void:
	playing = true
	var gen := _generation
	for e: Dictionary in events:
		if gen != _generation:
			return
		await play_event(e)
	playing = false


## Stops any sequence in progress after its current event (used when the board is rebuilt).
func cancel() -> void:
	_generation += 1
	playing = false


func play_event(e: Dictionary) -> void:
	event_started.emit(e)
	if skip_to_my_turn and not _skipping:
		_skipping = true
		_saved_speed = Fx.speed
		Fx.speed = 0.0
	if _skipping and e.get("type") == "turn_started" and String(e.get("unit", "")) in local_units:
		_skipping = false
		skip_to_my_turn = false
		Fx.speed = _saved_speed
	_follow(e)
	match String(e.get("type", "")):
		"turn_started":
			_log("[b]%s's turn.[/b]" % _name(e.get("unit", "")))
			var mv := _view(e.get("unit", ""))
			if mv and mv.battle:
				mv.battle.labels.active_unit = String(e.get("unit", ""))
			if on_banner.is_valid() and mv:
				on_banner.call("%s's turn" % mv.unit.get("name", e["unit"]))
			if on_turn_started.is_valid():
				on_turn_started.call(String(e.get("unit", "")))
			await Fx.wait(self, 0.6)
		"round_started":
			_log("[b]Round %d.[/b]" % int(e.get("round", 1)))
			if on_banner.is_valid():
				on_banner.call("Round %d" % int(e.get("round", 1)))
			await Fx.wait(self, 0.8)
		"next_side":
			pass
		"ejected":
			var emv := _view(e.get("unit", ""))
			_log("[b]%s's pilot ejects![/b]" % _name(e.get("unit", "")))
			_ejecting[String(e.get("unit", ""))] = true
			if emv and Fx.speed > 0.0:
				var top := emv.global_position + Vector3.UP * emv.model.height
				Fx.light_flash(battle.fx_root, top, Color(1.0, 0.7, 0.35), 5.0, 3.0, 0.3)
				Fx.sparks(battle.fx_root, top, Color(1.0, 0.75, 0.4), 18, 4.0)
				Fx.dust(battle.fx_root, top, 8, Color(0.6, 0.6, 0.62, 0.7), 0.4, 1.0, 1.2)
		"pilot_left_mech":
			await _pilot_out(e)
		"pilot_mounted":
			await _pilot_in(e)
		"terrain_damaged":
			# A hit on a wall or building: splinters, chips or sparks from the attacker's side,
			# then the cracks for its new damage total.
			var tc: Array = e.get("cell", [0, 0])
			var tcell := Vector2i(int(tc[0]), int(tc[1]))
			var src := _view(e.get("source", ""))
			if Fx.speed > 0.0:
				battle.terrain.hit_terrain(tcell, int(e.get("amount", 0)), src.body_center() if src else Vector3.INF)
			var totals: Dictionary
			if on_terrain_damage.is_valid():
				totals = on_terrain_damage.call()
			else:
				var key := "%d,%d" % [tcell.x, tcell.y]
				_terrain_damage[key] = int(_terrain_damage.get(key, 0)) + int(e.get("amount", 0))
				totals = _terrain_damage
			battle.terrain.show_damage(totals)
			_log("Terrain hit for %d %s damage%s." % [int(e.get("amount", 0)), String(e.get("damage_type", "")).to_lower(),
				" (%d Armor)" % int(e["armor"]) if int(e.get("armor", 0)) > 0 else ""])
		"objectives_changed":
			# The GM moved objectives (map editor): redraw them from the seat's fresh view.
			if on_mission_view.is_valid():
				var mvw: Variant = on_mission_view.call()
				if mvw is Dictionary and not (mvw as Dictionary).is_empty():
					battle.show_mission(mvw, battle.phase)
			_log("Objectives changed%s." % ((": " + String(e["reason"])) if String(e.get("reason", "")) != "" else ""))
		"terrain_destroyed", "terrain_edited":
			# Walls and buildings knocked down: collapse them with dust and rubble. The board
			# gets the rules' current map from on_map_changed when there is one (the host),
			# else the event's cells and new heights are applied to the board's own copy.
			var nc := (e.get("cells", []) as Array).size()
			_log("Terrain %s (%d space%s)." % ["edited by the GM" if e.get("type") == "terrain_edited" else "destroyed", nc, "" if nc == 1 else "s"])
			var current: BattleMap = on_map_changed.call() if on_map_changed.is_valid() else null
			if current == null:
				current = BattleMap.from_dict(battle.map.to_dict())
				for c: Variant in e.get("cells", []):
					var a: Array = c if c is Array else [(c as Dictionary).get("cell", [0, 0])[0], (c as Dictionary).get("cell", [0, 0])[1], (c as Dictionary).get("ground", 0)]
					var cell := Vector2i(int(a[0]), int(a[1]))
					var col := current.column(cell)
					if col and a.size() > 2:
						col.ground = int(a[2])
			battle.refresh_map(current)
			if Fx.speed > 0.0:
				await Fx.wait(self, 0.6)
		"cascade_check":
			var cmv2 := _view(e.get("unit", ""))
			_log("%s's NHP cascade check: d20 = %d%s" % [_name(e.get("unit", "")), int(e.get("roll", 0)), "  [color=#ff5544][b]CASCADE![/b][/color]" if e.get("cascade", false) else " (stable)"])
			if cmv2 and Fx.speed > 0.0 and e.get("cascade", false):
				cmv2.model.set_fx("cascade", 1.0)
				Fx.float_text(battle.fx_root, cmv2.body_center() + Vector3.UP * 0.5, "NHP CASCADE", Color(1.0, 0.25, 0.2), 56)
				Fx.light_flash(battle.fx_root, cmv2.body_center(), Color(1.0, 0.2, 0.15), 5.0, 3.5, 0.5)
				await Fx.wait(self, 0.8)
		"combat_started":
			battle.set_phase(GameState.PHASE_COMBAT)
		"zone_created":
			var z: Dictionary = e.get("zone", {})
			battle.zones.add_zone(z)
			_log("%s: %s." % [_name(z.get("owner", "")), z.get("label", z.get("kind", "zone"))])
		"zone_removed":
			battle.zones.remove_zone(String(e.get("id", "")))
		"manual_effect":
			# Something the game doesn't apply: say what, and what the table should do.
			var guide := String(e.get("guidance", e.get("note", "The table applies this.")))
			_log("[color=#e0b050]Table:[/color] %s: %s [color=#c8a060]%s[/color]" % [e.get("source", ""), String(e.get("text", "")).left(240), guide])
			if on_table_note.is_valid():
				on_table_note.call(String(e.get("source", "")), String(e.get("text", "")), guide)
		"bonus_damage":
			# Extra damage riding on a hit (a talent, system or core bonus); also part of the
			# damage_dealt that follows.
			var bmv := _view(e.get("target", ""))
			var bt := String(e.get("damage_type", "Kinetic"))
			_log("%s adds +%d %s damage (%s)%s." % [_name(e.get("attacker", "")), int(e.get("amount", 0)), bt.to_lower(), e.get("source", "bonus"), ", halved" if e.get("halved", false) else ""])
			if bmv and Fx.speed > 0.0:
				Fx.float_text(battle.fx_root, bmv.body_center() + Vector3.UP * 0.5, "+%d %s" % [int(e.get("amount", 0)), String(e.get("source", "")).to_upper()], RollDisplay.damage_color(bt), 40)
		"attack_rerolled":
			var first: Dictionary = e.get("first", {}) if e.get("first") is Dictionary else {}
			_log("%s rerolls the attack (%s): the first roll, %d, missed." % [_name(e.get("attacker", "")), e.get("source", "reroll"), int(first.get("total", 0))])
			var rmv2 := _view(e.get("attacker", ""))
			if rmv2 and Fx.speed > 0.0:
				Fx.float_text(battle.fx_root, rmv2.body_center() + Vector3.UP * 0.4, "REROLL", Color(0.5, 0.8, 1.0), 48)
				await Fx.wait(self, 0.35)
		"attack_cancelled":
			_log("%s's attack on %s doesn't happen: %s" % [_name(e.get("attacker", "")), _name(e.get("target", "")), e.get("reason", "")])
			var cmv := _view(e.get("attacker", ""))
			if cmv and Fx.speed > 0.0:
				Fx.float_text(battle.fx_root, cmv.body_center() + Vector3.UP * 0.4, "ATTACK CANCELLED", Color(0.8, 0.8, 0.85), 44)
				await Fx.wait(self, 0.4)
		"reaction_offered":
			_log("%s can react: %s?" % [_name(e.get("unit", "")), String(e.get("reaction", "")).capitalize()])
		"reaction":
			var rmv := _view(e.get("unit", ""))
			var what := String(e.get("reaction", "")).capitalize()
			_log("%s reacts: %s." % [_name(e.get("unit", "")), what])
			if rmv and Fx.speed > 0.0:
				if e.get("reaction") == "brace":
					Fx.shield_flash(battle.fx_root, rmv.body_center(), rmv.model.height * 0.6, Color(0.5, 0.8, 1.0))
				Fx.float_text(battle.fx_root, rmv.body_center() + Vector3.UP * 0.2, what.to_upper(), Color(0.95, 0.55, 0.95), 56)
				await Fx.wait(self, 0.5)
		"damage_rolled":
			# Rolled instantly; shown with the damage_dealt pop-up that follows.
			_last_damage_roll[String(e.get("target", ""))] = e.get("roll", {})
		"hp_changed":
			_set_stat(e.get("unit", ""), "hp", int(e.get("hp", 0)))
			_set_stat(e.get("unit", ""), "overshield", int(e.get("overshield", 0)))
		"structure_lost", "stress_lost":
			var key := "structure" if e["type"] == "structure_lost" else "stress"
			_set_stat(e.get("unit", ""), key, int(e.get(key, 0)))
			_log("%s loses 1 %s (%d left)." % [_name(e.get("unit", "")), key, int(e.get(key, 0))])
		"unit_destroyed":
			await _destroyed(e)
		"skill_check":
			var c: Dictionary = (e.get("check", {}) as Dictionary).duplicate()
			_log("%s: %s check, %d vs %d: %s" % [_name(e.get("unit", "")), c.get("skill", ""), int(c.get("total", 0)), int(c.get("target", 10)), "success" if c.get("success", false) else "failure"])
			var mv := _view(e.get("unit", ""))
			if popups and mv:
				var ok: bool = c.get("success", false)
				popups.show_check(_above(mv), c, "success" if ok else "fail")
				await Fx.wait(self, 0.6)
		"burn_marked":
			_set_stat(e.get("unit", ""), "burn", int(e.get("total", 0)))
			_log("%s is marked with %d burn." % [_name(e.get("unit", "")), int(e.get("amount", 0))])
		"movement_stopped":
			_log("%s stops: %s" % [_name(e.get("unit", "")), e.get("reason", "")])
		"falling":
			_log("%s starts to fall: %s" % [_name(e.get("unit", "")), e.get("reason", "")])
			var fmv := _view(e.get("unit", ""))
			if fmv and Fx.speed > 0.0:
				Fx.float_text(battle.fx_root, fmv.body_center() + Vector3.UP * 0.4, "FALLING", Color(1.0, 0.45, 0.3), 46)
		"overcharged", "stabilized", "reloaded", "scanned", "tech_action", "disengaged", "searched", "equipment_destroyed", "system_trauma":
			_log("%s: %s" % [_name(e.get("unit", e.get("attacker", ""))), String(e["type"]).replace("_", " ")])
		"moved":
			await _moved(e)
		"attack_rolled":
			await _attack(e)
		"damage_dealt":
			await _damage(e)
		"heat_changed":
			await _heat(e)
		"status_added", "status_removed":
			await _status(e)
		"structure_check", "stress_check":
			await _check_card(e)
		"structure_changed":
			_set_stat(e["unit"], "structure", int(e.get("total", 0)))
		"deployed":
			await _deployed(e)
		"tech_attack":
			await _tech(e)
		"destroyed":
			await _destroyed(e)
		"turn_ended":
			_log("%s ends their turn." % _name(e.get("unit", "")))
		_:
			_log("[color=#888](%s)[/color]" % e.get("type", "?"))
	event_finished.emit(e)


# --- helpers ---------------------------------------------------------------------------

## Point the camera at what this event is about.
func _follow(e: Dictionary) -> void:
	if camera == null or Fx.speed <= 0.0:
		return
	var a := _view(e.get("attacker", e.get("unit", "")))
	var b := _view(e.get("target", ""))
	if a == null:
		return
	if b and b != a:
		# Close fights (melee range) get a tighter shot.
		var near := a.global_position.distance_to(b.global_position) < 2.5
		camera.frame_pair(a.global_position, b.global_position, 3.2 if near else 6.0, _occlusion.bind(a.body_center(), b.body_center()))
	elif e.get("type") == "moved":
		var path: Array = e.get("path", [])
		if not path.is_empty():
			var last: Array = path.back()
			var end := battle.map.grid.to_world(Vector2i(int(last[0]), int(last[1])), int(last[2]) if last.size() > 2 else 0)
			camera.frame_pair(a.global_position, end, 6.0)
	elif e.get("type") in ["turn_started", "heat_changed", "status_added", "structure_check", "stress_check", "unit_destroyed", "destroyed"]:
		camera.look_at_point(a.global_position + Vector3.UP * 0.6, 7.0)


## How much terrain stands between a camera position and two points (0 = clear view).
func _occlusion(cam: Vector3, p1: Vector3, p2: Vector3) -> float:
	var hidden := 0.0
	for p: Vector3 in [p1, p2]:
		for i in range(1, 12):
			var q := p.lerp(cam, i / 12.0)
			var c := battle.map.grid.from_world(q)
			if battle.map.has_cell(c) and battle.map.ground_height(c) * GridLayout.LEVEL_HEIGHT > q.y:
				hidden += 1.0
	return hidden


## Where roll pop-ups appear: just above a unit's nameplate.
func _above(mv: MechView) -> Vector3:
	return mv.global_position + Vector3.UP * (mv.model.height + 0.75)


## The weapon's content id for a loadout key (rules events name weapons by key).
func _weapon_id(unit_id: Variant, key: String) -> String:
	var mv := _view(unit_id)
	if mv:
		for w: Dictionary in (mv.unit.get("loadout", {}) as Dictionary).get("weapons", []):
			if String(w.get("key", "")) == key:
				return String(w.get("id", key))
	return key

func _view(id: Variant) -> MechView:
	return battle.units.get(String(id))


func _name(id: Variant) -> String:
	var mv := _view(id)
	if mv == null:
		return String(id)
	var c := mv.side_color().lightened(0.3).to_html(false)
	return "[color=#%s]%s[/color]" % [c, mv.unit.get("name", id)]


func _log(text: String) -> void:
	if combat_log:
		combat_log.add_line(text)


func _set_stat(id: Variant, key: String, value: Variant) -> void:
	var mv := _view(id)
	if mv:
		mv.set_stat(key, value)


func _turn_to(mv: MechView, target: Vector3, dur: float = 0.25) -> void:
	var from := mv.model.rotation.y
	var to := mv.facing_angle_to(target)
	if Fx.speed <= 0.0 or absf(angle_difference(from, to)) < 0.05:
		mv.model.rotation.y = to
		return
	var tw := mv.create_tween()
	tw.tween_method(func(k: float) -> void: mv.model.rotation.y = lerp_angle(from, to, k), 0.0, 1.0, Fx.t(dur))
	await tw.finished


func _cell_of(v: Array) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))


# --- movement --------------------------------------------------------------------------

# --- pilots on foot -------------------------------------------------------------------

var _ejecting: Dictionary = {}


## A pilot leaves its mech: launched out on an arc after an Eject, or climbing down otherwise
## (Dismount, or leaving a wreck). The pilot's token is added to the board if it's new.
func _pilot_out(e: Dictionary) -> void:
	var mech := _view(e.get("mech", ""))
	var pid := String(e.get("unit", ""))
	var cell: Array = e.get("cell", [0, 0, 0])
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var lv := int(cell[2]) if cell.size() > 2 else battle.map.ground_height(c)
	var pv := _view(pid)
	if pv == null:
		pv = battle.add_unit({"id": pid, "kind": "pilot", "name": "%s pilot" % (mech.unit.get("name", "") if mech else ""),
			"side": mech.unit.get("side", "players") if mech else "players", "size": 0.5, "cell": [c.x, c.y], "level": lv})
	pv.unit["mounted"] = false
	pv.visible = true
	var ejecting := bool(_ejecting.get(String(e.get("mech", "")), false))
	_ejecting.erase(String(e.get("mech", "")))
	_log("%s %s." % [_name(pid), "lands" if ejecting else "climbs out of " + _name(e.get("mech", ""))])
	var land := pv.footprint_center(c, lv)
	if mech == null or Fx.speed <= 0.0:
		pv.place(c, lv)
		return
	pv.face(land + (land - mech.global_position))
	var from := mech.global_position + Vector3.UP * mech.model.height * (0.95 if ejecting else 0.6)
	pv.position = from
	var tw := pv.create_tween()
	if ejecting:
		# Up and out on the seat's rocket, then down by the chute.
		var peak := maxf(from.y, land.y) + 1.6
		tw.tween_method(func(k: float) -> void:
			var p := from.lerp(land, k)
			p.y = lerpf(from.y, land.y, k) + (peak - maxf(from.y, land.y)) * 4.0 * k * (1.0 - k) * (1.0 - 0.35 * k)
			pv.position = p, 0.0, 1.0, Fx.t(1.1))
		var trail := Fx.dust(battle.fx_root, from, 10, Color(0.75, 0.75, 0.78, 0.6), 0.25, 0.4, 1.4)
		trail.explosiveness = 0.1
	else:
		# Down the side of the mech to the ground.
		var side := from.lerp(land, 0.35)
		tw.tween_property(pv, "position", Vector3(side.x, from.y, side.z), Fx.t(0.25))
		tw.tween_property(pv, "position", land, Fx.t(0.55)).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	Fx.dust(battle.fx_root, land, 4, Color(0.55, 0.52, 0.48, 0.5), 0.15, 0.3, 0.8)
	pv.place(c, lv)


## A pilot climbs into a mech and disappears inside; the mech's eyes light up.
func _pilot_in(e: Dictionary) -> void:
	var pv := _view(e.get("unit", ""))
	var mech := _view(e.get("mech", ""))
	_log("%s mounts %s." % [_name(e.get("unit", "")), _name(e.get("mech", ""))])
	if pv == null:
		return
	if mech and Fx.speed > 0.0:
		var hatch := mech.global_position + Vector3.UP * mech.model.height * 0.6
		var tw := pv.create_tween()
		tw.tween_property(pv, "position", Vector3(hatch.x, pv.position.y, hatch.z).lerp(pv.position, 0.4), Fx.t(0.3))
		tw.tween_property(pv, "position", hatch, Fx.t(0.4))
		tw.parallel().tween_property(pv.model, "scale", Vector3.ONE * 0.2, Fx.t(0.4))
		await tw.finished
		mech.model.set_fx("flash", 0.5)
		var fl := mech.create_tween()
		fl.tween_method(func(v: float) -> void: mech.model.set_fx("flash", v), 0.5, 0.0, Fx.t(0.4))
	pv.model.scale = Vector3.ONE
	pv.unit["mounted"] = true
	pv.visible = false


func _moved(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	var path: Array = e.get("path", [])
	if mv == null or path.is_empty():
		return
	var mode := String(e.get("mode", "walk"))
	if mode == "fall":
		var drop := int(path[0][2]) - int(path[path.size() - 1][2]) if (path[0] as Array).size() > 2 else 0
		_log("%s falls %d level%s." % [_name(e["unit"]), drop, "" if drop == 1 else "s"])
	else:
		_log("%s %s %d spaces." % [_name(e["unit"]), {"walk": "moves", "boost": "boosts", "fly": "flies", "jump": "jumps", "involuntary": "is pushed", "teleport": "teleports"}.get(mode, "moves"), path.size() - 1])
	var last: Array = path[path.size() - 1]
	if Fx.speed <= 0.0:
		mv.place(_cell_of(last), int(last[2]) if last.size() > 2 else 0)
		return
	# Time per space: bigger mechs take longer, heavier strides.
	var step_time := ({"walk": 0.42, "boost": 0.28, "fly": 0.3, "involuntary": 0.15}.get(mode, 0.35) as float) * (0.85 + 0.15 * maxf(mv.model.size, 0.5))
	var model := mv.model
	var human: HumanFigure = model.get_meta("human") if model.has_meta("human") else null
	if human:
		human.play("run" if mode == "boost" else "walk")
	var legged := mode == "walk" or mode == "boost"
	model.airborne = mode == "fly"
	if legged or mode == "fly":
		var fade := mv.create_tween()
		fade.tween_property(model, "walk_amount", 1.0, Fx.t(0.15))
	var thruster: Node3D = null
	if mode == "fly" or mode == "jump" or mode == "boost":
		thruster = MeshKit.part(mv, MeshKit.sphere(0.08, 10), MeshKit.fx_material(Color(0.5, 0.8, 1.0), 4.0), Vector3(0, 0.05, 0.1))
	if mode == "fall":
		# Straight down, speeding up, a slight tumble, then a heavy landing.
		var a0 := mv.position
		var b0 := mv.footprint_center(_cell_of(last), int(last[2]) if last.size() > 2 else 0)
		var t_fall := Fx.t(clampf(sqrt(maxf(0.1, a0.y - b0.y)) * 0.32, 0.25, 1.1))
		var tw0 := mv.create_tween()
		tw0.tween_property(mv, "position", b0, t_fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw0.parallel().tween_property(model, "rotation_degrees:z", 9.0, t_fall)
		await tw0.finished
		Fx.dust(battle.fx_root, b0, 14, Color(0.5, 0.47, 0.43, 0.7), 0.6, 0.8, 1.4)
		Fx.debris(battle.fx_root, b0, 6)
		var settle := mv.create_tween()
		settle.tween_property(model, "rotation_degrees:z", 0.0, Fx.t(0.25))
	elif mode == "teleport":
		var b1 := mv.footprint_center(_cell_of(last), int(last[2]) if last.size() > 2 else 0)
		Fx.light_flash(battle.fx_root, mv.body_center(), Color(0.6, 0.85, 1.0), 4.0, 3.0, 0.3)
		model.visible = false
		await Fx.wait(self, 0.15)
		mv.position = b1
		Fx.light_flash(battle.fx_root, b1 + Vector3.UP * mv.model.height * 0.5, Color(0.6, 0.85, 1.0), 4.0, 3.0, 0.3)
		model.visible = true
	elif mode == "jump":
		var a := mv.position
		var b := mv.footprint_center(_cell_of(last), int(last[2]) if last.size() > 2 else 0)
		await _turn_to(mv, b)
		Fx.dust(battle.fx_root, a, 6, Color(0.5, 0.48, 0.45, 0.6))
		var tw := mv.create_tween()
		tw.tween_method(func(k: float) -> void: mv.position = a.lerp(b, k) + Vector3.UP * (1.5 + absf(b.y - a.y)) * 4.0 * k * (1.0 - k), 0.0, 1.0, Fx.t(0.8))
		await tw.finished
		Fx.dust(battle.fx_root, b, 8, Color(0.5, 0.48, 0.45, 0.6))
	else:
		for i in range(1, path.size()):
			var p: Array = path[i]
			var c := _cell_of(p)
			var lv := int(p[2]) if p.size() > 2 else battle.map.ground_height(c)
			var target := mv.footprint_center(c, lv)
			if mode != "involuntary":
				await _turn_to(mv, target, 0.12)
			var start := mv.position
			var hop := absf(target.y - start.y) > 0.01 and mode != "fly"
			var tw := mv.create_tween()
			if hop:
				# Climb or drop: a short hop over the ledge.
				tw.tween_method(func(k: float) -> void:
					var p2 := start.lerp(target, k)
					p2.y += 0.35 * 4.0 * k * (1.0 - k)
					mv.position = p2, 0.0, 1.0, Fx.t(step_time * 1.6))
			else:
				tw.tween_property(mv, "position", target, Fx.t(step_time))
			if legged:
				# Advance the gait by whole steps per cell, so feet land as the cell is reached.
				var steps := model.steps_per_cell()
				var t2 := mv.create_tween()
				t2.tween_property(model, "walk_phase", model.walk_phase + steps * PI, Fx.t(step_time * (1.6 if hop else 1.0)))
			await tw.finished
			if mode == "boost":
				Fx.dust(battle.fx_root, target, 3, Color(0.55, 0.52, 0.48, 0.5), 0.3, 0.4, 0.8)
			elif mode == "involuntary":
				Fx.dust(battle.fx_root, target, 4, Color(0.55, 0.52, 0.48, 0.6), 0.3, 0.4, 0.8)
	model.airborne = false
	var stop := mv.create_tween()
	stop.tween_property(model, "walk_amount", 0.0, Fx.t(0.15))
	stop.tween_callback(func() -> void: model.set_walk(0.0))
	if thruster:
		thruster.queue_free()
	if human:
		human.play("idle")
	mv.place(_cell_of(last), int(last[2]) if last.size() > 2 else battle.map.ground_height(_cell_of(last)))


# --- attacks ---------------------------------------------------------------------------

func _attack(e: Dictionary) -> void:
	var att := _view(e["attacker"])
	var tgt := _view(e["target"])
	if att == null or tgt == null:
		return
	var wid := _weapon_id(e["attacker"], String(e.get("weapon", "")))
	var w := battle.content.weapon(wid) if battle.content else {}
	var wname := String(e.get("weapon_name", w.get("name", e.get("weapon", "attack"))))
	var style := WeaponBuilder.attack_style(w) if not w.is_empty() else WeaponBuilder.STYLE_KINETIC
	var result := String(e.get("result", "hit"))
	var check: Dictionary = e.get("check", {})
	var hit := result != "miss"
	_log("%s attacks %s with %s: %s" % [_name(e["attacker"]), _name(e["target"]), wname, RollDisplay.formula_bbcode(check, result)])
	await _turn_to(att, tgt.global_position)
	var arm := att.model.arm_for(wid)
	if arm != "" and style != WeaponBuilder.STYLE_MELEE:
		att.model.aim_arm(arm, tgt.body_center())
	await Fx.wait(self, pre_attack_pause)
	if not is_instance_valid(att) or not is_instance_valid(tgt):
		return
	if Fx.speed > 0.0:
		firing.emit(e)
		await _attack_anim(att, tgt, wid, w, style, hit, result == "crit")
	if not is_instance_valid(tgt) or not is_instance_valid(att):
		return
	impact.emit(e)
	if popups and not check.is_empty():
		popups.show_check(_above(tgt), check, result)
	if arm != "":
		att.model.aim_arm(arm, Vector3.ZERO, false)
	await Fx.wait(self, 0.2)


## Where a shot that misses goes: past the target, off to one side.
func _miss_point(att: MechView, tgt: MechView) -> Vector3:
	var to := tgt.body_center() - att.body_center()
	var side := to.cross(Vector3.UP).normalized()
	return tgt.body_center() + side * (0.6 + tgt.model.height * 0.4) + to.normalized() * 2.5 + Vector3.DOWN * 0.4


func _attack_anim(att: MechView, tgt: MechView, wid: String, w: Dictionary, style: String, hit: bool, crit: bool) -> void:
	var fx := battle.fx_root
	var muzzle := att.model.muzzle_position(wid)
	var aim := tgt.body_center() if hit else _miss_point(att, tgt)
	var glow: Color = WeaponBuilder.glow_color(w) if not w.is_empty() else Color(1, 0.8, 0.4)
	var blast := "Blast" in WeaponBuilder.range_types(w)
	match style:
		WeaponBuilder.STYLE_MELEE:
			await _melee(att, tgt, hit, glow if "Energy" in WeaponBuilder.damage_types(w) else Color(1.0, 0.9, 0.7))
		WeaponBuilder.STYLE_ENERGY:
			await Fx.beam(fx, muzzle, aim, glow, 0.09 if crit else 0.06)
			if hit:
				Fx.sparks(fx, aim, glow, 24)
				Fx.hit_flash(tgt.model)
			else:
				Fx.impact_puff(fx, aim)
		WeaponBuilder.STYLE_MISSILE, WeaponBuilder.STYLE_EXPLOSIVE:
			var ground := tgt.global_position if hit else Vector3(aim.x, battle.map.ground_height(tgt.cell) * GridLayout.LEVEL_HEIGHT, aim.z)
			if blast:
				Fx.warning_ring(fx, tgt.global_position, 1.5, 0.6)
			var count := 3 if style == WeaponBuilder.STYLE_MISSILE else 1
			var arc := 2.0 if (style == WeaponBuilder.STYLE_MISSILE or blast) else 0.3
			Fx.muzzle_flash(fx, muzzle, Color(1.0, 0.6, 0.25), 0.15)
			for i in range(count):
				var jitter := Vector3(sin(i * 2.3), 0, cos(i * 1.7)) * 0.25 * i
				var land := (tgt.body_center() if hit else aim) + jitter
				if i < count - 1:
					Fx.projectile_arc(fx, muzzle, land, arc, 0.75 + 0.1 * i)
					await Fx.wait(self, 0.12)
				else:
					await Fx.projectile_arc(fx, muzzle, land, arc, 0.75 + 0.1 * i)
			if not is_instance_valid(tgt):
				return
			Fx.explosion(fx, (tgt.body_center() if hit else ground), 1.1 if blast else 0.7)
			if hit:
				Fx.hit_flash(tgt.model)
			await Fx.wait(self, 0.3)
		WeaponBuilder.STYLE_FLAME:
			var flame := Fx.fire(fx, muzzle, 0.7)
			flame.direction = (aim - muzzle).normalized()
			flame.initial_velocity_min = 4.0
			flame.initial_velocity_max = 6.0
			flame.spread = 18.0
			flame.gravity = Vector3.ZERO
			Fx.light_flash(fx, muzzle, Color(1.0, 0.5, 0.15), 4.0, 4.0, 1.0)
			await Fx.wait(self, 0.9)
			flame.emitting = false
			flame.get_tree().create_timer(1.0).timeout.connect(flame.queue_free)
			if hit:
				Fx.hit_flash(tgt.model)
		WeaponBuilder.STYLE_SWARM:
			for i in range(6):
				var land := aim + Vector3(sin(i * 1.3), cos(i * 2.1), sin(i * 0.7)) * 0.2
				Fx.projectile_arc(fx, muzzle, land, 0.6 + 0.2 * (i % 3), 0.6 + 0.05 * i, glow)
				await Fx.wait(self, 0.06)
			await Fx.wait(self, 0.6)
			Fx.sparks(fx, aim, glow, 20)
			if hit:
				Fx.hit_flash(tgt.model)
		_:
			# Kinetic: bursts of tracers; cannons fire one heavy round.
			var type := String(w.get("type", "Rifle"))
			var shots := 1 if type == "Cannon" else (1 if type == "CQB" else 3)
			var pellets := 5 if type == "CQB" else 1
			for i in range(shots):
				Fx.muzzle_flash(fx, muzzle, Color(1.0, 0.75, 0.35), 0.1 if type != "Cannon" else 0.2)
				for p in range(pellets):
					var spread := Vector3(sin(p * 2.4 + i), cos(p * 1.9 + i), sin(p * 3.1)) * (0.18 if pellets > 1 else 0.06)
					var target := aim + spread
					if p < pellets - 1:
						Fx.tracer(fx, muzzle, target, Color(1.0, 0.8, 0.45), 0.1)
					else:
						await Fx.tracer(fx, muzzle, target, Color(1.0, 0.8, 0.45), 0.12 if type != "Cannon" else 0.18)
				if not is_instance_valid(tgt):
					return
				if hit:
					Fx.impact_puff(fx, aim + Vector3(sin(i * 3.0), cos(i * 2.0), 0) * 0.08)
					Fx.hit_flash(tgt.model)
				else:
					Fx.dust(fx, aim + Vector3.DOWN * 0.3, 3, Color(0.5, 0.48, 0.45, 0.6), 0.3, 0.5, 0.8)
				await Fx.wait(self, 0.08)


func _melee(att: MechView, tgt: MechView, hit: bool, color: Color) -> void:
	var start := att.position
	var to := tgt.position - start
	to.y = 0
	var lunge := start + to.normalized() * maxf(0.0, to.length() - (tgt.model.height * 0.35 + att.model.height * 0.25))
	var tw := att.create_tween()
	tw.tween_property(att, "position", lunge, Fx.t(0.22)).set_ease(Tween.EASE_IN)
	await tw.finished
	var arm := "l" if att.model.slot_weapon.has("hand_l") else "r"
	var sw := att.create_tween()
	if att.model.arms.has(arm):
		var shoulder: Node3D = att.model.arms[arm]["shoulder"]
		sw.tween_property(shoulder, "rotation_degrees:x", 150.0, Fx.t(0.12))
		sw.tween_property(shoulder, "rotation_degrees:x", 20.0, Fx.t(0.12))
	else:
		sw.tween_interval(Fx.t(0.24))  # pilots and armless units: just the swing arc
	Fx.swing_arc(battle.fx_root, att.body_center(), to.normalized(), att.model.height * 0.6, color)
	await sw.finished
	if hit:
		Fx.sparks(battle.fx_root, tgt.body_center(), Color(1.0, 0.8, 0.4), 26, 4.0)
		Fx.hit_flash(tgt.model)
		# Knockback slide and settle.
		var tp := tgt.position
		var kb := tgt.create_tween()
		kb.tween_property(tgt, "position", tp + to.normalized() * 0.25, Fx.t(0.1))
		kb.tween_property(tgt, "position", tp, Fx.t(0.25))
	else:
		Fx.shield_flash(battle.fx_root, tgt.body_center(), tgt.model.height * 0.55)
		Fx.sparks(battle.fx_root, tgt.body_center(), Color(0.5, 0.8, 1.0), 10, 2.0)
	var back := att.create_tween()
	back.tween_interval(Fx.t(0.15))
	back.tween_property(att, "position", start, Fx.t(0.3))
	await back.finished
	att.model.aim_arm(arm, Vector3.ZERO, false)


# --- damage, heat, statuses ------------------------------------------------------------

func _damage(e: Dictionary) -> void:
	var mv := _view(e["target"])
	var amount := int(e.get("amount", 0))
	var dtype := String(e.get("damage_type", "Kinetic"))
	var de := e.duplicate()
	# `roll` may be a Dice.roll record or a plain total.
	if not (de.get("roll") is Dictionary) or (de["roll"] as Dictionary).is_empty():
		de["roll"] = _last_damage_roll.get(String(e["target"]), {})
	_last_damage_roll.erase(String(e["target"]))
	var breakdown := RollDisplay.damage_bbcode(de)
	_log("%s takes %d %s damage: %s" % [_name(e["target"]), amount, dtype.to_lower(), breakdown])
	if mv == null:
		return
	if popups:
		popups.show_damage(_above(mv), amount, dtype, breakdown)
	if dtype == "Heat":
		return
	if e.has("hp"):
		mv.set_stat("hp", int(e["hp"]))
	elif e.has("source"):
		pass  # rules engine format: an hp_changed event follows
	elif mv.unit.has("hp"):
		mv.set_stat("hp", maxi(0, int(mv.unit["hp"]) - amount))
	await Fx.wait(self, 0.4)


func _heat(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	var amount := int(e.get("amount", 0))
	_log("%s %s %d heat (%d total)." % [_name(e["unit"]), "gains" if amount >= 0 else "vents", absi(amount), int(e.get("total", 0))])
	if mv == null:
		return
	mv.unit["heat"] = int(e.get("total", 0))
	if amount < 0:
		Fx.steam(battle.fx_root, mv.global_position + Vector3.UP * mv.model.height * 0.7, mv.model.size)
		if popups:
			popups.show_text(_above(mv), "%d" % amount, "VENT", Color(0.85, 0.92, 1.0), "", "heat")
	elif popups:
		popups.show_text(_above(mv), "+%d" % amount, "", Color(1.0, 0.6, 0.25), "%d / %d heat" % [int(e.get("total", 0)), int(mv.unit.get("heat_cap", 0))], "heat")
	# Glow ramps toward the new heat level.
	var from := float(mv.unit.get("heat", 0) - amount)
	var to := float(mv.unit.get("heat", 0))
	var cap := int(mv.unit.get("heat_cap", 6))
	if Fx.speed > 0.0:
		var tw := mv.create_tween()
		tw.tween_method(func(h: float) -> void: mv.set_heat(roundi(h), cap), from, to, Fx.t(0.6))
		await tw.finished
	mv.refresh()
	await Fx.wait(self, 0.3)


func _status(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	var status := String(e.get("status", ""))
	var added: bool = e["type"] == "status_added"
	_log("%s %s %s." % [_name(e["unit"]), "is now" if added else "is no longer", status])
	if mv == null:
		return
	var statuses: Dictionary = mv.unit.get("statuses", {})
	if added:
		statuses[status] = {"source": e.get("source", "")}
	else:
		statuses.erase(status)
	mv.unit["statuses"] = statuses
	mv.refresh()
	Fx.float_text(battle.fx_root, mv.body_center() + Vector3.UP * 0.6, ("+ " if added else "− ") + status.to_upper(), Color(1.0, 0.85, 0.3), 56)
	var key := "%s|%s" % [e["unit"], status]
	if status == "Lock On":
		if added and not lasting.has(key):
			lasting[key] = _lock_reticle(mv)
		elif not added and lasting.has(key):
			(lasting[key] as Node).queue_free()
			lasting.erase(key)
	await Fx.wait(self, 0.5)


func _lock_reticle(mv: MechView) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3.UP * mv.model.height * 0.6
	mv.add_child(n)
	var tm := TorusMesh.new()
	tm.inner_radius = mv.model.height * 0.55
	tm.outer_radius = mv.model.height * 0.58
	tm.rings = 32
	tm.ring_segments = 4
	var ring := MeshKit.part(n, tm, MeshKit.fx_material(Color(1.0, 0.3, 0.25), 3.0), Vector3.ZERO, Vector3(90, 0, 0))
	for i in range(4):
		var a := TAU * i / 4.0
		MeshKit.part(ring, MeshKit.chamfer_box(Vector3(0.03, 0.03, 0.14), 0.005), MeshKit.fx_material(Color(1.0, 0.3, 0.25), 3.0), Vector3(cos(a), 0, sin(a)) * mv.model.height * 0.66, Vector3(0, -rad_to_deg(a) + 90, 0))
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "rotation:z", TAU, 3.0).from(0.0)
	n.rotation_degrees.x = 0
	return n


func _check_card(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	var is_structure: bool = e["type"] == "structure_check"
	var title := "STRUCTURE DAMAGE" if is_structure else "REACTOR STRESS"
	var roll: Variant = e.get("roll", 0)
	var roll_text := str(roll.get("total", roll)) if roll is Dictionary else str(roll)
	_log("%s: %s check, rolled %s: %s" % [_name(e["unit"]), "structure" if is_structure else "stress", roll_text, e.get("outcome", "")])
	if mv and Fx.speed > 0.0:
		var c := mv.body_center()
		if is_structure:
			# Armor plates blown off, sparks.
			Fx.explosion(battle.fx_root, c, 0.5)
			Fx.debris(battle.fx_root, c, 14, MechStyles.palette(mv.model.manufacturer)["primary"])
			Fx.hit_flash(mv.model)
		else:
			Fx.light_flash(battle.fx_root, c, Color(1.0, 0.4, 0.1), 6.0, 4.0, 0.8)
			Fx.steam(battle.fx_root, c, mv.model.size)
	if popups and mv:
		popups.show_text(_above(mv), roll_text, String(e.get("outcome", "")).to_upper(),
			Color(1.0, 0.5, 0.35) if is_structure else Color(1.0, 0.7, 0.3), "%s check: rolled %s → %s" % [title.capitalize(), roll_text, e.get("outcome", "")],
			"structure" if is_structure else "reactor")
		await Fx.wait(self, 0.8)


func _deployed(e: Dictionary) -> void:
	var obj: Dictionary = e.get("object", {})
	var kind := String(obj.get("kind", "deployable"))
	var mv := _view(e.get("unit", ""))
	var cells: Array = obj.get("cells", [])
	var points: Array = []
	for v: Array in cells:
		var c := _cell_of(v)
		points.append(battle.map.grid.to_world(c, int(v[2]) if v.size() > 2 else battle.map.ground_height(c)))
	_log("%s deploys %s." % [_name(e.get("unit", "")), obj.get("name", kind.replace("_", " "))])
	if points.is_empty():
		return
	var center := Vector3.ZERO
	for p: Vector3 in points:
		center += p
	center /= points.size()
	var id := String(obj.get("id", "%s_%d" % [kind, lasting.size()]))
	match kind:
		"smoke":
			if mv and Fx.speed > 0.0:
				await _turn_to(mv, center)
				await Fx.projectile_arc(battle.fx_root, mv.body_center(), center, 1.5, 0.6, Color(0.8, 0.8, 0.8))
			lasting[id] = Fx.smoke_cloud(battle.fx_root, points, float(obj.get("height", 1.2)))
			await Fx.wait(self, 0.8)
		"hard_light_wall":
			var segs: Array = []
			for i in range(points.size() - 1):
				segs.append([points[i], points[i + 1]])
			if segs.is_empty():
				var p: Vector3 = points[0]
				segs.append([p + Vector3(-0.5, 0, 0), p + Vector3(0.5, 0, 0)])
			if mv and Fx.speed > 0.0:
				await _turn_to(mv, center)
				Fx.data_link(battle.fx_root, mv.body_center(), center + Vector3.UP * 0.5, Color(0.3, 0.85, 1.0), 0.5)
			lasting[id] = Fx.hard_light_wall(battle.fx_root, segs, float(obj.get("height", 1.0)))
			await Fx.wait(self, 1.0)
		_:
			var marker := MeshKit.part(battle.fx_root, MeshKit.chamfer_box(Vector3(0.3, 0.3, 0.3), 0.03), MeshKit.mech_material(Color(0.4, 0.42, 0.45)), center + Vector3.UP * 0.15)
			MeshKit.part(marker, MeshKit.sphere(0.05, 8), MeshKit.fx_material(Color(0.4, 1.0, 0.6), 3.0), Vector3(0, 0.18, 0))
			lasting[id] = marker
			await Fx.wait(self, 0.4)


func _tech(e: Dictionary) -> void:
	var att := _view(e["attacker"])
	var tgt := _view(e["target"])
	if att == null or tgt == null:
		return
	var result := String(e.get("result", "hit"))
	var hit := result != "miss"
	var effect := String(e.get("effect", "Tech attack"))
	var check: Dictionary = (e.get("check", {}) as Dictionary).duplicate()
	if not check.has("target_label"):
		check["target_label"] = "E-Defense"
	_log("%s hacks %s (%s): %s" % [_name(e["attacker"]), _name(e["target"]), effect, RollDisplay.formula_bbcode(check, result)])
	await _turn_to(att, tgt.global_position)
	await Fx.wait(self, pre_attack_pause)
	var color := Color(0.35, 1.0, 0.55)
	if Fx.speed > 0.0:
		firing.emit(e)
		var from := att.model.eye.global_position if att.model.eye else att.body_center()
		await Fx.data_link(battle.fx_root, from, tgt.body_center(), color, 1.0)
	if not is_instance_valid(tgt) or not is_instance_valid(att):
		return
	impact.emit(e)
	if popups and not check.is_empty():
		popups.show_check(_above(tgt), check, result)
	if hit:
		Fx.glitch(tgt.model, 1.6)
		Fx.float_text(battle.fx_root, tgt.body_center() + Vector3.UP * 0.1, effect.to_upper(), color, 50)
		if String(e["target"]) in local_units and on_local_hacked.is_valid():
			on_local_hacked.call(String(att.unit.get("name", e["attacker"])))
	else:
		Fx.shield_flash(battle.fx_root, tgt.body_center(), tgt.model.height * 0.55, Color(0.35, 1.0, 0.55))
		Fx.float_text(battle.fx_root, tgt.body_center() + Vector3.UP * 0.1, "FIREWALL", Color(0.8, 0.8, 0.85), 48)
	await Fx.wait(self, 0.8)


func _destroyed(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	_log("[b]%s is destroyed![/b]" % _name(e["unit"]))
	if mv == null:
		return
	if Fx.speed > 0.0:
		Fx.explosion(battle.fx_root, mv.body_center(), 1.4 * maxf(1.0, mv.model.size))
		await Fx.wait(self, 0.15)
		Fx.explosion(battle.fx_root, mv.body_center() + Vector3(0.2, 0.2, 0), 0.9)
		Fx.float_text(battle.fx_root, mv.body_center() + Vector3.UP * 0.6, "DESTROYED", Color(1.0, 0.35, 0.25), 80)
	await mv.wreck()
