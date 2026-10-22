class_name CostIcon
extends Control
## A small drawn icon for an action cost (our own shapes): Quick, Full, Free, Reaction,
## Protocol, Move, plus Heat, Charges and Overcharge badges that carry a number.

const COLORS := {
	"quick": Color(0.55, 0.95, 0.45), "full": Color(1.0, 0.62, 0.2), "free": Color(0.8, 0.82, 0.86),
	"reaction": Color(0.95, 0.45, 0.95), "protocol": Color(0.35, 0.85, 1.0), "move": Color(0.4, 0.7, 1.0),
	"heat": Color(1.0, 0.45, 0.12), "charges": Color(0.95, 0.85, 0.4), "overcharge": Color(1.0, 0.3, 0.25),
}
const NAMES := {
	"quick": "Quick action", "full": "Full action", "free": "Free action", "reaction": "Reaction",
	"protocol": "Protocol (start of turn)", "move": "Movement", "heat": "Heat", "charges": "Uses left",
	"overcharge": "Overcharge heat",
}

var kind := "quick"
var text := ""
var dimmed := false


func _init(k: String = "quick", t: String = "", px: float = 26.0) -> void:
	kind = k
	text = t
	var w := px if t == "" else px + 8.0 + 9.0 * t.length()
	custom_minimum_size = Vector2(w, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var col: Color = COLORS.get(kind, Color.WHITE)
	if dimmed:
		col = Color(0.4, 0.4, 0.44)
	var s := size.y
	var c := Vector2(s / 2.0, s / 2.0)
	var r := s * 0.42
	match kind:
		"quick":
			_chevron(c, r, col)
		"full":
			_chevron(c - Vector2(r * 0.35, 0), r * 0.85, col)
			_chevron(c + Vector2(r * 0.45, 0), r * 0.85, col)
		"free":
			draw_arc(c, r * 0.8, 0, TAU, 20, col, 2.5, true)
		"reaction":
			draw_arc(c, r * 0.75, -PI * 0.15, PI * 1.45, 20, col, 3.0, true)
			var tip := c + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r * 0.75
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-6, -5), tip + Vector2(5, -2), tip + Vector2(-1, 7)]), col)
		"protocol":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col.darkened(0.3))
			draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 2.0, true)
		"move":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, r * 0.1), c + Vector2(r * 0.3, r * 0.1), c + Vector2(r * 0.3, r), c + Vector2(-r * 0.3, r), c + Vector2(-r * 0.3, r * 0.1), c + Vector2(-r * 0.8, r * 0.1)]), col)
		"heat":
			# A flame: teardrop of three points.
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.7, r * 0.2), c + Vector2(r * 0.45, r * 0.8), c + Vector2(-r * 0.45, r * 0.8), c + Vector2(-r * 0.7, r * 0.2)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.2), c + Vector2(r * 0.3, r * 0.5), c + Vector2(-r * 0.3, r * 0.5)]), Color(1, 0.85, 0.4) if not dimmed else col.lightened(0.2))
		"charges":
			for i in range(3):
				draw_rect(Rect2(c + Vector2(-r + i * r * 0.72, -r * 0.6), Vector2(r * 0.5, r * 1.2)), col)
		"overcharge":
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.6, r * 0.15), c + Vector2(-r * 0.05, r * 0.15), c + Vector2(-r * 0.25, r), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2)]), col)
	if text != "":
		var font := get_theme_default_font()
		draw_string(font, Vector2(s + 2, s * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.62), col.lightened(0.25))


func _chevron(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.6, 0), c + Vector2(-r * 0.6, r), c + Vector2(-r * 0.15, 0)]), col)
