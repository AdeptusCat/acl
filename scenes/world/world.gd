extends Node2D

const ALDERBROOK_CAMPAIGN: CampaignDefinition = preload("res://resources/campaigns/road_to_alderbrook.tres")

# --- SETUP ---
@onready var tile_map_layers: Node2D = $TileMapLayers

#@onready var ground_layer : HexagonTileMapLayer = $TileMapLayers/GroundTileMapLayer
#@onready var building_layer : HexagonTileMapLayer = $TileMapLayers/BuildingTileMapLayer
#@onready var wall_layer : HexagonTileMapLayer = $TileMapLayers/WallTileMapLayer
#@onready var terrain_layer : HexagonTileMapLayer = $TileMapLayers/TerrainTileMapLayer
@onready var fog_of_war_tile_map_layer: TileMapLayer = $TileMapLayers/FogOfWarTileMapLayer
@onready var selected_tile_map_layer: HexagonTileMapLayer = $TileMapLayers/SelectedTileMapLayer

@onready var result_screen: CanvasLayer = $ResultScreen
@onready var start_screen: CanvasLayer = $StartScreen
@onready var ui: CanvasLayer = $Ui
@onready var game_controller: Node2D = $GameController
@onready var target_area: Node2D = $TargetArea
@onready var input_manager: Node = $InputManager
@onready var maps: Node2D = $Maps
@onready var hex_inspection: HexInspectionOverlay = $HexInspection



signal try_again
signal fully_freed

var ground_layer: HexagonTileMapLayer
var terrain_layer : HexagonTileMapLayer 
var wall_layer : HexagonTileMapLayer
var building_layer : HexagonTileMapLayer
var mouse_hover_hex: Vector2i

#var map: Map
#var scenario: Scenario
var is_setup: bool = false


func _exit_tree() -> void:
	LOSHelper.unload_map()
	fully_freed.emit()


func _ready() -> void:
	Globals.reset()
	ALDERBROOK_CAMPAIGN.install(maps)
	maps.hide()
	var _maps: Array[Map] = []
	_maps.assign(maps.get_children())
	start_screen.setup_map_options(_maps)
	
	
	ui.show()
	
	
	
	#LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	#LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	#LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	#LOSHelper.terrain_layer = terrain_layer
	#Globals.astars[Globals.Team.AXIS] = copy_astar(LOSHelper.ground_layer.astar)
	#Globals.astars[Globals.Team.ALLIES] = copy_astar(LOSHelper.ground_layer.astar)
	#await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data($Maps/Map2)
	#LOSHelper.load_prebaked_los($Maps/Map2)
	
	#LOSHelper.bake_and_save_los_data("res://resources/los/los_data.tres")
	#LOSHelper.load_prebaked_los("res://resources/los/los_data.tres")
	
	game_controller.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	start_screen.game_started.connect(_on_game_started)
	game_controller.update_timer_label.connect(ui._on_update_timer_label)
	game_controller.game_started_through_moving_unit.connect(ui._on_game_started_through_moving_unit)
	game_controller.show_unit_details_in_ui.connect(ui._on_show_unit_details)
	game_controller.hide_unit_details_in_ui.connect(ui._on_hide_unit_details)
	game_controller.order_feedback.connect(ui.show_order_feedback)
	ui.selection_wheel_alt.cancelled.connect(_on_wheel_cancelled)
	ui.squad_roster.unit_selected.connect(game_controller.select_and_center_unit)
	game_controller.show_winner.connect(result_screen._on_show_winner)
	game_controller.hex_selected.connect(_on_hex_selected)
	ui.tile_details.inspection_closed.connect(clear_hex_inspection)
	hex_inspection.edge_hovered.connect(ui.show_hex_edge_hint)
	hex_inspection.edge_left.connect(ui.hide_hex_edge_hint)
	ui.squad_roster.unit_selected.connect(_on_roster_selection)
	ui.get_node("Control/Debug").bind_ai_controls(game_controller)
	
	
	
	#var origin_pos = ground_layer.map_to_local(Vector2i(3, 4))
	#var target_pos = ground_layer.map_to_local(Vector2i(7, 4))
	#var res = LOSHelper.check_los(origin_pos, target_pos, 0, 0, 0, 0)
	#pass
	
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
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(4,4))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(6,3))
	#var res = LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	#print(res)
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,1))
	#LOSHelper.get_tile_local_pixel_coords(pos_a, building_layer)
	
	#var match_data: MatchSaveData = load_match_data("debug1")
	#game_controller.spawn_units_from_match_save(match_data)
	

