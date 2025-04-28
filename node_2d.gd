extends Node2D

# --- SETUP ---

@onready var ground_layer = $GroundTileMapLayer
@onready var building_layer = $BuildingTileMapLayer
@onready var wall_layer = $WallTileMapLayer

func _ready():
	LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	await get_tree().process_frame
	LOSHelper.prebake_los()
