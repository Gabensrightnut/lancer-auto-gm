extends SceneTree
## Renders a scene and saves a PNG, so visuals can be checked without opening the editor:
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/main.tscn out.png [frames]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var out: String = args[1] if args.size() > 1 else "user://screenshot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 10
	root.add_child((load(scene_path) as PackedScene).instantiate())
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
