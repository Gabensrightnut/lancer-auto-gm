class_name EventPlayer
extends Node
## Animates rules-engine events (docs/ARCHITECTURE.md "Event types") one after another:
## movement, attacks by weapon style, tech attacks, damage numbers, heat, statuses,
## structure/stress checks, deployables and destruction. Every event also writes a
## plain-language line to the combat log. Speed: Fx.speed (1 full, 2.5 quick, 0 instant).
## The player only shows what the events say; it never decides outcomes.

signal event_started(event: Dictionary)
signal event_finished(event: Dictionary)

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
		"next_side", "combat_started":
			pass
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
		"overcharged", "stabilized", "reloaded", "scanned", "tech_action", "reaction", "disengaged", "searched", "equipment_destroyed", "system_trauma", "falling":
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
		camera.frame_pair(a.global_position, b.global_position, 6.0)
	elif e.get("type") == "moved":
		var path: Array = e.get("path", [])
		if not path.is_empty():
			var last: Array = path.back()
			var end := battle.map.grid.to_world(Vector2i(int(last[0]), int(last[1])), int(last[2]) if last.size() > 2 else 0)
			camera.frame_pair(a.global_position, end, 6.0)
	elif e.get("type") in ["turn_started", "heat_changed", "status_added", "structure_check", "stress_check", "unit_destroyed", "destroyed"]:
		camera.look_at_point(a.global_position + Vector3.UP * 0.6, 7.0)


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

func _moved(e: Dictionary) -> void:
	var mv := _view(e["unit"])
	var path: Array = e.get("path", [])
	if mv == null or path.is_empty():
		return
	var mode := String(e.get("mode", "walk"))
	_log("%s %s %d spaces." % [_name(e["unit"]), {"walk": "moves", "boost": "boosts", "fly": "flies", "jump": "jumps", "involuntary": "is pushed"}.get(mode, "moves"), path.size() - 1])
	var last: Array = path[path.size() - 1]
	if Fx.speed <= 0.0:
		mv.place(_cell_of(last), int(last[2]) if last.size() > 2 else 0)
		return
	var step_time := {"walk": 0.32, "boost": 0.2, "fly": 0.24, "involuntary": 0.15}.get(mode, 0.3) as float
	if mode == "walk" or mode == "boost":
		mv.model.set_walk(1.0)
	var thruster: Node3D = null
	if mode == "fly" or mode == "jump" or mode == "boost":
		thruster = MeshKit.part(mv, MeshKit.sphere(0.08, 10), MeshKit.fx_material(Color(0.5, 0.8, 1.0), 4.0), Vector3(0, 0.05, 0.1))
	if mode == "jump":
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
			await tw.finished
			if mode == "boost":
				Fx.dust(battle.fx_root, target, 3, Color(0.55, 0.52, 0.48, 0.5), 0.3, 0.4, 0.8)
			elif mode == "involuntary":
				Fx.dust(battle.fx_root, target, 4, Color(0.55, 0.52, 0.48, 0.6), 0.3, 0.4, 0.8)
	mv.model.set_walk(0.0)
	if thruster:
		thruster.queue_free()
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
		await _attack_anim(att, tgt, wid, w, style, hit, result == "crit")
	if not is_instance_valid(tgt) or not is_instance_valid(att):
		return
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
	var shoulder: Node3D = att.model.arms[arm]["shoulder"]
	var sw := att.create_tween()
	sw.tween_property(shoulder, "rotation_degrees:x", 150.0, Fx.t(0.12))
	sw.tween_property(shoulder, "rotation_degrees:x", 20.0, Fx.t(0.12))
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
	if not de.has("roll") or (de["roll"] as Dictionary).is_empty():
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
		var from := att.model.eye.global_position if att.model.eye else att.body_center()
		await Fx.data_link(battle.fx_root, from, tgt.body_center(), color, 1.0)
	if not is_instance_valid(tgt) or not is_instance_valid(att):
		return
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
