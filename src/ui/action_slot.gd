class_name ActionSlot
extends Control
## An empty slot on the action bar: a faint frame you can drop an action onto while the bar
## is unlocked.

var panel := 0
var index := -1
var bar: ActionBar


func _init(p: int, i: int, owner_bar: ActionBar) -> void:
	panel = p
	index = i
	bar = owner_bar
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.6))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.5, 0.65, 0.35 if ActionButton.drag_enabled else 0.18), false, 1.0)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return ActionButton.drag_enabled and data is Dictionary and data.has("action_id")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	bar.move_action(String(data["action_id"]), panel, index)
