class_name HotSeat
extends RefCounted
## Several players taking turns at one screen. Each seat still only sees its own view, so
## between seats the UI shows a "Pass to <player>" screen that hides the board.
##
## UI flow:
##   handoff_requested(seat, name) -> hide the board, show "Pass to <name>" + a Ready button
##   Ready pressed                  -> confirm_handoff()
##   view_updated(seat, view, events) -> draw `view` and animate `events` for `seat`
## Events that happened while a seat was away are kept and shown when it gets the screen
## back. Works alongside online seats: the same NetHost can also have a room open.

signal handoff_requested(next_seat: String, display_name: String)
signal view_updated(seat: String, view: Dictionary, events: Array)

var host: NetHost
## Seats played at this screen, in the order they sit.
var seats := PackedStringArray()
## The seat whose view is on screen ("" before the first handoff).
var current_seat := ""
## Waiting for the next player to take the screen.
var awaiting_handoff := false
var next_seat := ""

var _latest_view: Dictionary = {}  # seat -> view
var _unseen: Dictionary = {}  # seat -> events not shown to that seat yet


func _init(net_host: NetHost, local_seats: Array) -> void:
	host = net_host
	for s: String in local_seats:
		host.add_local_seat(s)
		seats.append(s)
		_unseen[s] = []
	host.local_update.connect(_on_local_update)
	host.updates_sent.connect(_on_updates_sent)


## Starts play: builds every seat's view and hands the screen to `first_seat`.
func start(first_seat: String = "") -> void:
	host.send_updates()
	pass_to(first_seat if first_seat != "" else seats[0])


## Submits an action as the seat at the screen.
func submit(action: Dictionary) -> Dictionary:
	return host.submit(current_seat, action)


## "I'll go": the people at this screen choose who acts next (any of their seats' units, or an
## AI squadmate). The screen then passes to that unit's seat if it's another person's.
func pick_next(unit_id: String) -> Dictionary:
	return host.submit(current_seat if current_seat != "" else seats[0], {"type": "start_turn", "actor": unit_id})


## Asks for the screen to go to `seat` (e.g. the players chose who acts next).
func pass_to(seat: String) -> void:
	if not seat in seats or (seat == current_seat and not awaiting_handoff):
		return
	awaiting_handoff = true
	next_seat = seat
	handoff_requested.emit(seat, _display_name(seat))


## The next player has the screen: show their view and what they missed.
func confirm_handoff() -> void:
	if not awaiting_handoff:
		return
	awaiting_handoff = false
	current_seat = next_seat
	next_seat = ""
	_show(current_seat)


## Hands the screen over if the unit now acting belongs to another seat at this screen
## (not for seats the AI is playing: their turns happen on whoever's screen is up).
func check_turn() -> void:
	# A reaction question (Brace, Overwatch...) goes to the asked unit's seat first.
	var asked := host.state.unit(str(host.state.pending.get("unit", "")))
	if asked != null and asked.controller in seats and asked.controller != current_seat and not host.is_ai_seat(asked.controller):
		pass_to(asked.controller)
		return
	var u := host.state.unit(host.state.active_unit)
	if u != null and u.controller in seats and u.controller != current_seat and not host.is_ai_seat(u.controller):
		pass_to(u.controller)


func _on_updates_sent(_events: Array) -> void:
	check_turn()


func _on_local_update(seat: String, view: Dictionary, events: Array) -> void:
	if not _unseen.has(seat):
		return
	_latest_view[seat] = view
	(_unseen[seat] as Array).append_array(events)
	if seat == current_seat and not awaiting_handoff:
		_show(seat)


func _show(seat: String) -> void:
	var events: Array = _unseen[seat]
	_unseen[seat] = []
	view_updated.emit(seat, _latest_view.get(seat, {}), events)


func _display_name(seat: String) -> String:
	return str(host.state.seats.get(seat, {}).get("name", seat))
