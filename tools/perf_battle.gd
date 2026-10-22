extends SceneTree
## Frame-rate check: 8 Blender-made mechs (Everest and Blackbeard models) on a big generated
## board with the full world dressing, from the tactical camera. Vsync off.
##   godot --path . --resolution 1920x1080 -s res://tools/perf_battle.gd -- [size] [lod on|off]
## Prints average/min fps, frame time and draw stats for a wide view and a close view.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size := int(args[0]) if args.size() > 0 else 40
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var db := ContentDB.new()
	db.load_all()
	var view := BattleView.new()
	view.content = db
	root.add_child(view)
	var g := MissionGenerator.generate(4, {"db": db, "shape": "hex", "landscape": "grassy_hills", "size": size})
	var map: BattleMap = (g["state"] as GameState).map
	view.set_map(map, (g["mission"] as Mission).flavor.get("kit", "grassy_hills"))
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in map.cells():
		var p := map.grid.to_world(c)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var mid := (lo + hi) * 0.5
	var frames := ["mf_standard_pattern_i_everest", "mf_blackbeard"]
	for i in range(8):
		var c := map.grid.from_world(mid + Vector3((i % 4 - 1.5) * 3.0, 0, (i / 4 - 0.5) * 4.0))
		view.add_unit({"id": "m%d" % i, "name": "Mech %d" % i, "side": "players" if i < 4 else "enemies", "content_id": frames[i % 2],
			"size": 1, "cell": [c.x, c.y], "level": map.ground_height(c), "loadout": {"mounts": [{"weapons": ["mw_assault_rifle"]}]},
			"hp": 10, "max_hp": 10, "heat": 0, "heat_cap": 6, "structure": 4, "max_structure": 4})
	for v in [["wide", mid + Vector3(0, 1, 0), maxf(hi.x - lo.x, hi.z - lo.z) * 0.95, -45.0], ["tactical", mid + Vector3(0, 1, 0), 16.0, -42.0], ["close", mid + Vector3(0, 1, 0), 7.0, -30.0]]:
		view.tactical.look_at_point(v[1], v[2])
		view.tactical.pitch = v[3]
		view.tactical.snap()
		for i in range(60):
			await process_frame
		var times: Array = []
		var t0 := Time.get_ticks_usec()
		for i in range(240):
			var a := Time.get_ticks_usec()
			# Slow orbit so the frame isn't static.
			view.tactical.yaw += 0.15
			await process_frame
			times.append((Time.get_ticks_usec() - a) / 1000.0)
		var total := (Time.get_ticks_usec() - t0) / 1000000.0
		times.sort()
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("PERF %s map %dx%d: avg %.1f fps, 1%% low %.1f fps (frame %.1f ms avg, %.1f ms p99), draw calls %d, primitives %d" % [
			v[0], size, size, 240.0 / total, 1000.0 / float(times[int(times.size() * 0.99)]), total * 1000.0 / 240.0, float(times[int(times.size() * 0.99)]), draws, prims])
	print("GPU ", RenderingServer.get_video_adapter_name(), " / ", RenderingServer.get_video_adapter_vendor())
	quit()
