extends SceneTree
## Renders a scene and saves a PNG (or JPG if the path ends in .jpg), so visuals can be checked without opening the editor:
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/main.tscn out.png [frames] [extra...]
## Extra arguments go to the scene root's `screenshot_setup(args)` if it has one (it may be a
## coroutine), so a scene can stage a specific moment before the capture.
## A scene can also take several shots in one run: give `out.png` as a pattern containing
## `%s` and have `screenshot_setup` return an array of tags; the scene's
## `screenshot_stage(tag)` is awaited before each capture, saved as out with %s = tag.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/main.tscn"
	var out: String = args[1] if args.size() > 1 else "user://screenshot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 10
	var extra := args.slice(3)
	var scene := (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var tags: Variant = null
	if scene.has_method("screenshot_setup"):
		tags = await scene.screenshot_setup(extra)
	if tags is Array and "%s" in out:
		for tag: String in tags:
			await scene.screenshot_stage(tag)
			await _capture(out % tag, frames)
	else:
		await _capture(out, frames)
	quit()


func _capture(path: String, frames: int) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if path.get_extension().to_lower() in ["jpg", "jpeg"]:
		img.save_jpg(path, 0.85)
	else:
		img.save_png(path)
	print("saved ", path)
