extends TestCase
## Fight length (GM dial): encounter size, deployment distance and when an enemy commander
## considers yielding; never HP, damage or any rule.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _gen(fight_length: String) -> Dictionary:
	var s := LobbyModel.gm_settings_for("Standard", fight_length)
	return MissionGenerator.generate(4242, {"db": MissionTest.db(), "sitrep": "sitrep_standardcombat", "size": 30, "players": 4, "settings": s, "environments": []})


func test_lengths_scale_the_gms_choices_only() -> void:
	var counts := {}
	var gaps := {}
	var hp := {}
	for fl: String in ["short", "standard", "long"]:
		var r := _gen(fl)
		var state: GameState = r["state"]
		counts[fl] = state.units_on_side(Mission.ENEMIES).size()
		var top := 0
		for c: Array in r["mission"].deployment[Mission.ENEMIES]:
			top = maxi(top, int(c[1]))
		var bottom := 999
		for c: Array in r["mission"].deployment[Mission.PLAYERS]:
			bottom = mini(bottom, int(c[1]))
		gaps[fl] = bottom - top
		hp[fl] = state.unit("p1").max_hp
	expect(counts["short"] < counts["standard"] and counts["standard"] < counts["long"], "fewer or more enemies: %s" % str(counts))
	expect(gaps["short"] < gaps["standard"] and gaps["standard"] < gaps["long"], "closer or farther deployment: %s" % str(gaps))
	expect(hp["short"] == hp["standard"] and hp["standard"] == hp["long"], "rules like HP never change")


func test_saved_with_the_gm_settings_and_kept_across_styles() -> void:
	var s := LobbyModel.gm_settings_for("Ruthless", "long")
	var back := GmSettings.from_dict(s.to_dict())
	expect_eq(back.fight_length, "long")
	expect_eq(back.preset, "Ruthless")
	expect_eq(GmSettings.from_dict({"preset": "Standard", "fight_length": "nonsense"}).fight_length, "standard")
	var c := Campaign.create("Length")
	var l := LobbyModel.for_host(c, MissionTest.db(), 77)
	l.set_fight_length("short")
	expect_eq(c.gm_settings["fight_length"], "short")
	l.set_preset("Cautious")
	expect_eq(c.gm_settings["fight_length"], "short", "changing the GM style keeps the fight length")


func test_commanders_yield_sooner_or_later() -> void:
	var b := {"round": 2, "enemy_ids": ["a", "b", "c", "d", "e", "f"], "enemy_down": ["a", "b"], "rival_structure": 4, "rival_max_structure": 4}
	b["yield_at"] = 0.33
	expect(Rivals.enemy_losing(b), "short: a third of their force down is enough")
	b["yield_at"] = 0.5
	expect(not Rivals.enemy_losing(b), "standard: needs half")
	b["enemy_down"] = ["a", "b", "c"]
	expect(Rivals.enemy_losing(b))
	b["yield_at"] = 0.67
	expect(not Rivals.enemy_losing(b), "long: they hold out longer")


## World maps grow to about 60 per side: the dial, not the map size, sets the starting
## distance, and the extra space is flanking room.
func test_bigger_maps_keep_the_starting_distance() -> void:
	var gap := func(lay: Dictionary) -> int:
		var top := 0
		for c: Array in lay["deployment"][Mission.ENEMIES]:
			top = maxi(top, int(c[1]))
		var bottom := 999
		for c: Array in lay["deployment"][Mission.PLAYERS]:
			bottom = mini(bottom, int(c[1]))
		return bottom - top
	for shape: GridLayout.Shape in [GridLayout.Shape.SQUARE, GridLayout.Shape.HEX]:
		for sitrep: String in ["sitrep_standardcombat", "sitrep_control", "sitrep_recon", "sitrep_gauntlet", "sitrep_escort", "sitrep_extraction"]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			var small: int = gap.call(SitrepLayout.layout(sitrep, 30, 34, shape, rng, 14))
			var big_lay := SitrepLayout.layout(sitrep, 60, 60, shape, rng, 14)
			expect_eq(gap.call(big_lay), small, "%s: same starting distance on a 60x60 map" % sitrep)
			for cells: Array in [big_lay["deployment"][Mission.PLAYERS], big_lay["deployment"][Mission.ENEMIES]] + big_lay["zones"].values():
				for c: Array in cells:
					var col := int(c[0]) + (int(c[1]) >> 1) if shape == GridLayout.Shape.HEX else int(c[0])
					expect(col >= 0 and col < 60 and int(c[1]) >= 0 and int(c[1]) < 60, "%s: on the map" % sitrep)
	var rng2 := RandomNumberGenerator.new()
	var hold := SitrepLayout.layout("sitrep_holdout", 60, 60, GridLayout.Shape.SQUARE, rng2, 14)
	var cols := []
	for c: Array in hold["deployment"][Mission.ENEMIES]:
		cols.append(int(c[0]))
	expect(cols.min() >= 13 and cols.max() <= 46, "holdout: attackers start near the zone, not at the far flanks")
