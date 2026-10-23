class_name SoldierFigure
extends Node3D
## One soldier (assets/people/soldier.glb, tools/blender/soldier_mh.py): the faction's helmet and
## armor shown, the rest of the gear hidden, recolored by material role from
## data/game/soldier_looks.json or the unit's own paint. The glb is loaded once and shared, and
## materials are cached per scheme, so ten squads of ten stay cheap. Animations: idle, walk,
## run, aim, fire, cover, hit, fall.

const SCENE := "res://assets/people/soldier.glb"
const FILE := "res://data/game/soldier_looks.json"
const LOOPS := ["idle", "walk", "run", "sneak", "talk"]

static var _scene: PackedScene
static var _data: Dictionary = {}
static var _mats: Dictionary = {}  # "scheme|role" -> Material

var anim: AnimationPlayer
var down := false
var faction := ""
var _root: Node3D


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_data = d if d is Dictionary else {"factions": {}, "by_side": {}}
	return _data


## The faction a unit shows: its own "faction", else by side.
static func faction_of(unit: Dictionary) -> String:
	var f := String(unit.get("faction", ""))
	if (data().get("factions", {}) as Dictionary).has(f):
		return f
	return String((data().get("by_side", {}) as Dictionary).get(String(unit.get("side", "")), "militia"))


## Colors by role for a faction, with the unit's paint (crew/company scheme) on top.
static func colors_for(fac: String, paint: Dictionary = {}) -> Dictionary:
	var c: Dictionary = ((data().get("factions", {}) as Dictionary).get(fac, {}) as Dictionary).get("colors", {}).duplicate()
	for pair: Array in [["primary", "uniform"], ["secondary", "armor"], ["glow", "visor"], ["markings", "trim"]]:
		if paint.has(pair[0]):
			c[pair[1]] = String(paint[pair[0]])
	return c


func build(fac: String, colors: Dictionary, launcher: bool = false) -> SoldierFigure:
	faction = fac
	name = "Soldier"
	if _scene == null and ResourceLoader.exists(SCENE):
		_scene = load(SCENE) as PackedScene
	if _scene == null:
		return self
	_root = _scene.instantiate() as Node3D
	add_child(_root)
	var spec: Dictionary = (data().get("factions", {}) as Dictionary).get(fac, {})
	var helmet := String(spec.get("helmet", ""))
	var armor := String(spec.get("armor", ""))
	var scheme := "%s|%s" % [fac, JSON.stringify(colors)]
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.begins_with("Helmet_"):
			mi.visible = n == helmet
		elif n.begins_with("Armor_"):
			mi.visible = n == armor or n.begins_with(armor + "_")
		elif n.begins_with("Weapon_launcher"):
			mi.visible = launcher
		elif n.begins_with("Gear_pack"):
			mi.visible = bool(spec.get("pack", true))
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(i)
			var role := String(m.resource_name) if m else ""
			if colors.has(role):
				mi.set_surface_override_material(i, _material(scheme, role, m, Color(String(colors[role]))))
	anim = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for a: String in LOOPS:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		play("idle")
	return self


static func _material(scheme: String, role: String, base: Material, color: Color) -> Material:
	var key := scheme + "|" + role
	if not _mats.has(key):
		var m := base.duplicate() as Material
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = color
			if role == "visor":
				(m as StandardMaterial3D).emission_enabled = true
				(m as StandardMaterial3D).emission = color
				(m as StandardMaterial3D).emission_energy_multiplier = 0.8
		_mats[key] = m
	return _mats[key]


func play(anim_name: String, blend: float = 0.2) -> void:
	if anim == null or down or not anim.has_animation(anim_name):
		return
	if anim.current_animation != anim_name:
		anim.play(anim_name, blend)


## Shot down: falls and stays down.
func fall() -> void:
	if down:
		return
	if anim and anim.has_animation("fall"):
		anim.play("fall", 0.1)
	down = true


## Where this soldier's rifle fires from (world space).
func muzzle() -> Vector3:
	var r := _root.find_child("Weapon_rifle", true, false) as MeshInstance3D if _root else null
	var fwd := -global_transform.basis.z
	if r and r.mesh:
		# The mesh sits around the hand (its node origin is the rig's): the box's center.
		return r.global_transform * r.get_aabb().get_center() + fwd * 0.12 * global_transform.basis.get_scale().y
	return global_position + Vector3.UP * 0.75 * global_transform.basis.get_scale().y + fwd * 0.2 * global_transform.basis.get_scale().y