var selected_hex: Vector2i
var has_inspected_hex: bool = false

func _on_hex_selected(map_hex: Vector2i, _event_pos: Vector2) -> void:
	if not is_setup or ground_layer == null:
		return
	if ground_layer.get_cell_source_id(map_hex) == -1 or (has_inspected_hex and map_hex == selected_hex):
		clear_hex_inspection()
		return
	clear_hex_inspection()
	selected_hex = map_hex
	has_inspected_hex = true
	selected_tile_map_layer.set_cell(selected_hex, 0, Vector2i(0, 0))  # Set selected tile with ID 1
	calc_unit_data_for_ui(ground_layer.map_to_local(map_hex))


func clear_hex_inspection() -> void:
	if has_inspected_hex:
		selected_tile_map_layer.erase_cell(selected_hex)
	has_inspected_hex = false
	hex_inspection.clear_inspection()
	ui.hide_tile_data()


func _on_roster_selection(_unit: Unit) -> void:
	clear_hex_inspection()
	ui.hide_target_hex_cover_distance()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and has_inspected_hex:
		clear_hex_inspection()
		get_viewport().set_input_as_handled()


func copy_astar(source: AStar2D) -> AStar2D:
	var copy: AStar2D = AStar2D.new()

	# Step 1: Copy all points
	for id: int in source.get_point_ids():
		var pos: Vector2 = source.get_point_position(id)
		var weight: float = source.get_point_weight_scale(id)
		var disabled: bool = source.is_point_disabled(id)
		copy.add_point(id, pos, weight)
		copy.set_point_disabled(id, disabled)

	# Step 2: Copy connections
	for id: int in source.get_point_ids():
		for neighbor: int in source.get_point_connections(id):
			# Avoid duplicate connections (only add if id < neighbor)
			if id < neighbor:
				copy.connect_points(id, neighbor)

	return copy


func _on_mouse_event_position_changed(_event_pos: Vector2) -> void:
	return
	#event_pos = get_local_mouse_position()
	#var map_hex = ground_layer.local_to_map(event_pos)
	#if not map_hex == mouse_hover_hex:
		#mouse_hover_hex = map_hex
		#calc_unit_data_for_ui(event_pos)


func calc_unit_data_for_ui(event_pos: Vector2) -> void:
	var map_hex: Vector2i = ground_layer.local_to_map(event_pos)
	var result: Dictionary = get_hex_inspection_data(map_hex)
	ui.show_tile_data(result)
	hex_inspection.inspect(ground_layer, result)


func get_hex_inspection_data(map_hex: Vector2i) -> Dictionary:
	var point: Vector2 = ground_layer.map_to_local(map_hex)
	var cover: int = LOSHelper.is_sample_point_in_building(point)
	var result: Dictionary = {
		"hex": map_hex,
		"tile_name": LOSHelper.get_tile_name(point),
		"cover_in_hex": cover,
		"blocking": cover > 0,
		"hindrance": LOSHelper.is_hex_hindrance(map_hex),
	}
	var terrain: TileData = terrain_layer.get_cell_tile_data(map_hex)
	if terrain != null and terrain.has_custom_data("blocking") and bool(terrain.get_custom_data("blocking")):
		result["blocking"] = true
	var keys: Array[String] = ["cover_n", "cover_ne", "cover_se", "cover_s", "cover_sw", "cover_nw"]
	for index: int in range(HexInspectionOverlay.DIRECTIONS.size()):
		result[keys[index]] = get_wall_cover(point, HexInspectionOverlay.DIRECTIONS[index])
	return result


