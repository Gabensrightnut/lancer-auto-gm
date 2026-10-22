class_name SitrepLayout
extends RefCounted
## Where each sitrep's areas go on a w x h map (rules text: data/lancer-data/sitreps.json):
## deployment zones for both sides, the sitrep's zones, and cells kept clear so the
## objectives are reachable. Plain data; MissionGenerator copies it into the Mission.
##
## Coordinates are (col, row) on a rectangle (hex rows shear like BattleMap.flat()). The
## players deploy along the bottom (high rows), the enemy along the top.
##
## Returns {"deployment": {side: [[x, y]]}, "zones": {name: [[x, y]]}, "clear": [[x, y]],
##   "first_side": side or ""}. Zone names: control/recon "zone_1".."zone_4", holdout and
## gauntlet "zone", escort "extraction", extraction "objective" (+ "extraction" = the allied
## deployment zone). Mission scores control/holdout/gauntlet today; escort, extraction and
## recon layouts are ready for when the GM generates them. Recon's True Control Zone is a
## secret the GM picks on the host; the layout doesn't mark it.

const DEPTH := 4
## Sitreps with zones: rows beyond the approach and the two deployment zones, and the least
## width, of the area they're laid out in on a big map (the size today's 30x34 maps give).
const ZONE_ROOM := 12
const ZONE_WIDTH := 30


## `approach` (GM dial, GmSettings.approach): for Basic Combat, the most rows between the two
## deployment zones (0 = deploy at the map edges). Closer zones mean first contact by about the
## second turn for Speed 4 mechs instead of two turns of walking. Sitreps with zones keep their
## edges (their zones are laid out from them), but on a map bigger than they need they're laid
## out in a centered area ZONE_ROOM rows taller than the approach (and at least ZONE_WIDTH
## wide): the starting distance follows the dial, not the map size, and the rest is flanking room.
static func layout(sitrep_id: String, w: int, h: int, shape: GridLayout.Shape, rng: RandomNumberGenerator, approach: int = 0) -> Dictionary:
	if sitrep_id != "sitrep_standardcombat" and approach > 0:
		var hh := mini(h, approach + 2 * DEPTH + ZONE_ROOM)
		var ww := mini(w, maxi(hh, ZONE_WIDTH))
		if hh < h or ww < w:
			# Even row offset: hex rows keep their stagger, so mirrored zones stay mirrored.
			return _shifted(_layout(sitrep_id, ww, hh, shape, rng, 0), (w - ww) / 2, ((h - hh) / 2) & ~1, shape)
	return _layout(sitrep_id, w, h, shape, rng, approach)


## Moves every cell of a layout by (dc columns, dr rows).
static func _shifted(lay: Dictionary, dc: int, dr: int, shape: GridLayout.Shape) -> Dictionary:
	var move := func(cells: Array) -> Array:
		var out: Array = []
		for c: Array in cells:
			var row := int(c[1])
			var col := int(c[0]) + (row >> 1) if shape == GridLayout.Shape.HEX else int(c[0])
			var cell := cell_of(col + dc, row + dr, shape)
			out.append([cell.x, cell.y])
		return out
	for side: String in lay["deployment"]:
		lay["deployment"][side] = move.call(lay["deployment"][side])
	for z: String in lay["zones"]:
		lay["zones"][z] = move.call(lay["zones"][z])
	lay["clear"] = move.call(lay["clear"])
	return lay


