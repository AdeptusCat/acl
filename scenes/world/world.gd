extends Node2D

# --- SETUP ---

@onready var ground_layer : HexagonTileMapLayer = $GroundTileMapLayer
@onready var building_layer : HexagonTileMapLayer = $BuildingTileMapLayer
@onready var wall_layer : HexagonTileMapLayer = $WallTileMapLayer
@onready var terrain_layer : HexagonTileMapLayer = $TerrainTileMapLayer
@onready var result_screen := $ResultScreen
@onready var start_screen := $StartScreen
@onready var ui := $Ui
@onready var game_controller := $GameController



#@export var los_data: Resource





func _ready():
	LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	LOSHelper.terrain_layer = terrain_layer
	await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data("res://scenes/game/los/los_data.tres")
	LOSHelper.load_prebaked_los("res://scenes/game/los/los_data.tres")
	
	
	start_screen.game_started.connect(_on_game_started)
	game_controller.update_timer_label.connect(ui._on_update_timer_label)
	game_controller.show_winner.connect(result_screen._on_show_winner)
	game_controller.set_objective_text.connect(start_screen._on_set_objective_text)
	
	game_controller.setup_game()
	
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#14,2 10,2
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(1,1))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(3,4))

	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(11,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(8,2))
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(14,2))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(10,2))
	#LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,1))
	#LOSHelper.get_tile_local_pixel_coords(pos_a, building_layer)


func _on_game_started(team : int):
	game_controller.start_game(team)