func get_tilemaplayer_texture_transform(map_hex: Vector2i, tilemaplayer: TileMapLayer) -> Transform2D:
	var tile_data: TileData = tilemaplayer.get_cell_tile_data(map_hex)
	if not tile_data:
		return Transform2D.IDENTITY

	var flip_h: bool = tile_data.get_flip_h()
	var flip_v: bool = tile_data.get_flip_v()
	var transpose: bool = tile_data.get_transpose()

	var basis_x: Vector2 = Vector2(1, 0)
	var basis_y: Vector2 = Vector2(0, 1)

	# Apply transpose: swap axes
	if transpose:
		var temp: Vector2 = basis_x
		basis_x = basis_y
		basis_y = temp
		# Also swap meaning of flip_h and flip_v
		var temp_flip: bool = flip_h
		flip_h = flip_v
		flip_v = temp_flip

	# Apply flips in the correct (possibly transposed) axes
	if flip_h:
		basis_x *= -1
	if flip_v:
		basis_y *= -1

	return Transform2D(basis_x, basis_y, Vector2.ZERO)

func get_tilemaplayer_texture(map_hex: Vector2i, tilemaplayer: TileMapLayer) -> Texture2D:
	var tile_id: int = tilemaplayer.get_cell_source_id(map_hex)
	var texture: Texture
	if not tile_id == -1:
		var tileset: TileSet = tilemaplayer.tile_set
		texture = tileset.get_source(tile_id).texture
	return texture


func get_wall_cover(event_pos: Vector2, direction_index: int) -> int:
	var hex_cube: Vector3i = building_layer.local_to_cube(event_pos)
	var top_cube: Vector3i = ground_layer.cube_direction(direction_index)
	var hex_cube_top: Vector3i = hex_cube + top_cube
	var top_pos: Vector2 = ground_layer.cube_to_local(hex_cube_top)
	var res: Dictionary = LOSHelper.check_los(event_pos, top_pos, 0, 0, 0, 0)
	return res.wall_cover


func _on_game_started(map: Map, scenario: Scenario, team : int, game_mode: Globals.GameMode) -> void:
	if is_setup:
		return
	is_setup = true
	Globals.begin_battle()
	
	ground_layer = map.get_ground_layer()
	terrain_layer = map.get_terrain_layer()
	wall_layer = map.get_wall_layer()
	building_layer = map.get_building_layer()
	fog_of_war_tile_map_layer.material = null
	if map.campaign_name == TerrainPalette.CAMPAIGN:
		fog_of_war_tile_map_layer.material = TerrainPalette.material_for_family("grid_fog", get_viewport().use_hdr_2d)
	
	
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	game_controller.ground_layer = map.get_ground_layer()
	ui.ground_layer = map.get_ground_layer()
	
	Globals.astars[Globals.Team.AXIS] = copy_astar(LOSHelper.ground_layer.astar)
	Globals.astars[Globals.Team.ALLIES] = copy_astar(LOSHelper.ground_layer.astar)
	await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data(map)
	LOSHelper.load_prebaked_los(map)
	
	ui.setup()
	
	
	var layers: Array[Node] = map.get_tilemap_layers()
	for layer: Node in layers:
		layer.reparent(tile_map_layers)
	
	var units: Array[Node] = scenario.get_units()
	for unit: Node in units:
		unit.setup()
		unit.add_to_group("units")
		unit.reparent(game_controller.unit_container)
		unit.game_start()
	
	fog_of_war_tile_map_layer.move_to_front()
	selected_tile_map_layer.move_to_front()
	
	var axis_objectives_layer: HexagonTileMapLayer = scenario.get_objectives_layer(Globals.Team.AXIS)
	axis_objectives_layer.reparent(tile_map_layers)
	
	var allied_objectives_layer: HexagonTileMapLayer = scenario.get_objectives_layer(Globals.Team.ALLIES)
	allied_objectives_layer.reparent(tile_map_layers)
	
	Globals.victory_conditions = scenario.get_victory_conditions()
	
	game_controller.setup()
	game_controller.setup_game()
	
	Globals.game_mode = game_mode
	target_area.hide()
	Globals.objectives = scenario.get_objectives()
	#game_controller.set_objective_layer(team, objectives[0])
	#map.remove_scenarios()
	
	game_controller.axis_objective_tilemap = scenario.get_objectives_layer(Globals.Team.AXIS)
	game_controller.allies_objective_tilemap = scenario.get_objectives_layer(Globals.Team.ALLIES)
	
	game_controller.start_game(team, start_screen.time)
	ui.show_mission_objectives(scenario.victory_conditions, team, game_controller.time_left_seconds)
	ui.show_squad_roster(team)
	input_manager.set_battle_input_enabled(true)
	
	game_controller.move_camera(scenario.start_hex[scenario.player_team])
	
	
	
	#var match_data: MatchSaveData = load_match_data("debug")
	#game_controller.spawn_units_from_match_save(match_data)


