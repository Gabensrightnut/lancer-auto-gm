class_name Icons
extends RefCounted
## Official LANCER icons (COMP/CON, GPL-3.0, assets/icons/lancer/). The SVGs have no fill,
## so they are rasterized here in white at the size asked for (crisp at any scale) and
## tinted with modulate or the color passed to RichTextLabel.add_image.
## Exports must include the raw .svg files (export filter "assets/icons/lancer/*.svg").

const DIR := "res://assets/icons/lancer/"

const DAMAGE := {"Kinetic": "kinetic", "Energy": "energy", "Explosive": "explosive", "Heat": "heat",
	"Burn": "burn", "Variable": "variable"}
const RANGE := {"Range": "range", "Threat": "threat", "Blast": "blast", "Burst": "burst", "Cone": "cone", "Line": "line"}
const COST := {"quick": "activation_quick", "full": "activation_full", "free": "free_action",
	"reaction": "reaction", "protocol": "protocol", "move": "", "overcharge": "overcharge",
	"quick_tech": "tech_quick", "full_tech": "tech_full"}
const STATUS := {"Lock On": "condition_lockon", "Jammed": "condition_jammed", "Immobilized": "condition_immobilized",
	"Shredded": "condition_shredded", "Slowed": "condition_slow", "Stunned": "condition_stunned",
	"Danger Zone": "status_dangerzone", "Engaged": "status_engaged", "Exposed": "status_exposed",
	"Hidden": "status_hidden", "Invisible": "status_invisible", "Prone": "status_prone",
	"Shut Down": "status_shutdown", "Down and Out": "status_downandout", "Intangible": "status_intangible",
	"Burn": "burning", "Impaired": "difficulty"}
const MANUFACTURER := {"GMS": "gms", "IPS-N": "ipsn", "SSC": "ssc", "HORUS": "horus", "HA": "ha"}
## Colors the book/COMP/CON uses for damage types and costs (approximate, our own picks).
const COLORS := {
	"kinetic": Color(0.85, 0.85, 0.85), "energy": Color(0.35, 0.8, 1.0), "explosive": Color(1.0, 0.6, 0.2),
	"heat": Color(1.0, 0.45, 0.12), "burn": Color(1.0, 0.35, 0.15), "variable": Color(0.75, 0.55, 1.0),
	"activation_quick": Color(0.55, 0.95, 0.45), "activation_full": Color(1.0, 0.62, 0.2),
	"free_action": Color(0.8, 0.82, 0.86), "reaction": Color(0.95, 0.45, 0.95), "protocol": Color(0.35, 0.85, 1.0),
	"overcharge": Color(1.0, 0.3, 0.25), "tech_quick": Color(0.4, 1.0, 0.6), "tech_full": Color(0.4, 1.0, 0.6),
	"structure": Color(0.92, 0.92, 0.95), "reactor": Color(1.0, 0.55, 0.3), "repair": Color(0.6, 0.9, 1.0),
}

static var _cache: Dictionary = {}


static func exists(icon_name: String) -> bool:
	return FileAccess.file_exists(DIR + icon_name + ".svg")


## The icon as a white texture `px` pixels tall. Returns null if the icon doesn't exist.
static func tex(icon_name: String, px: int = 32) -> Texture2D:
	var key := "%s@%d" % [icon_name, px]
	if _cache.has(key):
		return _cache[key]
	var path := DIR + icon_name + ".svg"
	if icon_name == "" or not FileAccess.file_exists(path):
		return null
	var svg := FileAccess.get_file_as_string(path)
	svg = svg.replace("<svg", "<svg fill=\"#ffffff\"")
	var img := Image.new()
	if img.load_svg_from_string(svg, maxf(0.1, px / 24.0)) != OK:
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func color(icon_name: String) -> Color:
	return COLORS.get(icon_name, Color(0.9, 0.92, 0.95))


static func damage(dtype: String) -> String:
	return DAMAGE.get(dtype, "kinetic")


static func cost(c: String) -> String:
	return COST.get(c, "activation_quick")


static func status(s: String) -> String:
	return STATUS.get(s, "marker")


## Writes text with inline icons into a RichTextLabel. Tokens: {icon:name} draws the icon in
## its own color, {icon:name:RRGGBB} in a given color. Everything else is BBCode.
static func write(rtl: RichTextLabel, text: String, px: int = 18) -> void:
	var re := RegEx.create_from_string("\\{icon:([a-z0-9_\\-]+)(?::([0-9a-fA-F]{6}))?\\}")
	var pos := 0
	for m in re.search_all(text):
		rtl.append_text(text.substr(pos, m.get_start() - pos))
		var icon_name := m.get_string(1)
		var t := tex(icon_name, px * 2)
		if t:
			var c := color(icon_name) if m.get_string(2) == "" else Color.html(m.get_string(2))
			rtl.add_image(t, px, px, c, INLINE_ALIGNMENT_CENTER)
		pos = m.get_end()
	rtl.append_text(text.substr(pos))


## "{icon:...}" token for a damage type, e.g. dmg_token("Energy").
static func dmg_token(dtype: String) -> String:
	return "{icon:%s}" % damage(dtype)
