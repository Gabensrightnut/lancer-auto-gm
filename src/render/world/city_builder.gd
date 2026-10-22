class_name CityBuilder
extends RefCounted
## Buildings for city and settlement styles (filled in below).

var t: TerrainRenderer


func _init(terrain: TerrainRenderer) -> void:
	t = terrain


## Marks the cells this builder draws (TerrainRenderer.structure_cells).
func claim() -> void:
	pass


func build(_root: Node3D) -> void:
	pass