func _process(delta: float) -> void:
	if Debug.hide_fog_of_war:
		fog_of_war_tile_map_layer.hide()
	else:
		fog_of_war_tile_map_layer.show()


func _on_ui_try_again() -> void:
	try_again.emit()


func _on_start_screen_hover_start_button(team: int) -> void:
	target_area.show_target(team)


func _on_result_screen_try_again() -> void:
	try_again.emit()

var selected_map_hex: Vector2i
var _command_unit: Unit

func _on_input_manager_right_button_pressed() -> void:
	if not is_setup or game_controller.end_game_handled or not is_instance_valid(game_controller.selected_unit):
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var mouse_screen_pos: Vector2 = input_manager.pointer_position
	var event_pos: Vector2 = game_controller.get_global_transform_with_canvas().affine_inverse() * mouse_screen_pos
	selected_map_hex = ground_layer.local_to_map(event_pos)
	if ground_layer.get_cell_source_id(selected_map_hex) == -1:
		return
	_command_unit = game_controller.selected_unit
	ui.hide_target_hex_cover_distance()
	ui.hide_order_feedback()
	LOSHelper.clear_los()
	ui.selection_wheel_alt.open(mouse_screen_pos, _wheel_restriction, _command_unit.stress_system)


func _wheel_restriction(option: WheelOption.Option) -> String:
	if not is_instance_valid(_command_unit) or _command_unit != game_controller.selected_unit:
		return "Squad selection changed. Open the wheel again."
	return MatchInteractionHandler.command_restriction(game_controller, selected_map_hex, option)


func _on_input_manager_right_button_released() -> void:
	if not ui.selection_wheel_alt.is_open():
		return
	ui.selection_wheel_alt.select_at(input_manager.pointer_position)
	var option: WheelOption.Option = ui.selection_wheel_alt.close()
	if option == WheelOption.Option.NONE:
		ui.show_order_cancelled()
	elif not is_instance_valid(_command_unit) or _command_unit != game_controller.selected_unit:
		game_controller.order_feedback.emit(false, MatchInteractionHandler.command_name(option), "Squad selection changed. Open the wheel again.")
	else:
		game_controller.order_via_option_wheel(selected_map_hex, option)
	_command_unit = null


func _on_wheel_cancelled() -> void:
	_command_unit = null
	ui.show_order_cancelled()


func _on_game_controller_show_winner(winner_team: int, outcome_level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
	ui.selection_wheel_alt.cancel()
	input_manager.set_battle_input_enabled(false)
	clear_hex_inspection()
	ui.hide_target_hex_cover_distance()
	var match_save: MatchSaveData = MatchSaveData.new()
	
	match_save.match_id = Globals.scenario_chosen.get_save_id()
	match_save.scenario_id = Globals.scenario_chosen.scenario_name
	if not Globals.scenario_chosen.scenario_id.is_empty():
		match_save.scenario_id = Globals.scenario_chosen.scenario_id
	match_save.battle_id = Globals.battle_id
	match_save.casualty_records.assign(Globals.battle_casualties)
	match_save.exit_records.assign(Globals.battle_exits)
	
	match_save.player_team = Globals.team_player
	match_save.winner_team = winner_team
	match_save.outcome_level = outcome_level
	match_save.timeout = timeout
	
	for unit: Unit in Globals.get_units():
		if unit.team == Globals.team_player:
			var unit_save_data: UnitSaveData = unit.create_save_data()
			match_save.player_units.append(unit_save_data)
	for unit: Unit in Globals.get_exited_units():
		var unit_save_data: UnitSaveData = unit.create_save_data()
		match_save.exited_units.append(unit_save_data)
		if unit.team == Globals.team_player:
			match_save.player_units.append(unit_save_data)
	Globals.save_match_data(match_save)
