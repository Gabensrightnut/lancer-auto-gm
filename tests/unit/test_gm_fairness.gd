extends TestCase
## Generated battlefields are fair (MapFairness): balanced cover between the two halves, part
## of each deployment zone out of the other's sight, and every objective reachable on foot
## by Size 1, 2 and 3. 50 seeds for every landscape, cycling through every sitrep layout,
## hex and square grids and map sizes 20-40.

const SEEDS := 50
const SITREPS := ["sitrep_standardcombat", "sitrep_control", "sitrep_holdout", "sitrep_gauntlet",
	"sitrep_escort", "sitrep_extraction", "sitrep_recon"]


func test_every_landscape_is_fair_for_50_seeds() -> void:
	for land: String in TerrainGen.LANDSCAPES:
		var fails: Array = []
		for s in range(SEEDS):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([land, s, "layout"])
			var wr := RandomNumberGenerator.new()
			wr.seed = hash([land, s, "world"])
			var w := 20 + (s * 7) % 21
			var h := clampi(int(w * (0.75 + 0.25 * ((s * 13) % 5) / 4.0)), 20, 40)
			var shape := GridLayout.Shape.SQUARE if s % 2 else GridLayout.Shape.HEX
			var sitrep: String = SITREPS[s % SITREPS.size()]
			var bf := MissionGenerator.battlefield(rng, wr, sitrep, w, h, shape, land)
			# Check again from scratch rather than trusting the generator's own report.
			var r := MapFairness.check(bf["map"], bf["layout"], h)
			if not r["ok"]:
				fails.append("seed %d %s %dx%d: cover %s hidden %s %s" % [s, sitrep, w, h, r["cover"], r["hidden"], r["unreachable"]])
		expect(fails.is_empty(), "%s: %d/%d unfair maps, e.g. %s" % [land, fails.size(), SEEDS, fails.slice(0, 2)])


func test_control_zones_are_mirrored() -> void:
	for shape: GridLayout.Shape in [GridLayout.Shape.HEX, GridLayout.Shape.SQUARE]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var lay := SitrepLayout.layout("sitrep_control", 30, 26, shape, rng)
		var zones: Dictionary = lay["zones"]
		expect_eq(zones.size(), 4, "four Control Zones")
		var centers: Array[Vector2] = []
		for z: String in zones:
			var sum := Vector2.ZERO
			for c: Array in zones[z]:
				var cr := MapFairness._col_row(Vector2i(c[0], c[1]), shape)
				sum += Vector2(cr.x, cr.y)
			centers.append(sum / (zones[z] as Array).size())
		# Each zone has a partner mirrored through the map's center.
		for c in centers:
			var mirror := Vector2(29, 25) - c
			var found := false
			for d in centers:
				if d.distance_to(mirror) < 0.6:
					found = true
			expect(found, "zone at %s has a mirrored partner" % c)


func test_sitrep_layouts_have_their_areas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var want := {"sitrep_control": ["zone_1", "zone_2", "zone_3", "zone_4"], "sitrep_recon": ["zone_1", "zone_4"],
		"sitrep_holdout": ["zone"], "sitrep_gauntlet": ["zone"], "sitrep_escort": ["extraction"],
		"sitrep_extraction": ["objective", "extraction"], "sitrep_standardcombat": []}
	for sitrep: String in want:
		var lay := SitrepLayout.layout(sitrep, 30, 24, GridLayout.Shape.HEX, rng)
		for z: String in want[sitrep]:
			expect((lay["zones"] as Dictionary).has(z) and not (lay["zones"][z] as Array).is_empty(), "%s has %s" % [sitrep, z])
		expect(not (lay["deployment"]["players"] as Array).is_empty() and not (lay["deployment"]["enemies"] as Array).is_empty(), "%s deployment" % sitrep)
	# Escort and extraction keep a clear route to the objective.
	var esc := SitrepLayout.layout("sitrep_escort", 30, 24, GridLayout.Shape.SQUARE, rng)
	expect((esc["clear"] as Array).size() > 20, "escort route")


func test_lava_and_boiling_mud_are_dangerous() -> void:
	for land: String in ["molten_world", "toxic_swamp"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		var map := TerrainGen.generate(rng, 30, 26, GridLayout.Shape.HEX, {}, land, "")
		var hazards := 0
		for c in map.cells():
			var col := map.column(c)
			if col.has_tag("lava") or col.has_tag("toxic"):
				expect(col.has_tag(BattleMap.TAG_DANGEROUS), "%s %s liquid is dangerous" % [land, c])
				hazards += 1
		expect(hazards > 10, "%s has hazards (%d)" % [land, hazards])
