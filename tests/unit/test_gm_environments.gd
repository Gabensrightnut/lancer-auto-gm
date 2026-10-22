extends TestCase
## Rules environments from the world's weather (MissionGenerator): a sandstorm can bring
## Particulate Storms, a moon Low Gravity, at the chance the GM's "environments" dial sets.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _gen(mission_seed: int, landscape: String, weather: String, chance: float) -> Dictionary:
	var s := GmSettings.from_preset("Standard")
	s.environments = chance
	return MissionGenerator.generate(mission_seed, {"db": MissionTest.db(), "landscape": landscape, "weather": weather, "settings": s, "size": 20})


func test_weather_and_world_suggest_environments() -> void:
	var r := _gen(11, "desert_mesas", "sandstorm", 1.0)
	var m: Mission = r["mission"]
	var state: GameState = r["state"]
	expect_eq(m.environments, ["env_particulatestorms"])
	expect_eq(state.environments, ["env_particulatestorms"], "the rules engine reads them from the state")
	expect(m.briefing.contains("Environment: Particulate Storms") and m.briefing.contains("soft cover"), "the briefing has the book text: %s" % m.briefing)
	expect_eq(m.flavor["environments"][0]["name"], "Particulate Storms")
	expect_eq(_gen(12, "tundra", "blizzard", 1.0)["mission"].environments, ["env_extremecold"])
	expect_eq(_gen(13, "grassy_hills", "storm", 1.0)["mission"].environments, ["env_electricalstorms"])
	expect_eq(_gen(14, "moon", "clear", 1.0)["mission"].environments, ["env_lowgravity"])
	expect_eq(_gen(15, "asteroid", "clear", 1.0)["mission"].environments, ["env_lowgravity"])
	expect_eq(_gen(16, "ocean", "storm", 1.0)["mission"].environments, ["env_electricalstorms", "env_oceanworld"])
	expect_eq(_gen(17, "volcanic", "ashfall", 1.0)["mission"].environments, ["env_moltenworld"])
	expect_eq(_gen(18, "grassy_hills", "rain", 1.0)["mission"].environments, [], "rain is only a look")


func test_the_gm_dial_sets_the_chance() -> void:
	expect_eq(_gen(21, "desert_mesas", "sandstorm", 0.0)["mission"].environments, [], "dial at 0: storms are only a look")
	var with_rules := 0
	for i in range(40):
		if not _gen(100 + i, "desert_mesas", "sandstorm", 0.5)["mission"].environments.is_empty():
			with_rules += 1
	expect(with_rules > 8 and with_rules < 32, "about half the sandstorms bring their rules: %d of 40" % with_rules)
	expect_eq(GmSettings.from_preset("Standard").environments, 0.5)
	expect_eq(GmSettings.from_preset("Teaching").environments, 0.0, "the gentle preset keeps battles simple")
	expect_eq(GmSettings.from_dict({"preset": "Standard", "environments": 0.9}).environments, 0.9, "saved with the campaign's GM settings")


func test_environment_roll_changes_nothing_else() -> void:
	var a := _gen(31, "desert_mesas", "sandstorm", 0.0)
	var b := _gen(31, "desert_mesas", "sandstorm", 1.0)
	expect_eq(JSON.stringify(a["state"].map.to_dict()), JSON.stringify(b["state"].map.to_dict()), "same battlefield")
	expect_eq(a["state"].units.keys(), b["state"].units.keys(), "same forces")
	var again := _gen(31, "desert_mesas", "sandstorm", 0.5)
	expect_eq(again["mission"].environments, _gen(31, "desert_mesas", "sandstorm", 0.5)["mission"].environments, "same seed, same result")


func test_saved_and_announced() -> void:
	var r := _gen(41, "desert_mesas", "sandstorm", 1.0)
	var state: GameState = r["state"]
	expect_eq(GameState.from_dict(state.to_dict()).environments, ["env_particulatestorms"], "saved with the battle")
	expect_eq(Mission.from_dict(r["mission"].to_dict()).environments, ["env_particulatestorms"])
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), r["mission"])
	host.set_fill_empty_with_ai(true)
	var told: Array = []
	host.action_resolved.connect(func(_s: String, a: Dictionary, _r: RuleResult, e: Array) -> void:
		if a.get("type", "") == "gm_narrate":
			told.append_array(e))
	for i in range(6):
		director.step()
	expect(not told.is_empty(), "the GM announces the environment when combat starts")
	if not told.is_empty():
		expect_eq(told[0]["kind"], "environment")
		expect(str(told[0]["text"]).contains("soft cover"))
		expect(not told[0].has("seen_by"), "everyone sees it, both sides")
