class_name MechStyles
extends RefCounted
## Manufacturer looks and per-frame signature features for the generated mechs.
## The shapes are our own; Lancer Tactics is only the reference for "readable at a glance".

## Paint schemes per manufacturer (lancer-data `source`).
const PALETTES := {
	"GMS": {
		"primary": Color(0.70, 0.72, 0.74), "secondary": Color(0.20, 0.30, 0.44),
		"trim": Color(0.16, 0.17, 0.19), "glow": Color(0.35, 0.85, 1.0),
		"metal": 0.5, "rough": 0.42,
	},
	"IPS-N": {
		"primary": Color(0.16, 0.24, 0.40), "secondary": Color(0.82, 0.80, 0.74),
		"trim": Color(0.14, 0.14, 0.15), "glow": Color(1.0, 0.62, 0.18),
		"metal": 0.45, "rough": 0.5,
	},
	"SSC": {
		"primary": Color(0.86, 0.84, 0.79), "secondary": Color(0.72, 0.56, 0.22),
		"trim": Color(0.10, 0.10, 0.11), "glow": Color(0.95, 0.35, 0.85),
		"metal": 0.35, "rough": 0.3,
	},
	"HORUS": {
		"primary": Color(0.09, 0.09, 0.10), "secondary": Color(0.22, 0.24, 0.22),
		"trim": Color(0.05, 0.05, 0.06), "glow": Color(0.35, 1.0, 0.45),
		"metal": 0.7, "rough": 0.35,
	},
	"HA": {
		"primary": Color(0.40, 0.09, 0.07), "secondary": Color(0.62, 0.50, 0.28),
		"trim": Color(0.13, 0.11, 0.10), "glow": Color(1.0, 0.45, 0.12),
		"metal": 0.6, "rough": 0.4,
	},
}

## Body proportions per manufacturer, before mech type and per-frame variation.
const BODY := {
	"GMS": {"leg_len": 0.46, "leg_thick": 0.10, "digi": false, "torso_w": 0.37, "torso_h": 0.30, "torso_d": 0.28, "taper": 1.0, "head": "visor", "head_size": 0.11, "pad": "box", "pad_size": 1.0, "arm_thick": 0.085, "hunch": 0.0, "bevel": 0.025},
	"IPS-N": {"leg_len": 0.44, "leg_thick": 0.12, "digi": false, "torso_w": 0.42, "torso_h": 0.28, "torso_d": 0.28, "taper": 1.12, "head": "sunk", "head_size": 0.10, "pad": "round", "pad_size": 1.3, "arm_thick": 0.10, "hunch": 6.0, "bevel": 0.04},
	"SSC": {"leg_len": 0.50, "leg_thick": 0.075, "digi": true, "torso_w": 0.34, "torso_h": 0.28, "torso_d": 0.22, "taper": 1.18, "head": "long", "head_size": 0.10, "pad": "fin", "pad_size": 0.9, "arm_thick": 0.065, "hunch": 0.0, "bevel": 0.02},
	"HORUS": {"leg_len": 0.44, "leg_thick": 0.09, "digi": true, "torso_w": 0.38, "torso_h": 0.30, "torso_d": 0.26, "taper": 0.85, "head": "slit", "head_size": 0.10, "pad": "spike", "pad_size": 1.1, "arm_thick": 0.08, "hunch": 10.0, "bevel": 0.012},
	"HA": {"leg_len": 0.45, "leg_thick": 0.11, "digi": false, "torso_w": 0.42, "torso_h": 0.30, "torso_d": 0.28, "taper": 1.25, "head": "crest", "head_size": 0.09, "pad": "slab", "pad_size": 1.25, "arm_thick": 0.105, "hunch": 3.0, "bevel": 0.018},
}

## Multipliers by mech type (frame `mechtype`): bulk, legs, arm reach.
const MECHTYPE := {
	"Striker": {"bulk": 0.95, "legs": 1.05, "arms": 1.1, "hunch": 6.0},
	"Defender": {"bulk": 1.12, "legs": 0.95, "arms": 1.0, "hunch": 0.0},
	"Artillery": {"bulk": 1.08, "legs": 0.95, "arms": 0.95, "hunch": 0.0},
	"Controller": {"bulk": 0.95, "legs": 1.0, "arms": 0.95, "hunch": 2.0},
	"Support": {"bulk": 1.0, "legs": 1.0, "arms": 1.0, "hunch": 0.0},
	"Balanced": {"bulk": 1.0, "legs": 1.0, "arms": 1.0, "hunch": 0.0},
}

