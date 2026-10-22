extends TestCase
## Weapon mods (tags: Mod, Core p.106; mods.json).

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(mounts: Array, t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": []})
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _act(name: String, params: Dictionary = {}) -> Dictionary:
	var p := params.duplicate()
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			p["ability"] = x["key"]
	return F.act(e, s, "activate", "a", p)


func test_tags_and_range_mods() -> void:
	_setup([{}, {}, {"weapons": ["mw_howitzer"], "mod": "wm_stabilizer_mod"}, ])
	var w := Weapons.find(a, "2:0")
	expect_eq(Weapons.range_value(w, "Range"), 25, "Stabilizer: +5 range")
	_setup([{"weapons": ["mw_assault_rifle"], "mod": "wm_nanocomposite_adaptation"}])
	w = Weapons.find(a, "0:0")
	expect(Weapons.has_tag(w, "tg_smart") and Weapons.has_tag(w, "tg_seeking"), "Nanocomposite: Smart and Seeking")
	_setup([{"weapons": ["mw_assault_rifle"], "mod": "wm_paracausal_mod"}])
	t.armor = 3
	F.load_dice(s, [15, 5])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(t.hp, 35, "Paracausal: damage can't be reduced (Armor ignored)")


func test_thermal_charge_and_shock_wreath() -> void:
	_setup([{"weapons": ["mw_tactical_melee_weapon"], "mod": "wm_thermal_charge"}], Vector2i(1, 0))
	var uses := int(Weapons.find(a, "0:0")["mod_uses"])
	F.load_dice(s, [15, 3, 4])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "thermal_charge": true})
	expect_eq(F.events_of(out, "bonus_damage")[0]["damage_type"], "Explosive", "+1d6 explosive on a hit")
	expect_eq(int(a.counters["mod_uses"]["0:0"]), uses - 1)
	_setup([{"weapons": ["mw_tactical_melee_weapon"], "mod": "wm_shock_wreath"}], Vector2i(1, 0))
	expect(not F.ok(_act("Shock Wreath", {"target": "t"})), "only after a hit")
	F.load_dice(s, [15, 3])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	F.load_dice(s, [4])
	out = _act("Shock Wreath", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.burn, 4)


func test_uncle_and_throughbolt() -> void:
	_setup([{"weapons": ["mw_assault_rifle"], "mod": "wm_uncle_class_comp_con"}])
	F.load_dice(s, [19])
	var out := _act("UNCLE", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	var srcs: Array = F.events_of(out, "attack_rolled")[0]["check"]["sources"]
	expect(srcs.any(func(x: Dictionary) -> bool: return x["label"] == "UNCLE"), "+2 Difficulty")
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "the weapon is locked until your next turn")
	_setup([{"weapons": ["mw_assault_rifle"], "mod": "wm_throughbolt_rounds"}], Vector2i(6, 0))
	var mid := F.mech(s, "mid", "enemies", Vector2i(2, 0))
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "throughbolt": [6, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(mid.hp, 8, "2 AP kinetic to everything on the line 3 path")


func test_phase_ready() -> void:
	_setup([{"weapons": ["mw_assault_rifle"], "mod": "wm_phase_ready_mod"}], Vector2i(5, 0))
	s.map.set_column(Vector2i(3, 0), 3)
	s.map.set_column(Vector2i(3, 1), 3)
	F.load_dice(s, [2, 15, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "phase": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "invisible_roll").size(), 1, "the target counts as Invisible")
