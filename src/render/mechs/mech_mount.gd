class_name MechMount
extends RefCounted
## Getting in and out of a mech in real time (exploring, the hangar): the pilot walks up to
## the mech's side, the mech kneels, the pilot climbs to the hatch and is gone, the mech stands
## and its eyes light up. Dismount is the reverse. `pilot` is any Node3D (a HumanFigure, or a
## MechView/node carrying one as meta "human"); `mech` is the MechModel. Await either call.
## Visual only: call it when the story/flow says the pilot mounts (Core: Mount, a full action
## in combat; in combat EventPlayer shows pilot_mounted / pilot_left_mech itself).


static func _human(pilot: Node3D) -> Node:
	if pilot == null:
		return null
	if pilot.has_method("play"):
		return pilot
	if pilot.has_meta("human"):
		return pilot.get_meta("human")
	for c in pilot.get_children():
		if c.has_method("play"):
			return c
	return null


static func _play(pilot: Node3D, anim_name: String) -> void:
	var h := _human(pilot)
	if h:
		h.call("play", anim_name)


## The hatch (world space): a little behind and above the eye, or high on the torso.
static func hatch(mech: MechModel) -> Vector3:
	if mech.eye:
		return mech.eye.global_position + mech.global_transform.basis.z * mech.height * 0.12
	return mech.global_position + Vector3.UP * mech.height * 0.7


## Where the pilot stands to climb: beside the mech's right leg.
static func boarding_spot(mech: MechModel) -> Vector3:
	var right := mech.global_transform.basis.x.normalized()
	return mech.global_position + right * maxf(0.5, mech.height * 0.45)


static func _kneel(mech: MechModel, from: float, to: float, dur: float) -> void:
	var tw := mech.create_tween()
	tw.tween_method(func(k: float) -> void: mech.set_kneel(k), from, to, Fx.t(dur)).set_trans(Tween.TRANS_SINE)
	await tw.finished


static func mount(pilot: Node3D, mech: MechModel) -> void:
	var spot := boarding_spot(mech)
	spot.y = pilot.global_position.y
	_play(pilot, "walk")
	var walk := pilot.create_tween()
	walk.tween_property(pilot, "global_position", spot, Fx.t(maxf(0.3, pilot.global_position.distance_to(spot) / 1.4)))
	pilot.look_at(Vector3(mech.global_position.x, pilot.global_position.y, mech.global_position.z), Vector3.UP, true)
	await walk.finished
	_play(pilot, "idle")
	await _kneel(mech, 0.0, 1.0, 0.6)
	# Climb: up the leg and onto the hatch, then inside.
	var top := hatch(mech)
	_play(pilot, "sneak")
	var climb := pilot.create_tween()
	climb.tween_property(pilot, "global_position", Vector3(spot.x, top.y * 0.6 + spot.y * 0.4, spot.z), Fx.t(0.5))
	climb.tween_property(pilot, "global_position", top, Fx.t(0.45))
	await climb.finished
	pilot.visible = false
	mech.set_fx("flash", 0.5)
	var fl := mech.create_tween()
	fl.tween_method(func(v: float) -> void: mech.set_fx("flash", v), 0.5, 0.0, Fx.t(0.4))
	await _kneel(mech, 1.0, 0.0, 0.7)


static func dismount(mech: MechModel, pilot: Node3D, to: Vector3) -> void:
	await _kneel(mech, 0.0, 1.0, 0.6)
	var top := hatch(mech)
	var spot := boarding_spot(mech)
	spot.y = to.y
	pilot.global_position = top
	pilot.visible = true
	_play(pilot, "sneak")
	var climb := pilot.create_tween()
	climb.tween_property(pilot, "global_position", Vector3(spot.x, top.y * 0.6 + spot.y * 0.4, spot.z), Fx.t(0.45))
	climb.tween_property(pilot, "global_position", spot, Fx.t(0.5))
	await climb.finished
	_play(pilot, "walk")
	var walk := pilot.create_tween()
	walk.tween_property(pilot, "global_position", to, Fx.t(maxf(0.3, spot.distance_to(to) / 1.4)))
	await _kneel(mech, 1.0, 0.0, 0.7)
	await walk.finished
	_play(pilot, "idle")
