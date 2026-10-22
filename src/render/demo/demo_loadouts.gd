class_name DemoLoadouts
extends RefCounted
## Picks plausible weapons for a frame's mounts so demo mechs have something in their
## hands. Prefers the frame's own manufacturer, then GMS. Not a rules-checked loadout.


static func for_frame(frame: Dictionary, content: ContentDB, variant: int = 0) -> Dictionary:
	var mfr: String = frame.get("source", "GMS")
	var mounts: Array = []
	var i := variant
	for m: String in frame.get("mounts", []):
		var sizes: Array = []
		match m:
			"Main/Aux":
				sizes = ["Main", "Auxiliary"]
			"Aux/Aux":
				sizes = ["Auxiliary", "Auxiliary"]
			"Flex":
				sizes = ["Main"]
			"Heavy":
				sizes = ["Heavy"]
			_:
				sizes = [m]
		var ids: Array = []
		for s: String in sizes:
			var w := pick(content, s, mfr, frame.get("id", "") + str(i))
			i += 1
			if w != "":
				ids.append(w)
		mounts.append({"mount": m, "weapons": ids, "mod": ""})
	return {"mounts": mounts, "systems": []}


static func pick(content: ContentDB, mount_size: String, mfr: String, seed_key: String) -> String:
	for source: String in [mfr, "GMS"]:
		var pool: Array = []
		for w: Dictionary in content.all("weapons"):
			if w.get("mount") == mount_size and w.get("source") == source and w.get("type") != "???":
				pool.append(w["id"])
		if not pool.is_empty():
			pool.sort()
			return pool[int(MeshKit.hash01(seed_key) * pool.size()) % pool.size()]
	return ""
