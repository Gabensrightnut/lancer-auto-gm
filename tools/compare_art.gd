extends SceneTree
## Side-by-side check of a modeled frame against its reference art:
##   godot --path . -s res://tools/compare_art.gd -- <frame_id> <art.png> <out.png> [yaw] [pitch] [guide.glb[;guide2.glb@y]] [weapons] [top] [bottom]
## `top`/`bottom` are where the mech's body (feet to highest body part, weapons excluded)
## sits in the art, as fractions of the art's height, so both are drawn at the same scale.
## Renders the frame (MechBuilder, real loadout) at the art's angle on a plain background and
## writes one image: art | model | (optional) TripoSR blockout at the same camera.
## `weapons` is a comma list of weapon ids, filled into the frame's mounts in order.
## Reference art and blockouts stay in /local (never committed or shipped).

const H := 900

var _top := 0.05
var _bottom := 0.97


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var frame_id: String = a[0]
	var art_path: String = a[1]
	var out: String = a[2]
	var yaw := float(a[3]) if a.size() > 3 else 15.0
	var pitch := float(a[4]) if a.size() > 4 else -8.0
	var guide: String = a[5] if a.size() > 5 and a[5] != "-" else ""
	var weapons: Array = Array(a[6].split(",")) if a.size() > 6 and a[6] != "" else []
	_top = float(a[7]) if a.size() > 7 else 0.05
	_bottom = float(a[8]) if a.size() > 8 else 0.97
	var db := ContentDB.new()
	db.load_all()
	var multi := art_path == "-" or art_path == "rom"
	var art := Image.load_from_file(art_path) if not multi else null
	var w := int(H * float(art.get_width()) / art.get_height()) if art else int(H * 0.95)
	var frame := db.frame(frame_id)
	var mounts: Array = []
	var fm: Array = frame.get("mounts", [])
	for i in range(fm.size()):
		mounts.append({"mount": fm[i], "weapons": [weapons[i]] if i < weapons.size() and weapons[i] != "" else []})
	var model := MechBuilder.build(frame, {"mounts": mounts}, db)
	model.scale = Vector3.ONE / model.size  # compare at unit height
	var panels: Array = []
	if art_path == "rom":
		# Range of motion: joints at their extremes, mostly side-on so each pivot can be seen
		# turning around its joint piece (no gaps opening, nothing stretching or detaching).
		var poses := [["rest", 90.0], ["stride_a", 90.0], ["stride_b", 90.0], ["arms_up", yaw], ["kneel", 90.0], ["kneel_aim", yaw + 30.0]]
		w = int(H * 0.7)
		for p: Array in poses:
			var mm := MechBuilder.build(frame, {"mounts": mounts}, db)
			mm.scale = Vector3.ONE / mm.size
			match String(p[0]):
				"stride_a", "stride_b":
					mm.walk_amount = 1.0
					mm.walk_phase = PI * (0.5 if p[0] == "stride_a" else 1.5)
					mm._apply_walk()
				"arms_up":
					for s: String in ["r", "l"]:
						mm.aim_arm(s, Vector3(0, mm.height * 1.4, -2.0))
				"kneel":
					mm.set_kneel(1.0)
				"kneel_aim":
					mm.set_kneel(0.6)
					mm.aim_arm("r", Vector3(0, mm.height * 0.8, -2.0))
			panels.append(await _render(mm, w, float(p[1]), pitch, null))

	elif multi:
		# No art: front, 3/4 and back views of the model.
		for y: float in [yaw, yaw + 40.0, yaw + 180.0]:
			var mm := MechBuilder.build(frame, {"mounts": mounts}, db)
			mm.scale = Vector3.ONE / mm.size
			panels.append(await _render(mm, w, y, pitch, null))
	else:
		panels = [art, await _render(model, w, yaw, pitch, null)]
	# Several guides separated by ';'. A trailing '@y' marks a Y-up mesh (TripoSG); others are
	# Z-up (TripoSR).
	for gp: String in guide.split(";", false):
		var g := _load_glb(gp.trim_suffix("@y"), gp.ends_with("@y"))
		if g:
			panels.append(await _render(g, w, yaw, pitch, model))
	var img := Image.create(w * panels.size() + 12 * (panels.size() - 1), H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.93, 0.93, 0.94))
	var x := 0
	for p: Image in panels:
		p.convert(Image.FORMAT_RGBA8)
		var q := p.duplicate() as Image
		q.resize(w, H, Image.INTERPOLATE_LANCZOS)
		img.blend_rect(q, Rect2i(0, 0, w, H), Vector2i(x, 0))
		x += w + 12
	img.save_png(out)
	print("saved ", out)
	quit()


func _load_glb(path: String, y_up: bool = false) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	var n := doc.generate_scene(st) as Node3D
	var holder := Node3D.new()
	holder.add_child(n)
	if not y_up:
		n.rotation_degrees.x = -90.0  # TripoSR meshes are Z-up
		n.rotation_degrees.y = 180.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = not y_up  # TripoSR has colors; TripoSG is plain grey
	mat.albedo_color = Color(0.72, 0.72, 0.74)
	for m in n.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	return holder


func _bounds(n: Node3D, body_only: bool = false) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.has_meta("no_height"):
			continue
		if body_only and _in_weapon(mi):
			continue
		var g := mi.global_transform * mi.get_aabb()
		box = g if first else box.merge(g)
		first = false
	return box


func _in_weapon(n: Node) -> bool:
	while n:
		if n.has_meta("style"):
			return true
		n = n.get_parent()
	return false


## Renders `n` standing at the origin, framed to its height. If `match` is given, `n` is
## scaled and moved so its bounds line up with that model's (for the blockout panel).
func _render(n: Node3D, w: int, yaw: float, pitch: float, match: Node3D) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	world.add_child(n)
	await process_frame
	var box := _bounds(n)
	if match:
		var mb := _bounds(match) if match.is_inside_tree() else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
		var k := 1.0 / maxf(box.size.y, 0.001)
		n.scale *= k
		await process_frame
		box = _bounds(n)
		n.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
		await process_frame
		box = _bounds(n)
	var body := _bounds(n, true) if not match else box
	# Fit the body's box as the camera sees it: its projected height spans [_top, _bottom] of
	# the frame (like the figure in the art), and it never spills off the sides.
	var dir := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)) * Vector3(0, 0, -1)
	var view := Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3.ZERO).inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(8):
		var c := view * body.get_endpoint(i)
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	var aspect := float(w) / H
	var size := maxf((hi.y - lo.y) / (_bottom - _top), (hi.x - lo.x) / aspect * 1.04)
	# Screen-space centre: horizontally centred, vertically placed per _top/_bottom.
	var mid := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5 + size * ((_bottom + _top) * 0.5 - 0.5))
	var center := view.affine_inverse() * Vector3(mid.x, mid.y, (view * body.get_center()).z)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	world.add_child(cam)
	# The model faces -Z, so the camera sits on the -Z side looking back at it.
	cam.position = center + dir * 10.0
	cam.look_at(center)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 160 + yaw, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 220 + yaw, 0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.97, 0.97, 0.97)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.78)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	return img
