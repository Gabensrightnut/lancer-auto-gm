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


## `approach` (GM dial, GmSettings.approach): the most rows between the two deployment zones
## (0 = deploy at the map edges), for every sitrep: on big maps the fight still starts close
## (first contact by about the second turn for Speed 4 mechs), and the rest is flanking room.
## Holdout's attackers start half that far from the zone; an escort runs 1.5 times as long.
static func layout(sitrep_id: String, w: int, h: int, shape: GridLayout.Shape, rng: RandomNumberGenerator, approach: int = 0) -> Dictionary:
	# The fight happens in a band of rows: both deployment zones and the rows between them,
	# `approach` rows apart (the GM's distance dial), so a big map doesn't mean a long walk.
	# Rows behind the zones and the columns past the deployment width are flanking room.
	var gap := (approach if approach > 0 else h - 2 * DEPTH)
	if sitrep_id == "sitrep_escort":
		gap = int(gap * 1.5)  # an escort is a journey
	gap = clampi(gap, 6, maxi(6, h - 2 * DEPTH))
	var band_h := mini(h, 2 * DEPTH + gap)
	var top := (h - band_h) / 2
	var bottom := top + band_h  # first row after the band
	var dw := clampi(int(w * 0.6), mini(w - 4, 16), w - 4)
	var c0 := (w - dw) / 2
	var out := {
		"deployment": {Mission.PLAYERS: rect(c0, bottom - DEPTH, dw, DEPTH, w, h, shape), Mission.ENEMIES: rect(c0, top, dw, DEPTH, w, h, shape)},
		"zones": {}, "clear": [], "first_side": "", "sitrep": sitrep_id, "band": [top, bottom],
	}
	match sitrep_id:
		"sitrep_control", "sitrep_recon":
			# Four 4x4 zones, one per quadrant of the battle band, mirrored so neither side is
			# favored (the book: "roughly symmetrical, or the map will be unbalanced"). They can
			# sit out on the flanks, past the deployment zones.
			var dx := rng.randi_range(2, maxi(2, w / 4 - 2))
			var dy := rng.randi_range(DEPTH + 1, maxi(DEPTH + 1, band_h / 2 - 5))
			var spots := [[dx, top + dy], [w - dx - 4, top + dy], [dx, bottom - dy - 4], [w - dx - 4, bottom - dy - 4]]
			for i in range(4):
				out["zones"]["zone_%d" % (i + 1)] = rect(spots[i][0], spots[i][1], 4, 4, w, h, shape)
		"sitrep_holdout":
			var zr := h / 2 - 2
			var zc := w / 2 - 5
			var zone := rect(zc, zr, 10, 5, w, h, shape)
			out["zones"]["zone"] = zone
			out["deployment"][Mission.PLAYERS] = zone  # PCs deploy in the Control Zone.
			# Attackers can come from three sides, `g` spaces out from the zone.
			var g := clampi(approach / 2 if approach > 0 else 99, 4, 14)
			var r_top := maxi(0, zr - g - DEPTH)
			var c_left := maxi(0, zc - g - 3)
			var c_right := mini(w - 3, zc + 10 + g)
			var edz: Array = rect(maxi(0, zc - g), r_top, mini(w, 10 + 2 * g), DEPTH, w, h, shape)
			edz.append_array(rect(c_left, r_top + DEPTH, 3, mini(h - r_top - DEPTH, zr + 5 - r_top), w, h, shape))
			edz.append_array(rect(c_right, r_top + DEPTH, 3, mini(h - r_top - DEPTH, zr + 5 - r_top), w, h, shape))
			out["deployment"][Mission.ENEMIES] = edz
		"sitrep_gauntlet":
			var zone := rect(w / 2 - 5, top, 10, 5, w, h, shape)
			out["zones"]["zone"] = zone
			out["deployment"][Mission.ENEMIES] = zone  # The Control Zone is the EDZ.
			out["first_side"] = Mission.PLAYERS
		"sitrep_escort":
			# Extraction at the far end of the band; the enemy holds both flanks in its upper
			# half, so the squad pushes up the middle. A clear 3-wide route keeps the Objective
			# moving.
			var ext := rect(w / 2 - 3, top, 6, 3, w, h, shape)
			out["zones"]["extraction"] = ext
			var fw := maxi(3, w / 5)
			var edz: Array = rect(maxi(1, c0 - fw / 2), top + DEPTH, fw, band_h / 3, w, h, shape)
			edz.append_array(rect(mini(w - 1 - fw, c0 + dw - fw / 2), top + DEPTH, fw, band_h / 3, w, h, shape))
			out["deployment"][Mission.ENEMIES] = edz
			out["clear"] = _route(Vector2i(w / 2, bottom - DEPTH), Vector2i(w / 2, top + 2), w, h, shape, rng)
		"sitrep_extraction":
			# Dash out to the Objective Zone near the enemy line and back; the allied
			# deployment zone is also the extraction zone.
			var obj := rect(w / 2 - 2, top + DEPTH + 2, 4, 4, w, h, shape)
			out["zones"]["objective"] = obj
			out["zones"]["extraction"] = out["deployment"][Mission.PLAYERS]
			out["clear"] = _route(Vector2i(w / 2, bottom - DEPTH), Vector2i(w / 2, top + DEPTH + 4), w, h, shape, rng)
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
