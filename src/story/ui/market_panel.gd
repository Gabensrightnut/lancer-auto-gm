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
		_box.add_child(StoryStyle.label("%s has %s. Squad fund: %s. Here, 1 manna = %d %s." % [_cs(_me()), Economy.describe(story, _me()), Economy.describe(story), Economy.rate(story), Economy.currency(story)], 15, StoryStyle.TEXT, 540))
		var fund := StoryStyle.button("Put 50 manna into the squad fund", 13)
		fund.tooltip_text = "The squad fund pays for shared things: the ship, your troops, passage."
		fund.pressed.connect(func() -> void: _send({"type": "fund_deposit", "params": {"pilot": _me(), "manna": 50}}))
		_box.add_child(fund)
		for o: Dictionary in Economy.offers(story, campaign, _me()):
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
		if not Economy.communal(story):
			var ex := HBoxContainer.new()
			_box.add_child(ex)
			var el := StoryStyle.label("Change money (only here):", 13, StoryStyle.DIM)
			el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ex.add_child(el)
			var b1 := StoryStyle.button("50 manna → %s" % Economy.currency(story), 13)
			b1.pressed.connect(func() -> void: _send({"type": "exchange", "params": {"to_manna": false, "amount": 50, "pilot": _me()}}))
			ex.add_child(b1)
			var b2 := StoryStyle.button("All %s → manna" % Economy.symbol(story), 13)
			b2.pressed.connect(func() -> void: _send({"type": "exchange", "params": {"to_manna": true, "amount": Economy.local(story, _me()), "pilot": _me()}}))
			ex.add_child(b2)
		if int(Economy.wallet(story).get("salvage", 0)) > 0:
			var sb := StoryStyle.button("Sell the salvage (%d manna)" % int(Economy.wallet(story)["salvage"]), 14)
			sb.pressed.connect(func() -> void: _send({"type": "sell_salvage", "params": {}}))
			_box.add_child(sb)
	if StoryHouseRules.on(campaign, Economy.R_FOOD):
		_food_section()
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
	if StoryHouseRules.any_on(campaign, [Economy.R_WALLET, Economy.R_FOOD]):
		_trade_section()
	_msg = StoryStyle.label("", 13, StoryStyle.GREEN, 540)
	_box.add_child(_msg)


func _cs(pid: String) -> String:
	return str(campaign.pilots.get(pid, {}).get("callsign", "You"))


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


## Your pack: food and water bars, what you carry, eating, packing field rations, selling.
func _food_section() -> void:
	var me := _me()
	var b := Survival.bars(story, me)
	_box.add_child(StoryStyle.label("%s's pack: %s." % [_cs(me), Inventory.describe(story, me)], 15, StoryStyle.TEXT, 540))
	_box.add_child(StoryStyle.label("Food %d%%  ·  Water %d%%  ·  %s." % [roundi(b.x), roundi(b.y), Survival.need_text(campaign, me)], 14,
		StoryStyle.RED if Survival.hungry(story, campaign, me) else StoryStyle.DIM, 540))
	var row := _row(_box)
	for it: Array in [["food", "Eat"], ["water", "Drink"], ["ration", "Open a ration"]]:
		var item := str(it[0])
		var eb := StoryStyle.button(str(it[1]), 13)
		eb.disabled = Inventory.count(story, me, item) <= 0
		eb.pressed.connect(func() -> void: _send({"type": "eat", "params": {"pilot": me, "item": item}}))
		row.add_child(eb)
	var pk := StoryStyle.button("Pack food + water into a ration", 13)
	pk.tooltip_text = "A sealed field pack keeps indefinitely, packs small, and sells for more than its parts."
	pk.disabled = Inventory.pack_refusal(story, me, 1, false) != ""
	pk.pressed.connect(func() -> void: _send({"type": "pack_ration", "params": {"pilot": me, "n": 1}}))
	row.add_child(pk)
	var auto := CheckBox.new()
	auto.text = "Auto-eat and drink"
	auto.button_pressed = bool(Inventory.of(story, me).get("auto_eat", true))
	auto.toggled.connect(func(on: bool) -> void: _send({"type": "set_auto_eat", "params": {"pilot": me, "on": on}}))
	_box.add_child(auto)
	if StoryHouseRules.on(campaign, Economy.R_WALLET) and not story.hub.is_empty():
		var sr := _row(_box)
		for id: String in ["ration", "food", "water"]:
			if Inventory.count(story, me, id) > 0:
				var sb := StoryStyle.button("Sell a %s (%d %s)" % [Inventory.item_name(id).to_lower(), Inventory.sell_price(story, id), Economy.symbol(story)], 13)
				var what := id
				sb.pressed.connect(func() -> void: _send({"type": "sell_item", "params": {"pilot": me, "item": what, "n": 1}}))
				sr.add_child(sb)


## Trading with a squadmate: offers waiting for you, and quick offers and gifts.
func _trade_section() -> void:
	var me := _me()
	_box.add_child(StoryStyle.label("TRADE", 16, StoryStyle.GOLD))
	for t: Dictionary in (story.flags.get(Inventory.TRADES, {}) as Dictionary).values():
		var row := _row(_box)
		var l := StoryStyle.label("%s offers %s for %s." % [_cs(str(t["from"])), Inventory._side_text(story, t["give"]), Inventory._side_text(story, t["get"])], 13, StoryStyle.TEXT, 380)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var tid := str(t["id"])
		if Inventory.mine_of(story, seat).has(str(t["to"])):
			var ok := StoryStyle.button("Accept", 13)
			ok.pressed.connect(func() -> void: _send({"type": "trade_answer", "params": {"trade": tid, "accept": true}}))
			row.add_child(ok)
			var no := StoryStyle.button("Decline", 13)
			no.pressed.connect(func() -> void: _send({"type": "trade_answer", "params": {"trade": tid, "accept": false}}))
			row.add_child(no)
		else:
			var cx := StoryStyle.button("Cancel", 13)
			cx.pressed.connect(func() -> void: _send({"type": "trade_cancel", "params": {"trade": tid}}))
			row.add_child(cx)
	for other: String in campaign.pilots:
		if other == me or not story.is_alive(other):
			continue
		var row := _row(_box)
		row.add_child(StoryStyle.label("%s:" % _cs(other), 13, StoryStyle.TEXT))
		var to := other
		if StoryHouseRules.on(campaign, Economy.R_FOOD) and Inventory.count(story, me, "ration") > 0:
			var g := StoryStyle.button("Give a ration", 13)
			g.pressed.connect(func() -> void: _send({"type": "trade_offer", "params": {"from": me, "to": to, "give": {"items": {"ration": 1}}, "get": {}}}))
			row.add_child(g)
		if StoryHouseRules.on(campaign, Economy.R_WALLET) and int(Economy.wallet(story, me).get("manna", 0)) >= 50:
			var gm := StoryStyle.button("Give 50 manna", 13)
			gm.pressed.connect(func() -> void: _send({"type": "trade_offer", "params": {"from": me, "to": to, "give": {"manna": 50}, "get": {}}}))
			row.add_child(gm)
		if StoryHouseRules.on(campaign, Economy.R_FOOD) and StoryHouseRules.on(campaign, Economy.R_WALLET) and Inventory.count(story, me, "ration") > 0:
			var sell := StoryStyle.button("Offer a ration for 15 manna", 13)
			sell.pressed.connect(func() -> void: _send({"type": "trade_offer", "params": {"from": me, "to": to, "give": {"items": {"ration": 1}}, "get": {"manna": 15}}}))
			row.add_child(sell)


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
