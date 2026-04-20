extends Node2D
class_name Map

@onready var tile_map_layers: Node2D = $TileMapLayers
@onready var scenarios: Node2D = $Scenarios

@export var map_name: String = "map"


func get_tilemap_layers() -> Array[Node]:
	return tile_map_layers.get_children()


func get_ground_layer():
	return tile_map_layers.get_node("./GroundTileMapLayer")


func get_terrain_layer():
	return tile_map_layers.get_node("./TerrainTileMapLayer")


func get_wall_layer():
	return tile_map_layers.get_node("./WallTileMapLayer")


func get_building_layer():
	return tile_map_layers.get_node("./BuildingTileMapLayer")


func get_scenario(nr: int) -> Scenario:
	if scenarios.get_child_count() > nr:
		return scenarios.get_children()[nr]
	else:
		return null

func get_objectives_layer_from_scenario(nr: int):
	if scenarios.get_child_count() > nr:
		return scenarios.get_children()[nr].get_objectives_layer()
	else:
		return null
	

func get_scenarios() -> Array[Scenario]:
	var _scenarios: Array[Scenario] = []
	_scenarios.assign(scenarios.get_children())
	return _scenarios


func remove_scenarios():
	scenarios.queue_free()
