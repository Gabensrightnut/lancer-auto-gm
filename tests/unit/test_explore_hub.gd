extends TestCase
## Hubs on foot: layout, where people stand, walking into buildings, and the check pop-up's
## plain-words breakdown.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func test_layout_has_a_building_for_every_role() -> void:
	var t := Setup.setup(70)
	var s: StoryState = t["story"]
	var kinds := {}
	for spot: Dictionary in s.hub["spots"]:
		kinds[spot["kind"]] = true
	for id: String in s.hub["npcs"]:
		var spot_kind := str(s.npcs[id]["spot"])
		expect(kinds.has(spot_kind), "%s stands at a %s" % [s.npcs[id]["role"], spot_kind])
	expect(kinds.has("bar"), "a town has somewhere to Get a Damn Drink")
	for spot: Dictionary in s.hub["spots"]:
		var p := Vector2(float(spot["pos"][0]), float(spot["pos"][1]))
		expect(p.length() <= HubLayout.BOUNDS, "inside the walkable area")


func test_people_stand_apart() -> void:
	var t := Setup.setup(71)
	var s: StoryState = t["story"]
	var per := {}
	var spots: Array = []
	for id: String in s.hub["npcs"]:
		var kind := str(s.npcs[id]["spot"])
		var i := int(per.get(kind, 0))
		per[kind] = i + 1
		spots.append(HubLayout.npc_position(s.hub, kind, i))
	for a in range(spots.size()):
		for b in range(a + 1, spots.size()):
			expect((spots[a] as Vector2).distance_to(spots[b]) > 0.8, "NPCs %d and %d don't overlap" % [a, b])


func test_walking_into_a_building_stops_at_the_wall() -> void:
	var hub := HubScene.new()
	var box := Transform3D(Basis(Vector3.UP, 0.7), Vector3(10, 0, 4))
	hub._blockers = [{"inv": box.affine_inverse(), "half": Vector2(3, 2)}]
	var inside := Vector2(10, 4)
	var out := hub._push_out(inside)
	var lp := box.affine_inverse() * Vector3(out.x, 0, out.y)
	expect(absf(lp.x) >= 2.99 or absf(lp.z) >= 1.99, "pushed out to the wall")
	expect_eq(hub._push_out(Vector2(0, 0)), Vector2(0, 0), "open ground is left alone")
	hub.free()


func test_check_breakdown_in_plain_words() -> void:
	var pilot := {"id": "p", "skills": {"sk_charm": 2}, "background": "pbg_noble"}
	var r := NarrativeCheck.roll(Dice.new(5), pilot, {"skills": ["sk_charm"], "tags": ["etiquette"], "risky": true, "consequence": "They see through you."})
	var text := StoryCheckPopup.breakdown(r)
	expect("d20 rolled %d" % int(r["d20"]) in text)
	expect("Charm +4" in text, text)
	expect("Accuracy" in text, "background accuracy shown")
	expect(("= %d vs 10" % int(r["total"])) in text)
	expect("RISKY" in text)


func test_portrait_and_figure_build() -> void:
	var look := Portrait.look_for_pilot({"id": "pilot_x"})
	expect(look.has("skin") and look.has("hair_style"))
	expect_eq(Portrait.look_for_pilot({"id": "pilot_x"}), look, "same pilot, same face")
	var fig := PilotFigure.new().build(look, "Bluebird")
	expect(fig.get_child_count() > 2)
	fig.free()
