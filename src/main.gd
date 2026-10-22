extends Node3D
## Placeholder scene: draws a sample terraced map so the foundation can be checked visually.
## The renderer work replaces this.

func _ready() -> void:
	var map := BattleMap.flat(GridLayout.Shape.HEX, 14, 10)
	for i in range(4):
		for j in range(4 - i):
			map.set_column(Vector2i(6 + j - i, 3 + i), 4 - i - j)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.58, 0.62)
	for cell in map.cells():
		var h := map.ground_height(cell)
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 6
		mesh.top_radius = GridLayout.SPACE / sqrt(3.0) * 0.96
		mesh.bottom_radius = mesh.top_radius
		mesh.height = (h + 0.2) * GridLayout.LEVEL_HEIGHT
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = mat
		inst.rotation.y = PI / 6.0
		inst.position = map.grid.to_world(cell) + Vector3(0, mesh.height / 2.0 - 0.2, 0)
		add_child(inst)
	var cam := Camera3D.new()
	cam.position = Vector3(5, 11, 16)
	add_child(cam)
	cam.look_at(Vector3(5, 0, 4.5))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
