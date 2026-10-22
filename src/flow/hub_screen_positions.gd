class_name HubScreenPositions
extends RefCounted
## The wire format for pilots walking around the hub online: [x, z, facing], rounded to
## centimetres. Cosmetic only; anything malformed or outside the hub is ignored.


static func pack(pos: Vector3, facing: float) -> Array:
	return [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01), snappedf(wrapf(facing, -PI, PI), 0.01)]


## [Vector3, facing] or [] if `v` isn't a sensible position.
static func parse(v: Variant) -> Array:
	if not v is Array or (v as Array).size() != 3:
		return []
	for n: Variant in v:
		if not (n is float or n is int) or is_nan(float(n)):
			return []
	var pos := Vector3(float(v[0]), 0.0, float(v[1]))
	if pos.length() > HubLayout.BOUNDS + 1.0:
		return []
	return [pos, float(v[2])]
