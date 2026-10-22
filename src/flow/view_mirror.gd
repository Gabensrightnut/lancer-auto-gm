class_name ViewMirror
extends RefCounted
## A GameState rebuilt from one seat's view (ViewFilter output), so the turn UI can run its
## previews (movement arrow, hit chance, action list) without ever seeing a secret. Hidden
## enemies are left out; unscanned enemies have default stats. Never submitted anywhere:
## actions go to the host, which judges them on the real state.


## Updates `mirror` in place (the turn UI keeps a reference to it) from `view`.
static func sync(mirror: GameState, view: Dictionary) -> void:
	# Terrain doesn't change during a battle: read it once.
	if view.has("map") and (mirror.map == null or mirror.map.cells().is_empty()):
		mirror.map = BattleMap.from_dict(view["map"])
	mirror.units.clear()
	for id: String in view.get("units", {}):
		var d: Dictionary = view["units"][id]
		if d.get("hidden", false):
			continue  # Statuses, Hidden: no position to plan against.
		mirror.units[id] = Unit.from_dict(d)
	mirror.round_number = int(view.get("round", 0))
	mirror.phase = str(view.get("phase", GameState.PHASE_SETUP))
	mirror.active_unit = str(view.get("active_unit", ""))
	mirror.acted = PackedStringArray(view.get("acted", []))
	mirror.turn_side = str(view.get("turn_side", ""))
	mirror.first_side = str(view.get("first_side", ""))
	mirror.intel = (view.get("intel", {}) as Dictionary).duplicate(true)
	mirror.seats = (view.get("seats", {}) as Dictionary).duplicate(true)
	mirror.rulings = (view.get("rulings", {}) as Dictionary).duplicate(true)
	mirror.packs = (view.get("packs", []) as Array).duplicate(true)


static func build(view: Dictionary) -> GameState:
	var shape: GridLayout.Shape = GridLayout.Shape[str(view.get("map", {}).get("shape", "HEX"))]
	var m := GameState.new(0, shape)
	m.map = null
	sync(m, view)
	return m