static func _layout(sitrep_id: String, w: int, h: int, shape: GridLayout.Shape, rng: RandomNumberGenerator, approach: int) -> Dictionary:
	var inset := 0
	if sitrep_id == "sitrep_standardcombat" and approach > 0:
		inset = maxi(0, (h - 2 * DEPTH - approach) / 2)
	var out := {
		"deployment": {Mission.PLAYERS: rect(2, h - DEPTH - inset, w - 4, DEPTH, w, h, shape), Mission.ENEMIES: rect(2, inset, w - 4, DEPTH, w, h, shape)},
		"zones": {}, "clear": [], "first_side": "", "sitrep": sitrep_id,
	}
	match sitrep_id:
		"sitrep_control", "sitrep_recon":
			# Four 4x4 zones, one per quadrant, mirrored so neither side is favored (the book:
			# "roughly symmetrical, or the map will be unbalanced").
			var dx := rng.randi_range(2, maxi(2, w / 4 - 2))
			var dy := rng.randi_range(DEPTH + 1, maxi(DEPTH + 1, h / 2 - 5))
			var spots := [[dx, dy], [w - dx - 4, dy], [dx, h - dy - 4], [w - dx - 4, h - dy - 4]]
			for i in range(4):
				out["zones"]["zone_%d" % (i + 1)] = rect(spots[i][0], spots[i][1], 4, 4, w, h, shape)
		"sitrep_holdout":
			var zone := rect(w / 2 - 5, h / 2 - 2, 10, 5, w, h, shape)
			out["zones"]["zone"] = zone
			out["deployment"][Mission.PLAYERS] = zone  # PCs deploy in the Control Zone.
			# Attackers can come from every side: the EDZ wraps the top and both flanks.
			var edz: Array = rect(2, 0, w - 4, DEPTH, w, h, shape)
			edz.append_array(rect(0, DEPTH, 3, h - DEPTH - 2, w, h, shape))
			edz.append_array(rect(w - 3, DEPTH, 3, h - DEPTH - 2, w, h, shape))
			out["deployment"][Mission.ENEMIES] = edz
		"sitrep_gauntlet":
			var zone := rect(w / 2 - 5, 0, 10, 5, w, h, shape)
			out["zones"]["zone"] = zone
			out["deployment"][Mission.ENEMIES] = zone  # The Control Zone is the EDZ.
			out["first_side"] = Mission.PLAYERS
		"sitrep_escort":
			# Extraction at the far edge; the enemy holds both flanks in the upper half, so the
			# squad pushes up the middle. A clear 3-wide route keeps the Objective moving.
			var ext := rect(w / 2 - 3, 0, 6, 3, w, h, shape)
			out["zones"]["extraction"] = ext
			var edz: Array = rect(1, DEPTH, maxi(3, w / 5), h / 3, w, h, shape)
			edz.append_array(rect(w - 1 - maxi(3, w / 5), DEPTH, maxi(3, w / 5), h / 3, w, h, shape))
			out["deployment"][Mission.ENEMIES] = edz
			out["clear"] = _route(Vector2i(w / 2, h - DEPTH), Vector2i(w / 2, 2), w, h, shape, rng)
		"sitrep_extraction":
			# Dash out to the Objective Zone near the enemy line and back; the allied
			# deployment zone is also the extraction zone.
			var obj := rect(w / 2 - 2, DEPTH + 2, 4, 4, w, h, shape)
			out["zones"]["objective"] = obj
			out["zones"]["extraction"] = out["deployment"][Mission.PLAYERS]
			out["clear"] = _route(Vector2i(w / 2, h - DEPTH), Vector2i(w / 2, DEPTH + 4), w, h, shape, rng)
	return out


## A wandering 3-wide path of cells between two map points (col, row).
static func _route(from: Vector2i, to: Vector2i, w: int, h: int, shape: GridLayout.Shape, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var seen := {}
	var phase := rng.randf() * TAU
	var amp := rng.randf_range(1.5, maxf(2.0, w * 0.12))
	var steps := absi(to.y - from.y)
	for k in range(steps + 1):
		var t := float(k) / maxf(1.0, steps)
		var row := int(round(lerpf(from.y, to.y, t)))
		var col := int(round(lerpf(from.x, to.x, t) + sin(t * PI * 1.5 + phase) * amp * sin(t * PI)))
		for dc in range(-1, 2):
			var c := clampi(col + dc, 0, w - 1)
			var cell := cell_of(c, clampi(row, 0, h - 1), shape)
			if not seen.has(cell):
				seen[cell] = true
				out.append([cell.x, cell.y])
	return out


static func cell_of(col: int, row: int, shape: GridLayout.Shape) -> Vector2i:
	return Vector2i(col - (row >> 1), row) if shape == GridLayout.Shape.HEX else Vector2i(col, row)


static func rect(c0: int, r0: int, cw: int, rh: int, w: int, h: int, shape: GridLayout.Shape) -> Array:
	var out: Array = []
	for r in range(maxi(r0, 0), mini(r0 + rh, h)):
		for c in range(maxi(c0, 0), mini(c0 + cw, w)):
			var cell := cell_of(c, r, shape)
			out.append([cell.x, cell.y])
	return out
