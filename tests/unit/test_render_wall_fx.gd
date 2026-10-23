extends TestCase
## Shots meeting walls and barriers look like what the rules did: the path comes from the
## event, the weapon's mod, id and tags; walls on the line are found from the real terrain;
## barrier crossings come from the zones on the board; every book item is mapped.

static var _db: ContentDB


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _unit(wid: String, mod: String = "") -> Dictionary:
	return {"loadout": {"mounts": [{"mount": "Main", "weapons": [wid], "mod": mod}],
		"weapons": [{"key": "w0", "id": wid, "mount": 0, "tags": db().weapon(wid).get("tags", [])}]}}


func test_paths_follow_event_mod_weapon_and_tags() -> void:
	var e := {"weapon": "w0"}
	expect_eq(WallFx.path_for(e, db().weapon("mw_assault_rifle"), _unit("mw_assault_rifle")), "", "a plain rifle shoots straight")
	expect_eq(WallFx.path_for(e, db().weapon("mw_mortar"), _unit("mw_mortar")), "arc", "Arcing lobs over")
	expect_eq(WallFx.path_for(e, db().weapon("mw_smartgun"), _unit("mw_smartgun")), "seek", "Seeking curves around")
	expect_eq(WallFx.path_for(e, db().weapon("mw_assault_rifle"), _unit("mw_assault_rifle", "wm_phase_ready_mod")), "phase", "Phase-Ready mod: through the wall")
	expect_eq(WallFx.path_for(e, db().weapon("mw_assault_rifle"), _unit("mw_assault_rifle", "wm_throughbolt_rounds")), "throughbolt", "Throughbolt punches through")
	expect_eq(WallFx.path_for({"weapon": "w0", "phase": true}, db().weapon("mw_assault_rifle"), _unit("mw_assault_rifle")), "phase", "the event's phase flag wins")
	expect_eq(WallFx.path_for(e, db().weapon("mw_fold_knife"), _unit("mw_fold_knife")), "teleport", "Fold Knife folds space")


func test_every_book_item_is_mapped() -> void:
	var items: Dictionary = WallFx.data()["items"]
	for id: String in items:
		var known := id.begins_with("tg_") or not db().weapon(id).is_empty() or not db().system(id).is_empty() or not db().frame(id).is_empty() or id.begins_with("t_") or id.begins_with("wm_")
		expect(known, "%s is a real book item" % id)
	for w: Dictionary in db().all("weapons"):
		for t: Variant in w.get("tags", []):
			var tid := String((t as Dictionary).get("id", "")) if t is Dictionary else ""
			if tid in ["tg_arcing", "tg_seeking"]:
				expect(WallFx.path_for({"weapon": "w0"}, w, {}) in WallFx.PATHS, "%s has a path" % w["id"])


func test_walls_on_the_line_and_barrier_crossings() -> void:
	var bv := BattleView.new()
	var m := BattleMap.flat(GridLayout.Shape.SQUARE, 10, 4)
	m.column(Vector2i(5, 1)).ground = 4  # a tall wall in the middle
	bv.set_map(m, "urban_ruins")
	var a := bv.cell_pos(Vector2i(1, 1), 0) + Vector3.UP * 0.6
	var b := bv.cell_pos(Vector2i(8, 1), 0) + Vector3.UP * 0.6
	expect_eq(WallFx.blocks(bv, a, b).size(), 1, "one wall between them")
	var c := bv.cell_pos(Vector2i(1, 3), 0) + Vector3.UP * 0.6
	var d := bv.cell_pos(Vector2i(8, 3), 0) + Vector3.UP * 0.6
	expect(WallFx.blocks(bv, c, d).is_empty(), "a clear line has none")
	expect(WallFx.max_top(bv, a, b) >= 4 * GridLayout.LEVEL_HEIGHT, "the lob clears the wall")
	bv.zones.add_zone({"id": "h1", "kind": "hardlight", "cells": [[4, 3], [5, 3]]})
	expect_eq(WallFx.barrier_crossings(bv, c, d).size(), 2, "the shot crosses the hardlight wall in and out")
	expect(WallFx.barrier_crossings(bv, a, b).is_empty(), "a line away from it doesn't")
	expect(WallFx.is_barrier_deployable("Stasis Barrier"), "barrier deployables shatter and flicker")
	bv.free()
