class_name SquadModel
extends MechModel
## Infantry on the board: a squad (kind "squad": ten men sharing its HP in one space) or a
## single soldier (kind "soldier"), as SoldierFigures in a loose formation. Men fall as the
## squad loses HP: men left = ceil(hp / max_hp * 10) (or the unit's "men_left" when the view
## has it). All standing men fire together as a volley, take cover, flinch when hit, walk when
## the board moves the unit. Fits MechView like any other model.

var figures: Array[SoldierFigure] = []
var men := 0
var _walking := false


static func build(unit: Dictionary) -> SquadModel:
	var m := SquadModel.new()
	m.name = "Squad_" + String(unit.get("id", ""))
	m.size = maxf(0.5, float(unit.get("size", 1)))
	m.gait = "tracked"
	var d := SoldierFigure.data()
	var h := float(d.get("height", 0.42))
	m.height = h
	var body := Node3D.new()
	body.name = "Body"
	m.add_child(body)
	m.pelvis = body
	m.torso = body
	var fac := SoldierFigure.faction_of(unit)
	var colors := SoldierFigure.colors_for(fac, unit.get("paint", {}) if unit.get("paint") is Dictionary else {})
	var count := int(d.get("men_per_squad", 10)) if is_squad(unit) else 1
	var kind_spec: Dictionary = (d.get("kinds", {}) as Dictionary).get(soldier_kind(unit), {})
	var every := int(kind_spec.get("launcher_every", d.get("launcher_every", 5)))
	if kind_spec.has("trim"):
		colors["trim"] = String(kind_spec["trim"])
	for i in range(count):
		var f := SoldierFigure.new().build(fac, colors, every > 0 and i % every == every - 1, kind_spec)
		f.scale = Vector3.ONE * (h / 1.75)
		f.position = slot(i, count, m.size)
		f.rotation.y = (MeshKit.hash01(String(unit.get("id", "")), i) - 0.5) * 0.5
		body.add_child(f)
		m.figures.append(f)
		if f.anim:
			f.anim.seek(MeshKit.hash01("t", i) * 1.5, true)  # not all in step
	var eye := Marker3D.new()
	eye.position = Vector3(0, h * 0.92, 0)
	body.add_child(eye)
	m.eye = eye
	m.men = count
	m.set_men(men_left(unit))
	m.collect_meshes()
	return m


## Where man `i` of `count` stands in his space: two loose rows, a little jitter.
static func slot(i: int, count: int, size: float) -> Vector3:
	if count <= 1:
		return Vector3.ZERO
	var per_row := ceili(count / 2.0)
	var row := i / per_row
	var col := i % per_row
	var span := 0.62 * size
	var x := (float(col) / maxf(1.0, per_row - 1) - 0.5) * span
	var z := (row - 0.5) * 0.28 * size
	return Vector3(x + (MeshKit.hash01("sx", i) - 0.5) * 0.06, 0, z + (MeshKit.hash01("sz", i) - 0.5) * 0.06 + (0.05 if col % 2 == 1 else 0.0))


## Men still standing: the view's men_left, else ceil(hp / max_hp * 10), for a squad.
static func men_left(unit: Dictionary) -> int:
	var per := int(SoldierFigure.data().get("men_per_squad", 10)) if is_squad(unit) else 1
	if unit.has("men_left"):
		return clampi(int(unit["men_left"]), 0, per)
	var mx := float(unit.get("max_hp", 0))
	if mx <= 0.0 or not unit.has("hp"):
		return per
	return clampi(ceili(float(unit["hp"]) / mx * per), 0, per)


## Garrisoned (PROVISIONAL field: unit "garrison" = building id or null, until rules settles
## the shape): a few men at the windows facing out, the rest out of sight inside. Leaving
## puts everyone back in formation.
const WINDOW_MEN := 3
var garrisoned := false


func set_garrison(building: Variant) -> void:
	var inside := building != null and String(building) != ""
	if inside == garrisoned:
		return
	garrisoned = inside
	var shown := 0
	for i in range(figures.size()):
		var f := figures[i]
		if not inside:
			f.visible = true
			f.position = slot(i, figures.size(), size)
			continue
		var at_window := not f.down and shown < WINDOW_MEN
		f.visible = at_window
		if at_window:
			var a := TAU * shown / WINDOW_MEN + 0.4
			f.position = Vector3(sin(a), 0, cos(a)) * 0.42 * size + Vector3.UP * height * 0.6
			f.rotation.y = a + PI  # facing out
			shown += 1


## Men beyond `n` fall (the last ones in the formation first) and stay down.
func set_men(n: int) -> void:
	men = n
	for i in range(figures.size()):
		if i >= n:
			figures[i].fall()


func standing() -> Array[SoldierFigure]:
	var out: Array[SoldierFigure] = []
	for f in figures:
		if not f.down and f.visible:
			out.append(f)
	return out


func _process(delta: float) -> void:
	super(delta)
	var walk := walk_amount > 0.05
	if walk != _walking:
		_walking = walk
		for f in standing():
			f.play("walk" if walk else "idle")


## Every standing man fires at `target` together: they turn, shoulder their rifles and flash.
func volley(fx: Node3D, target: Vector3, color: Color = Color(1.0, 0.8, 0.45)) -> void:
	var guns := standing()
	for f in guns:
		var to := target - f.global_position
		f.rotation.y = atan2(-to.x, -to.z) - global_rotation.y
		f.play("fire", 0.1)
	if is_inside_tree():
		await get_tree().create_timer(Fx.t(0.15)).timeout
	for f in guns:
		if not is_instance_valid(f):
			continue
		var m := f.muzzle()
		Fx.muzzle_flash(fx, m, Color(1.0, 0.75, 0.35), 0.05)
		Fx.tracer(fx, m, target + Vector3((MeshKit.hash01("v", guns.find(f)) - 0.5) * 0.3, (MeshKit.hash01("w", guns.find(f)) - 0.5) * 0.2, 0), color, 0.12)
	if is_inside_tree():
		await get_tree().create_timer(Fx.t(0.4)).timeout
	for f in guns:
		if is_instance_valid(f):
			f.play("walk" if _walking else "idle")


## Hit: the standing men flinch.
func hit() -> void:
	for f in standing():
		f.play("hit", 0.05)
	if is_inside_tree():
		await get_tree().create_timer(Fx.t(0.5)).timeout
	for f in standing():
		f.play("idle")


## In cover (the rules said so): kneel behind it; out of cover: stand.
func take_cover(on: bool) -> void:
	for f in standing():
		f.play("cover" if on else "idle")


## The soldier kind a view unit is (rules: kind "npc" with loadout.on_foot and
## loadout.soldier, and the public "soldier" field): rifle_squad, missile_team, guard_squad,
## spotter_team, medic_team or soldier. "" if it isn't infantry. Older placeholder kinds
## ("squad", "soldier") still work.
static func soldier_kind(unit: Dictionary) -> String:
	var k := String(unit.get("soldier", ""))
	if k == "":
		k = String((unit.get("loadout", {}) as Dictionary).get("soldier", ""))
	if k == "" and String(unit.get("kind", "")) in ["squad", "soldier"]:
		k = "rifle_squad" if String(unit.get("kind", "")) == "squad" else "soldier"
	return k


## Ten men in one space (every kind but the single "soldier").
static func is_squad(unit: Dictionary) -> bool:
	var k := soldier_kind(unit)
	return k != "" and k != "soldier"
