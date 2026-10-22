class_name HubDemo
extends RefCounted
## A ready-made squad at a generated town in downtime, for screenshots and trying the hub
## without a full campaign: four LL0 pilots (one human seat, three AI squadmates).


static func make(seed_value: int = 12) -> Dictionary:
	var db := ContentDB.new()
	db.load_all()
	var c := Campaign.create("Hub demo")
	c.id = "c_demo_%d" % seed_value
	var crew := [
		["Ama Okafor", "Bluebird", {"sk_charm": 1, "sk_word_on_the_street": 1, "sk_patch": 1, "sk_investigate": 1}, "pbg_colonist", "steady"],
		["Rin Sato", "Kettle", {"sk_apply_fists_to_faces": 1, "sk_threaten": 1, "sk_assault": 1, "sk_survive": 1}, "pbg_mercenary", "bold"],
		["Teodor Vasquez-Lind", "Halo", {"sk_hack_or_fix": 1, "sk_invent_or_create": 1, "sk_read_a_situation": 1, "sk_spot": 1}, "pbg_mechanic", "curious"],
		["Priya Anand", "Saint", {"sk_lead_or_inspire": 1, "sk_stay_cool": 1, "sk_patch": 1, "sk_charm": 1}, "pbg_medic", "kind"],
	]
	var s := StoryState.new(seed_value)
	s.flags = c.story_flags
	var e := StoryEngine.new(db)
	var i := 0
	for row: Array in crew:
		var p := c.new_pilot(row[0], row[1])
		p["skills"] = row[2]
		p["background"] = row[3]
		i += 1
		e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p%d" % i, "pilot": p["id"], "ai": i > 1, "persona": row[4]}})
	e.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": seed_value}})
	s.phase = "level_up"
	e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	return {"db": db, "campaign": c, "story": s, "engine": e}
