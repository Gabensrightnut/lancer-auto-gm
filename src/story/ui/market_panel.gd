class_name MarketPanel
extends PanelContainer
## The hub's market for the money-and-supplies house rules (Economy; "Your idea, not a book
## rule"): prices in this world's money, buying, working it off when you can't pay, selling
## salvage, printer access for wrecked mechs, free food at a friendly hub. Only reachable
## while one of those rules is on.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"
var _box: VBoxContainer
var _msg: Label


func _init() -> void:
	visible = false
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.custom_minimum_size.x = 560
	add_child(_box)


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat


static func available(c: Campaign) -> bool:
	return StoryHouseRules.any_on(c, [Economy.R_WALLET, Economy.R_FOOD, Economy.R_PRINTERS, Economy.R_FIGHT])


func open() -> void:
	visible = true
	refresh()


func _process(_d: float) -> void:
	if visible:
		reset_size()
		position = (get_viewport_rect().size - size) / 2.0


func _me() -> String:
	var pid := story.pilot_of_seat(seat)
	if pid == "" or not story.is_alive(pid):
		for p: String in campaign.pilots:
			if story.is_alive(p):
				return p
	return pid


func refresh() -> void:
	for ch in _box.get_children():
		ch.queue_free()
	var head := HBoxContainer.new()
	_box.add_child(head)
	var t := StoryStyle.label("MARKET  ·  %s" % story.hub.get("name", ""), 20, StoryStyle.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := StoryStyle.button("Close (B)", 13)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	var on: Array = StoryHouseRules.definitions().filter(func(r: Dictionary) -> bool: return StoryHouseRules.on(campaign, str(r["id"])))
	_box.add_child(StoryStyle.label("House rules on: %s. %s." % [", ".join(PackedStringArray(on.map(func(r: Dictionary) -> String: return r["name"]))), Economy.LABEL], 12, StoryStyle.DIM, 540))
	if StoryHouseRules.on(campaign, Economy.R_WALLET):
		Economy.start(story, campaign, Economy.R_WALLET)
		_box.add_child(StoryStyle.label("The squad has %s. Here, 1 manna = %d %s." % [Economy.describe(story), Economy.rate(story), Economy.currency(story)], 15, StoryStyle.TEXT, 540))
		for o: Dictionary in Economy.offers(story, campaign):
			var row := HBoxContainer.new()
			_box.add_child(row)
			var l := StoryStyle.label("%s  ·  %s" % [o["name"], o["text"]], 14, StoryStyle.TEXT if bool(o["affordable"]) else StoryStyle.DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var item := str(o["item"])
			if bool(o["affordable"]):
				var b := StoryStyle.button("Buy", 13)
				b.pressed.connect(func() -> void: _send({"type": "buy", "params": {"item": item, "pilot": _me()}}))
				row.add_child(b)
			elif StoryHouseRules.on(campaign, Economy.R_FIGHT):
				var f := StoryStyle.button("Work it off", 13)
				f.tooltip_text = "Can't afford it? Take a job for the seller instead."
				f.pressed.connect(func() -> void: _send({"type": "fight_for_it", "params": {"item": item, "pilot": _me()}}))
				row.add_child(f)
		if int(Economy.wallet(story).get("salvage", 0)) > 0:
			var sb := StoryStyle.button("Sell the salvage (%d manna)" % int(Economy.wallet(story)["salvage"]), 14)
			sb.pressed.connect(func() -> void: _send({"type": "sell_salvage", "params": {}}))
			_box.add_child(sb)
	if StoryHouseRules.on(campaign, Economy.R_FOOD):
		_box.add_child(StoryStyle.label("Food and water: %d days for the squad." % Economy.rations(story), 15, StoryStyle.TEXT))
		if not StoryHouseRules.on(campaign, Economy.R_WALLET):
			var rb := StoryStyle.button("Stock up on food and water", 14)
			rb.disabled = Economy.restock_refusal(story, campaign) != ""
			rb.tooltip_text = Economy.restock_refusal(story, campaign)
			rb.pressed.connect(func() -> void: _send({"type": "restock", "params": {}}))
			_box.add_child(rb)
	if StoryHouseRules.on(campaign, Economy.R_PRINTERS):
		_box.add_child(StoryStyle.label("Printer here: %s" % ("yes" if Economy.has_printer(story) else "no"), 15, StoryStyle.TEXT))
		for pid: String in Economy.wrecked(story, campaign):
			var row := HBoxContainer.new()
			_box.add_child(row)
			var l := StoryStyle.label("%s's mech is wrecked." % campaign.pilots.get(pid, {}).get("callsign", ""), 14, StoryStyle.RED)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var why := Economy.printer_refusal(story, campaign, pid)
			var pb := StoryStyle.button("Reprint it", 13)
			pb.disabled = why != ""
			pb.tooltip_text = why
			var who := pid
			pb.pressed.connect(func() -> void: _send({"type": "use_printer", "params": {"pilot": who}}))
			row.add_child(pb)
			if why.begins_with("Printer access costs") and StoryHouseRules.on(campaign, Economy.R_FIGHT):
				var fb := StoryStyle.button("Work it off", 13)
				fb.pressed.connect(func() -> void: _send({"type": "fight_for_it", "params": {"item": "printer", "pilot": who}}))
				row.add_child(fb)
	_msg = StoryStyle.label("", 13, StoryStyle.GREEN, 540)
	_box.add_child(_msg)


func _send(a: Dictionary) -> void:
	a["seat"] = "gm" if seat == "gm" else seat
	var r := engine.submit(story, campaign, a)
	if not r["ok"]:
		refresh()
		_msg.text = "✕ " + str(r["reason"])
		_msg.add_theme_color_override("font_color", StoryStyle.RED)
		return
	var said: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x.has("text")).map(func(x: Dictionary) -> String: return x["text"])
	story_events.emit(r["events"])
	refresh()
	_msg.text = "✓ " + " ".join(PackedStringArray(said))
