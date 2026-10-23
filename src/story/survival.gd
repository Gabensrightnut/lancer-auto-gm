class_name Survival
extends RefCounted
## Food and water, per pilot (the food-and-water house rule, the user's; off by default). Each
## pilot has a food bar and a water bar (0-100) that run down with the clock: water lasts
## about 2-3 days, food 3-5 (inventory.json survival). Eating a food (or a field ration, which
## is both) puts back a full day's worth. With auto-eat on (the default; Settings → Gameplay),
## pilots eat and drink from their own stash when a bar gets low; with it off, you eat from
## the inventory yourself. Going without is a story matter with clear warnings (Hungry,
## Parched, then Starving, Dehydrated) and the existing +1 Difficulty on skill checks while
## hungry; no combat penalties. Cybernetic upgrades (house rule) cut the daily need, stacking,
## never below a quarter of a ration a day.

const REF := "Your idea, not a book rule"


static func cfg() -> Dictionary:
	return Inventory.data().get("survival", {})


static func on(campaign: Campaign) -> bool:
	return StoryHouseRules.on(campaign, Economy.R_FOOD)


## A pilot's daily need, as fractions of a ration: Vector2(food, water).
static func need(campaign: Campaign, pid: String) -> Vector2:
	var f := 1.0
	var w := 1.0
	if StoryHouseRules.on(campaign, "hr_cybernetics"):
		var mods: Dictionary = Inventory.data().get("need_mods", {})
		for imp: Variant in campaign.pilots.get(pid, {}).get("implants", []):
			var m: Dictionary = mods.get(str(imp), {})
			f += float(m.get("food", 0.0))
			w += float(m.get("water", 0.0))
	var floor_v := float(cfg().get("floor", 0.25))
	return Vector2(maxf(floor_v, f), maxf(floor_v, w))


static func need_text(campaign: Campaign, pid: String) -> String:
	var n := need(campaign, pid)
	return "Needs %s food, %s water per day" % [_num(n.x), _num(n.y)]


static func _num(v: float) -> String:
	return ("%d" % roundi(v)) if absf(v - roundf(v)) < 0.01 else ("%.2f" % v).rstrip("0").rstrip(".")


static func bars(story: StoryState, pid: String) -> Vector2:
	var r := Inventory.of(story, pid)
	return Vector2(float(r.get("food", 100.0)), float(r.get("water", 100.0)))


static func hungry(story: StoryState, campaign: Campaign, pid: String) -> bool:
	if not on(campaign):
		return false
	var b := bars(story, pid)
	var warn := float(cfg().get("warn_below", 35))
	return b.x < warn or b.y < warn


## Time passes: bars run down, auto-eat tops them up, warnings when they cross a line.
static func pass_hours(story: StoryState, campaign: Campaign, hours: float) -> Array:
	if not on(campaign) or hours <= 0.0:
		return []
	var events: Array = []
	var warn := float(cfg().get("warn_below", 35))
	var low := float(cfg().get("auto_eat_below", 50))
	var lines: Dictionary = cfg().get("lines", {})
	for pid: String in campaign.pilots:
		if not story.is_alive(pid):
			continue
		var r := Inventory.of(story, pid)
		var n := need(campaign, pid)
		var before := bars(story, pid)
		var f := before.x - hours / 24.0 * 100.0 / float(cfg().get("food_days", 4)) * n.x
		var w := before.y - hours / 24.0 * 100.0 / float(cfg().get("water_days", 2.5)) * n.y
		r["food"] = maxf(0.0, f)
		r["water"] = maxf(0.0, w)
		if bool(r.get("auto_eat", true)):
			events.append_array(_auto(story, campaign, pid, low))
		events.append_array(_warn(story, campaign, pid, before, warn, lines))
	return events


static func _auto(story: StoryState, campaign: Campaign, pid: String, low: float) -> Array:
	var events: Array = []
	var guard := 0
	while guard < 6:
		guard += 1
		var b := bars(story, pid)
		if b.x >= low and b.y >= low:
			break
		var item := ""
		if b.x < low and b.y < low and Inventory.count(story, pid, "ration") > 0:
			item = "ration"
		elif b.x < low and Inventory.count(story, pid, "food") > 0:
			item = "food"
		elif b.y < low and Inventory.count(story, pid, "water") > 0:
			item = "water"
		elif Inventory.count(story, pid, "ration") > 0:
			item = "ration"
		if item == "":
			break
		events.append_array(consume(story, campaign, pid, item))
	return events


## Eats or drinks one of something from the pilot's stash.
static func consume(story: StoryState, campaign: Campaign, pid: String, item: String) -> Array:
	if not Inventory.take(story, pid, item, 1):
		return []
	var r := Inventory.of(story, pid)
	var day_f := 100.0 / float(cfg().get("food_days", 4))
	var day_w := 100.0 / float(cfg().get("water_days", 2.5))
	var makes: Dictionary = Inventory.item_def(item).get("makes", {item: 1})
	if makes.has("food"):
		r["food"] = minf(100.0, float(r.get("food", 100.0)) + day_f * int(makes["food"]))
	if makes.has("water"):
		r["water"] = minf(100.0, float(r.get("water", 100.0)) + day_w * int(makes["water"]))
	return [{"type": "ate", "pilot": pid, "item": item, "text": "%s %s." % [campaign.pilots[pid].get("callsign", ""), {"food": "eats", "water": "drinks", "ration": "opens a field ration"}.get(item, "eats")], "quiet": true}]


static func eat_refusal(story: StoryState, campaign: Campaign, pid: String, item: String) -> String:
	if not on(campaign):
		return "Food isn't tracked (that house rule is off)."
	if not item in ["food", "water", "ration"]:
		return "You can't eat that."
	if Inventory.count(story, pid, item) <= 0:
		return "You don't have any."
	return ""


static func _warn(story: StoryState, campaign: Campaign, pid: String, before: Vector2, warn: float, lines: Dictionary) -> Array:
	var events: Array = []
	var now := bars(story, pid)
	var cs := str(campaign.pilots[pid].get("callsign", ""))
	for k: Array in [["food", before.x, now.x, "hungry", "starving"], ["water", before.y, now.y, "parched", "dehydrated"]]:
		var was := float(k[1])
		var is_ := float(k[2])
		if is_ <= 0.0 and was > 0.0:
			events.append({"type": "hungry" if k[0] == "food" else "thirsty", "pilot": pid, "level": k[4], "text": str(lines.get(k[4], "")).replace("{name}", cs), "label": REF})
		elif is_ < warn and was >= warn:
			events.append({"type": "hungry" if k[0] == "food" else "thirsty", "pilot": pid, "level": k[3], "text": str(lines.get(k[3], "")).replace("{name}", cs) + " (+1 Difficulty on skill checks until they eat and drink.)", "label": REF})
	# With no mech of their own, the supplies stowed in it are gone: every stretch of going
	# hungry like that feeds a grudge (Agendas).
	if hungry(story, campaign, pid) and Economy.wrecked(story, campaign).has(pid):
		events.append_array(Agendas.add(story, campaign, pid, "grievance", "going hungry since their mech was wrecked"))
	return events


## A meal out, or meals that come with the stay: everyone's bars full.
static func refill(story: StoryState, campaign: Campaign) -> void:
	for pid: String in campaign.pilots:
		var r := Inventory.of(story, pid)
		r["food"] = 100.0
		r["water"] = 100.0