## Signature silhouette features for each core frame (frame id -> feature tags).
## Unknown frames still get a full model from manufacturer + mech type + their id.
const FEATURES := {
	"mf_standard_pattern_i_everest": ["antenna"],
	"mf_blackbeard": ["grapple_arms", "spikes"],
	"mf_drake": ["tower_shield", "heavy_legs"],
	"mf_lancaster": ["cargo_crane", "heavy_legs"],
	"mf_nelson": ["crest", "spear_fins"],
	"mf_raleigh": ["cowl", "bandolier"],
	"mf_tortuga": ["heavy_legs", "sensor_mast", "hunched"],
	"mf_vlad": ["spikes", "spike_crown"],
	"mf_black_witch": ["halo_ring"],
	"mf_deaths_head": ["sniper_head", "stabilizers"],
	"mf_dusk_wing": ["wings"],
	"mf_metalmark": ["cloak_fins"],
	"mf_monarch": ["missile_pods"],
	"mf_mourning_cloak": ["cloak_fins", "arm_blades"],
	"mf_swallowtail": ["wings", "sensor_mast"],
	"mf_balor": ["nanite_cloud", "heavy_legs", "hunched"],
	"mf_goblin": ["hunched", "antennae", "tail"],
	"mf_gorgon": ["serpent_heads"],
	"mf_hydra": ["drone_orbit"],
	"mf_manticore": ["tail", "pylons"],
	"mf_minotaur": ["horns"],
	"mf_pegasus": ["orbit_ring"],
	"mf_barbarossa": ["heavy_legs", "reactor_back", "siege_frame"],
	"mf_genghis": ["fuel_tanks"],
	"mf_iskander": ["mine_racks", "antennae"],
	"mf_napoleon": ["tower_shield", "hunched"],
	"mf_saladin": ["shield_emitters", "heavy_legs"],
	"mf_sherman": ["reactor_back"],
	"mf_tokugawa": ["heat_fins", "crest"],
}


static func palette(manufacturer: String) -> Dictionary:
	return PALETTES.get(manufacturer, PALETTES["GMS"])


## Body parameters for a frame: manufacturer base, mech type multipliers, then a small
## per-frame variation seeded by the frame id so every frame has its own silhouette.
static func body(frame: Dictionary) -> Dictionary:
	var mfr: String = frame.get("source", "GMS")
	var b: Dictionary = (BODY.get(mfr, BODY["GMS"]) as Dictionary).duplicate()
	var types: Array = frame.get("mechtype", ["Balanced"])
	var bulk := 1.0
	var legs := 1.0
	var arms := 1.0
	var hunch := 0.0
	for t: String in types:
		var m: Dictionary = MECHTYPE.get(t, MECHTYPE["Balanced"])
		bulk *= m["bulk"]
		legs *= m["legs"]
		arms *= m["arms"]
		hunch += m["hunch"]
	var id: String = frame.get("id", "")
	var j := func(i: int, amount: float) -> float: return 1.0 + (MeshKit.hash01(id, i) - 0.5) * 2.0 * amount
	b["torso_w"] *= bulk * j.call(1, 0.08)
	b["torso_d"] *= bulk * j.call(2, 0.08)
	b["torso_h"] *= j.call(3, 0.08)
	b["leg_len"] *= legs * j.call(4, 0.07)
	b["leg_thick"] *= bulk * j.call(5, 0.1)
	b["arm_thick"] *= bulk * j.call(6, 0.1)
	b["arm_len"] = 0.2 * arms * j.call(7, 0.06)
	b["pad_size"] *= j.call(8, 0.12)
	b["hunch"] += hunch
	b["features"] = FEATURES.get(id, [])
	if "heavy_legs" in b["features"]:
		b["leg_thick"] *= 1.25
		b["digi"] = false
	if "hunched" in b["features"]:
		b["hunch"] += 12.0
	b["seed"] = id
	return b
