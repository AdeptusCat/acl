extends Node2D

# --- SETUP ---

@onready var ground_layer : HexagonTileMapLayer = $GroundTileMapLayer
@onready var building_layer : HexagonTileMapLayer = $BuildingTileMapLayer
@onready var wall_layer : HexagonTileMapLayer = $WallTileMapLayer
@onready var objective_tilemap := $ObjectiveTileMapLayer
@onready var result_screen := $ResultScreen
@onready var start_screen := $StartScreen
var timer_running := false
var objective_hex : Vector2i = Vector2.ZERO


@export var time_left_seconds: float = 120.0  

@onready var timer_label = $CanvasLayer/HBoxContainer/TimerLabel

func _ready():
	LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data("res://los_data.tres")
	#LOSHelper.load_prebaked_los("res://los_data.tres")
	var cells = objective_tilemap.get_used_cells()  # 0 = layer index
	if cells.size() > 0:
		objective_hex = cells[0]
	else:
		push_error("ObjectiveTileMapLayer has no tiles placed!")
	start_screen.set_objective_text("Hold hex at %s (red circle) with an unbroken unit!" % str(objective_hex))
	start_screen.game_started.connect(_on_game_started)
	start_screen.visible = true
	$UnitManager.set_input_enabled(false)
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	
	var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(1,1))
	var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(3,4))

	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)


func _on_game_started(team : int):
	timer_running = true
	$UnitManager.team = team
	$UnitManager.set_input_enabled(true)

func _process(delta):
	if timer_running:
		time_left_seconds -= delta
		if time_left_seconds <= 0:
			time_left_seconds = 0
			timer_running = false
			end_game_check()

		update_timer_label()

func update_timer_label():
	var minutes = int(time_left_seconds) / 60
	var seconds = int(time_left_seconds) % 60
	timer_label.text = "Time left: %02d:%02d" % [minutes, seconds]

func end_game_check():
	var occupying_units : Array
	for unit in $UnitManager.units:
		if unit.current_hex == objective_hex:
			occupying_units.append(unit)

	for unit in occupying_units:
		if not unit.broken:
			result_screen.show_winner(unit.team)
			return

	result_screen.show_winner(-1)
