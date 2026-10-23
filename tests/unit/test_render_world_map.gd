extends TestCase
## The world map draws a region from net's region shape: every tile has a height and a
## color, props are instanced, sites are marked, the squad's tokens follow the view,
## clicks find the tile under the cursor.

const Demo = preload("res://src/render/demo/world_map_demo.gd")


func test_region_tokens_sites_and_picking() -> void:
	var v := WorldMapView.new()
	var db := ContentDB.new()
	db.load_all()
	v.content = db
	var r: Dictionary = Demo.sample_region()
	v.load_region(r)
	expect_eq(v._heights.size(), 24 * 18, "every tile has a height")
	expect_eq(v.sites.size(), 4, "sites are marked")
	expect(v.find_child("Props_trees", true, false) != null, "forests are instanced trees")
	expect(v.height_at(Vector2(10, 4)) >= 0.0, "nothing under the sea plane is walked on")
	v.show_view({"squad": {"a": {"at": [10.0, 9.0], "on": "mech", "in_area": ""}, "b": {"at": [6.0, 11.0], "on": "foot", "in_area": "camp"}}})
	expect_eq(v.tokens.size(), 2, "a token per squad member")
	expect(not (v.tokens["b"] as Node3D).visible, "inside a site: hidden")
	expect_eq(v.site_at(Vector2i(14, 8)), "town")
	var above := v.to_world(Vector2(12, 9)) + Vector3(0, 6, 4)
	expect_eq(v.tile_under(above, (v.to_world(Vector2(12, 9)) - above).normalized()), Vector2i(12, 9), "a click finds its tile")
	v.free()
