class_name DemoBattle
extends Node
## A playable demo battle on the real rules engine: players and enemies alternate as in
## Lancer, the players pick who goes next with "I'll go" on the turn-order bar, your turn waits
## for you (move, act, confirm, End Turn), and enemy turns play at a readable pace with the
## camera following. Host-side: it owns the GameState; the view gets ViewFilter output.

signal battle_over(winner: String)

const SEAT := "p1"

var content: ContentDB
var view: BattleView
var player: EventPlayer
var ui: CanvasLayer
var state: GameState
var engine: RulesEngine
var order_bar: TurnOrderBar
var bar: ActionBar
var turn: PlayerTurn
var banner: Label
## Set by screenshot staging to pick units without clicks.
var auto_pick := ""
var running := false

var _filter := ViewFilter.new()


func setup(db: ContentDB, battle_view: BattleView, events: EventPlayer, layer: CanvasLayer) -> void:
	content = db
	view = battle_view
	player = events
	ui = CanvasLayer.new()
	ui.layer = layer.layer
	add_child(ui)
	order_bar = TurnOrderBar.new()
	ui.add_child(order_bar)
	order_bar.i_will_go.connect(_on_i_will_go)
	bar = ActionBar.new()
	bar.visible = false
	ui.add_child(bar)
	banner = Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 10)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.modulate.a = 0.0
	ui.add_child(banner)
	player.on_banner = show_banner
	player.camera = view.tactical
	turn = PlayerTurn.new()
	turn.bar = bar
	turn.view = view
	turn.player = player
	turn.db = content
	add_child(turn)
	turn.setup(ui)
	turn.acted.connect(sync_views)


## Builds the GameState from a map and a roster (DemoRoster format) and shows the seat's view.
func load_battle(map: BattleMap, roster: Dictionary, offset: Vector2) -> void:
	state = GameState.new(1234, map.grid.shape)
	state.map = map
	state.seats = {SEAT: {"name": "You", "side": "players"}}
	engine = RulesEngine.new()
	for id: String in roster:
		var r: Array = roster[id]
		var mounts: Array = []
		for m: Array in r[6]:
			mounts.append({"weapons": m[1], "mod": ""})
		var u := UnitFactory.build_mech(content, id, r[0], {"mounts": mounts, "systems": []}, {"ll": 2, "hull": 1, "agility": 1, "systems": 1, "engineering": 1})
		u.name = r[5]
		u.side = r[1]
		u.controller = SEAT if r[1] == "players" else "gm"
		u.cell = DemoMap.cell_at(map, r[2] + offset.x, r[3] + offset.y)
		u.level = map.ground_height(u.cell)
		state.add_unit(u)
	turn.state = state
	turn.engine = engine
	player.local_units = []
	for u: Unit in state.units_on_side("players"):
		player.local_units.append(u.id)
	view.clear_units()
	var v := _filter.view_for(state, SEAT)
	for id: String in v["units"]:
		var ud: Dictionary = v["units"][id]
		if not ud.get("hidden", false):
			view.add_unit(ud)
	for mv: MechView in view.units.values():
		mv.face(Vector3(offset.x + 8, 0, offset.y + (6 if mv.unit["side"] == "players" else 11)))
	_render_portraits()
	_update_order()


func _render_portraits() -> void:
	for id: String in state.units:
		var u := state.unit(id)
		var model := MechBuilder.build(content.frame(u.content_id), (view.units[id] as MechView).unit.get("loadout", {}), content)
		order_bar.portraits[id] = TurnOrderBar.render_portrait(self, model, model.height)


func _update_order() -> void:
	var units: Array = []
	for u: Unit in state.units.values():
		var e := {"id": u.id, "name": u.name, "side": u.side, "acted": state.acted.has(u.id) or u.destroyed,
			"active": state.active_unit == u.id, "frame": u.content_id}
		if u.side == "players" or _filter.knows_stats("players", u.id):
			e["hp"] = [u.hp, u.max_hp]
		units.append(e)
	var active := state.unit(state.active_unit)
	order_bar.set_data({"round": maxi(1, state.round_number), "picking_side": state.turn_side, "local_side": "players",
		"active_name": active.name if active else "", "units": units})


func show_banner(text: String) -> void:
	var vp := banner.get_viewport_rect().size
	banner.text = text.to_upper()
	banner.add_theme_font_size_override("font_size", int(vp.y * 0.045))
	banner.position = Vector2(0, vp.y * 0.22)
	banner.size = Vector2(vp.x, vp.y * 0.08)
	var tw := banner.create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, Fx.t(0.25))
	tw.tween_interval(Fx.t(1.0))
	tw.tween_property(banner, "modulate:a", 0.0, Fx.t(0.4))


## Copies public stats from the state onto the views (after each action).
func sync_views() -> void:
	var v := _filter.view_for(state, SEAT)
	for id: String in view.units:
		var ud: Dictionary = v["units"].get(id, {})
		var mv: MechView = view.units[id]
		for k: String in ["hp", "max_hp", "heat", "heat_cap", "structure", "max_structure", "overshield", "statuses", "burn"]:
			if ud.has(k):
				mv.unit[k] = ud[k]
		mv.refresh()
	_update_order()


func start() -> void:
	running = true
	var out := engine.submit(state, {"type": "start_combat", "params": {"first_side": "players"}})
	await player.play(out["events"])
	_update_order()
	_next()


func _winner() -> String:
	for side: String in ["players", "enemies"]:
		var alive := false
		for u: Unit in state.units_on_side(side):
			alive = alive or not u.destroyed
		if not alive:
			return "enemies" if side == "players" else "players"
	return ""


func _next() -> void:
	sync_views()
	var w := _winner()
	if w != "":
		show_banner("%s win" % ("Players" if w == "players" else "Enemies"))
		running = false
		battle_over.emit(w)
		return
	if state.turn_side == "players":
		# The players choose who goes next: wait for "I'll go" (or the staged pick).
		if auto_pick != "":
			var id := auto_pick
			auto_pick = ""
			_on_i_will_go(id)
		return
	var waiting := TurnRules.waiting(state, "enemies")
	if waiting.is_empty():
		return
	var uid := waiting[0].id
	await _start_turn(uid)
	var events := DemoAI.take_turn(state, engine, uid)
	await player.play(events)
	_next()


func _start_turn(uid: String) -> void:
	var out := engine.submit(state, {"type": "start_turn", "actor": uid})
	_update_order()
	await player.play(out["events"])
	_update_order()


func _on_i_will_go(uid: String) -> void:
	if state.turn_side != "players" or state.active_unit != "":
		return
	await _start_turn(uid)
	turn.begin(uid)
	await turn.finished
	_next()
