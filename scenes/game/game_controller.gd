extends Node2D

@onready var unit_container = $UnitContainer
@onready var los_renderer   = $LOSRenderer
@onready var camera 		= $Camera2D
@onready var axis_formation_ai_controllers := $AxisFormationAIControllers
@onready var allies_formation_ai_controllers := $AlliesFormationAIControllers
@onready var close_combat_locations := $CloseCombatLocations
@onready var close_combat_instances := $CloseCombatInstances


@export var allies_objective_tilemap : TileMapLayer
@export var axis_objective_tilemap : TileMapLayer
@export var ground_layer : HexagonTileMapLayer
@export var fog_of_war_layer : HexagonTileMapLayer
@export var glow_maker_scene: PackedScene
@export var unit_scene: PackedScene
@export var formation_ai_controller_scene: PackedScene
@export var close_combat_instance_scene: PackedScene

@export var close_combat_sign_scene: PackedScene

@export var time_left_seconds: float = 120.0  
var timer_running := false

var selected_unit: Unit = null


signal update_timer_label(time_left_seconds: float)
signal show_winner(team: int)
signal set_objective_text(hex: String)
signal mouse_event_position_changed(event_pos)
signal show_unit_details_in_ui(unit: Unit)
signal hide_unit_details_in_ui
signal game_started_through_moving_unit
signal hex_selected(map_hex: Vector2i, event_pos: Vector2)
signal start_match

var end_game_handled: bool = false

var point_array: Array[Vector2]
var threat_weights = {}

func draw_points(_point_array):
	point_array = _point_array
	queue_redraw()
func _draw():
	#for point in point_array:
		##draw_line(point, point, Color(1, 0, 0), 2.0)
		#draw_circle(point, 5.0, Color.RED)
	if threat_weights.is_empty():
		return
		
	var weights = threat_weights.values()
	var min_weight = weights.min()
	var max_weight = weights.max()

	for hex in threat_weights:
		var norm = _normalize_weight(threat_weights[hex], min_weight, max_weight)
		var color = Color(1, 1 - norm, 0)  # Red to Green
		var pos = ground_layer.map_to_local(hex) #+ Vector2(32, 32)
		draw_circle(pos, 4, color)
		
func _normalize_weight(w, min_w, max_w):
	if max_w == min_w:
		return 0.0
	return clamp((w - min_w) / (max_w - min_w), 0.0, 1.0)
	
func _on_draw_threat(_threat_weights: Dictionary[int, Dictionary]):
	# return #debug
	if Debug.draw_thread_map:
		if Debug.draw_thread_map_enemy:
			threat_weights = _threat_weights[Globals.team_enemy]
		else:
			threat_weights = _threat_weights[Globals.team_player]#
		queue_redraw()
	

func _ready():
	MovementSystem.draw_threat.connect(_on_draw_threat)
	#camera.camera_moved.connect(_on_camera_moved)
	#combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)
	#for child in $"../UnitManager".get_children():
		#child.unit_arrived_at_hex.connect(move_sys._on_arrived)
	Globals.units.clear()
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Unit:
			Globals.units.append(unit)
			unit.unit_died.connect(_on_unit_died)
			unit.unit_entered_hex.connect(LOS._on_unit_entered_hex)
			unit.unit_entered_hex.connect(_on_unit_entered_hex)
			unit.unit_arrived_at_hex.connect(MovementSystem._on_arrived)
			unit.current_hex = ground_layer.local_to_map(unit.global_position)
			unit.current_cube = ground_layer.map_to_cube(unit.current_hex)
			unit.deselect_unit.connect(_deselect_unit)
			unit.started_moving.connect(_on_started_moving)
			unit.unit_surrendered.connect(_on_unit_surrendered)
			unit.squad_fire.draw_los_to_target_unit.connect(los_renderer._on_draw_los_to_target_unit)
			unit.movement.draw_movement_path.connect(los_renderer._on_draw_draw_movement_path)
			unit.draw_command_link_strength.connect(los_renderer._on_draw_command_link_strength)
			unit.draw_leader_presence_strength.connect(los_renderer._on_draw_leader_presence_strength)
			Globals.register_unit(unit.team, unit.company, unit.platoon, unit.squad, unit)
			
	for unit in Globals.units:
		if unit is Unit:
			# assign platoon headquarter to squad 
			if not unit.squadType == Unit.SquadType.COMPANY_HEADQUARTERS and not unit.squadType == Unit.SquadType.PLATOON_HEADQUARTERS:
				unit.command_squad = Globals.get_unit(unit.team, unit.company, unit.platoon, 0)
			# assign company headquarter to platoon headquarter 
			if unit.squadType == Unit.SquadType.PLATOON_HEADQUARTERS:
				unit.command_squad = Globals.get_unit(unit.team, unit.company, 0, 0)
	
	LOS.draw_los_to_enemy.connect(los_renderer._on_draw_los_to_enemy)
	
	update_timer_label.emit(time_left_seconds)
	
	var map_size : Vector2 = Vector2(ground_layer.tile_set.tile_size) * Vector2(LOSHelper.GRID_SIZE_X, LOSHelper.GRID_SIZE_Y)
	camera.set_camera_limit(map_size) 
	
	#for x in range(LOSHelper.GRID_SIZE_X):
		#for y in range(LOSHelper.GRID_SIZE_Y):
			#fog_of_war_layer.set_cell(Vector2i(x, y), 0)
	
	#fog_of_war_layer.set_cell(Vector2i(1, 1), 0)
	#fog_of_war_layer.set_cell(tile_map_layer, new_tile_map_cell_position, tile_map_cell_source_id, tile_map_cell_atlas_coords, tile_map_cell_alternative)

func spawn_formation():
	if Globals.game_mode == Globals.GameMode.ATTACK:
		return
	var team: Globals.Team
	var location: Vector2i
	var roll: int = randi_range(0, 4)
	
	match Globals.team_player:
		Globals.Team.AXIS:
			team = Globals.Team.ALLIES
			if roll == 0:
				location = Vector2i(21, 20)
			elif roll == 1:
				location = Vector2i(6, 16)
			elif roll == 2:
				location = Vector2i(12, 10)
			elif roll == 3:
				location = Vector2i(31, 1)
			else:
				location = Vector2i(16, 7)
		Globals.Team.ALLIES:
			team = Globals.Team.AXIS
			if roll == 0:
				location = Vector2i(27,7)
			elif roll == 1:
				location = Vector2i(22,12)
			elif roll == 2:
				location = Vector2i(9,17)
			elif roll == 3:
				location = Vector2i(11,0)
			else:
				location = Vector2i(19,12)

	var formation_ai_controller: FormationAIController = formation_ai_controller_scene.instantiate()
	formation_ai_controller.active = true
	formation_ai_controller.mission_mode = GoapTypes.FormationMissionMode.ATTACK
	formation_ai_controller.team = team
	var formation_id: int
	match Globals.team_player:
		Globals.Team.AXIS:
			formation_id = $AlliesFormationAIControllers.get_child_count() + 1
			formation_ai_controller.formation_id = formation_id
			$AlliesFormationAIControllers.add_child(formation_ai_controller)
		Globals.Team.ALLIES:
			formation_id = $AxisFormationAIControllers.get_child_count() + 1
			formation_ai_controller.formation_id = formation_id
			$AxisFormationAIControllers.add_child(formation_ai_controller)
	
	spawn_unit(team, location, Unit.SquadType.Rifle, formation_id)
	spawn_unit(team, location, Unit.SquadType.MG, formation_id)
	spawn_unit(team, location, Unit.SquadType.PLATOON_HEADQUARTERS, formation_id)
	
	


func spawn_unit(team: Globals.Team, location: Vector2i, squad_type: Unit.SquadType, formation_id: int):
	var unit: Unit = unit_scene.instantiate()
	unit.ground_map = ground_layer
	unit.team = team
	match squad_type:
		Unit.SquadType.Rifle:
			unit.make_rifle_squad = true
		Unit.SquadType.MG:
			unit.make_light_mg_team = true
		Unit.SquadType.PLATOON_HEADQUARTERS:
			unit.make_platoon_headquarters_squad = true
	
	unit.formation_id = formation_id 
	#$UnitContainer.add_child(unit)
	unit.position = ground_layer.map_to_local(location)
	
	var map_coords = ground_layer.local_to_map(ground_layer.map_to_local(location))
	unit.position = ground_layer.map_to_local(map_coords)
	unit.current_hex = map_coords
	unit.current_cube = ground_layer.map_to_cube(map_coords)
	
	unit.hide()
	$UnitContainer.add_child(unit)
	
	unit.set_team(team)
	
	Globals.units.append(unit)
	unit.unit_died.connect(_on_unit_died)
	unit.unit_entered_hex.connect(LOS._on_unit_entered_hex)
	unit.unit_entered_hex.connect(_on_unit_entered_hex)
	unit.unit_arrived_at_hex.connect(MovementSystem._on_arrived)
	unit.current_hex = ground_layer.local_to_map(unit.global_position)
	unit.current_cube = ground_layer.map_to_cube(unit.current_hex)
	unit.deselect_unit.connect(_deselect_unit)
	unit.started_moving.connect(_on_started_moving)
	unit.unit_surrendered.connect(_on_unit_surrendered)
	unit.squad_fire.draw_los_to_target_unit.connect(los_renderer._on_draw_los_to_target_unit)
	unit.movement.draw_movement_path.connect(los_renderer._on_draw_draw_movement_path)
	unit.draw_command_link_strength.connect(los_renderer._on_draw_command_link_strength)
	unit.draw_leader_presence_strength.connect(los_renderer._on_draw_leader_presence_strength)
	Globals.register_unit(unit.team, unit.company, unit.platoon, unit.squad, unit)
	unit.update_terrain_defense_bonus()
			
	# assign platoon headquarter to squad 
	if not unit.squadType == Unit.SquadType.COMPANY_HEADQUARTERS and not unit.squadType == Unit.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, unit.platoon, 0)
	# assign company headquarter to platoon headquarter 
	if unit.squadType == Unit.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, 0, 0)

func draw_fog():
	var used_cells := fog_of_war_layer.get_used_cells()
	for cell in used_cells:
		if LOSHelper.visible_hexes[Globals.team_player].has(cell):
			fog_of_war_layer.set_cell(cell, -1, Vector2i(0, 0))  # Clear fog
		else:
			fog_of_war_layer.set_cell(cell, 0, Vector2i(0, 0))  # Set fog tile with ID 1
	for x in LOSHelper.GRID_SIZE_X:
		for y in LOSHelper.GRID_SIZE_Y:
			if not LOSHelper.visible_hexes[Globals.team_player].has(Vector2i(x, y)):
				fog_of_war_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0)) 


func show_visible_units():
	var units_seen: Array = []
	#for u in Globals.units:
		#if not is_instance_valid(u):
			#continue
		#if not u.team == Globals.team_player:
			#u.visible = false
	for u in Globals.units:
		if not is_instance_valid(u):
			continue
		if u.surrendered:
			continue
		if u.team == Globals.team_player:
			var units_in_los: Array = Globals.unit_visible_enemies.get(u, [])
			for unit_in_los in units_in_los:
				if not units_seen.has(unit_in_los):
					units_seen.append(unit_in_los)
	
	for u in Globals.units:
		if not is_instance_valid(u):
				continue
		if not u.team == Globals.team_player:
			if units_seen.has(u):
				u.visible = true
			else:
				u.visible = false
			
			#if LOSHelper.visible_hexes[Globals.team_player].has(u.current_hex):
				#u.visible = true
			#else:
				#u.visible = false 


func update_visible_hexes():
	for array in LOSHelper.visible_hexes.values():
		array.clear()
	for u in Globals.units:
		if not is_instance_valid(u):
			continue
		if u.surrendered:
			continue
		var unit_visible = LOSHelper.los_lookup.get(u.current_hex, [])
		for hex in unit_visible:
			if not LOSHelper.visible_hexes[u.team].has(hex):
				LOSHelper.visible_hexes[u.team].append(hex)
		if not LOSHelper.visible_hexes[u.team].has(u.current_hex):
			LOSHelper.visible_hexes[u.team].append(u.current_hex)



func _on_unit_entered_hex(unit_entering_hex: Unit, hex_entered: Vector2i):
	update_visible_hexes()
	show_visible_units()
	draw_fog()
	
	unit_entering_hex.terrain_defense_bonus = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(unit_entering_hex.current_hex))
	
	var units_in_hex: Array = LOSHelper.find_units_at(hex_entered)
	var min_one_good_order_enemy_unit: bool = false
	var enemy_present: bool = false
	for unit: Unit in units_in_hex:
		if not unit.team == unit_entering_hex.team:
			enemy_present = true
			if unit.is_good_order():
				min_one_good_order_enemy_unit = true
	if min_one_good_order_enemy_unit:
		if unit_entering_hex.broken:
			unit_entering_hex.surrender()
	else:
		if enemy_present:
			if unit_entering_hex.broken and not unit_entering_hex.surrendered:
				unit_entering_hex.action_controller._start_rout()
			else:
				for unit: Unit in units_in_hex:
					if not unit.team == unit_entering_hex.team:
						unit.surrender()
	
	set_close_combat_hexes_and_units()
	
	
	#var _units: Array
	#for _unit in Globals.units:
		#if _unit.current_hex == map_hex: 
			#_units.append(_unit)
	
	#get_parent().ui.show_unit_data(map_hex, _units)
	#for x in range(LOSHelper.GRID_SIZE_X):
		#for y in range(LOSHelper.GRID_SIZE_Y):
			#fog_of_war_layer.set_cell(Vector2(x, y), -1)
	
	#
	#LOSHelper.GRID_SIZE_Y
	#var visible_hexes: Array
	#for u in units:
		#if u.team == current_team:
			#var visible_hexes_from_unit = LOSHelper.los_lookup.get(unit.current_hex, [])
			


func set_close_combat_hexes_and_units():
	#Globals.units_in_close_combat.clear()
	#Globals.close_combat_locations.clear()
	
	#for child in close_combat_locations.get_children():
		#child.queue_free()
	
	for unit: Unit in Globals.units:
		if not unit.is_good_order():
			continue
		var mask: int = 0
		var both_teams_present: bool = false
		var units_in_hex: Array[Unit] = LOSHelper.find_units_at(unit.current_hex)
		for _unit in units_in_hex:
			if not _unit.is_good_order():
				continue
			match _unit.team:
				Globals.Team.AXIS:
					mask |= 1
				Globals.Team.ALLIES:
					mask |= 2
			if mask == 3:
				both_teams_present = true
		if both_teams_present:
			var close_combat_instance: CloseCombatInstance
			for close_combat_instance_present in close_combat_instances.get_children():
				if close_combat_instance_present.hex == unit.current_hex:
					close_combat_instance = close_combat_instance_present
					break
			if not close_combat_instance:
				close_combat_instance = close_combat_instance_scene.instantiate()
				close_combat_instance.hex = unit.current_hex
				close_combat_instance.terrain_defense_value = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(unit.current_hex))
				
			for _unit in units_in_hex:
				if not close_combat_instance.units_by_team[_unit.team].has(_unit):
					close_combat_instance.add_unit(_unit)
			
			for _unit in units_in_hex:
				_unit.in_close_combat = true
			#var close_combat_sign: Sprite2D = close_combat_sign_scene.instantiate()
			#close_combat_locations.add_child(close_combat_sign)
			#if not Globals.close_combat_locations.has(unit.current_hex):
				#Globals.close_combat_locations.append(unit.current_hex)
			#if not Globals.units_in_close_combat.has(unit):
				#Globals.units_in_close_combat.append(unit)
			
			if close_combat_instance.get_parent() == null:
				close_combat_instance.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
				close_combat_instances.add_child(close_combat_instance)
		else:
			for _unit in units_in_hex:
				_unit.in_close_combat = false


#func set_close_combat_hexes_and_units():
	#Globals.units_in_close_combat.clear()
	#Globals.close_combat_locations.clear()
	#
	#for child in close_combat_locations.get_children():
		#child.queue_free()
	#
	#for unit: Unit in Globals.units:
		#if not unit.is_good_order():
			#continue
		#var mask: int = 0
		#var both_teams_present: bool = false
		#var units_in_hex: Array[Unit] = LOSHelper.find_units_at(unit.current_hex)
		#for _unit in units_in_hex:
			#if not _unit.is_good_order():
				#continue
			#match _unit.team:
				#Globals.Team.AXIS:
					#mask |= 1
				#Globals.Team.ALLIES:
					#mask |= 2
			#if mask == 3:
				#both_teams_present = true
		#if both_teams_present:
			#for _unit in units_in_hex:
				#_unit.in_close_combat = true
			#var close_combat_sign: Sprite2D = close_combat_sign_scene.instantiate()
			#close_combat_locations.add_child(close_combat_sign)
			#close_combat_sign.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
			#if not Globals.close_combat_locations.has(unit.current_hex):
				#Globals.close_combat_locations.append(unit.current_hex)
			#if not Globals.units_in_close_combat.has(unit):
				#Globals.units_in_close_combat.append(unit)
		#else:
			#for _unit in units_in_hex:
				#_unit.in_close_combat = false


func setup_game():
	for unit in Globals.units:
		unit.update_terrain_defense_bonus()
	
	set_objective_text.emit("")
	for unit in unit_container.get_children():
		unit.visible = false


func set_objective_cells(player_team: Globals.Team): 
	Globals.objective_hexes.clear()
	var player_objective_tilemap: TileMapLayer
	var ai_objective_tilemap: TileMapLayer
	var ai_team: Globals.Team
	if player_team == Globals.Team.AXIS:
		ai_team = Globals.Team.ALLIES
	else:
		ai_team = Globals.Team.AXIS
		
	if player_team == Globals.Team.AXIS:
		match Globals.game_mode:
			Globals.GameMode.DEFEND:
				player_objective_tilemap = allies_objective_tilemap
				ai_objective_tilemap = allies_objective_tilemap
			Globals.GameMode.ATTACK:
				player_objective_tilemap = axis_objective_tilemap
				ai_objective_tilemap = axis_objective_tilemap
	if player_team == Globals.Team.ALLIES:
		match Globals.game_mode:
			Globals.GameMode.DEFEND:
				player_objective_tilemap = axis_objective_tilemap
				ai_objective_tilemap = axis_objective_tilemap
			Globals.GameMode.ATTACK:
				player_objective_tilemap = allies_objective_tilemap
				ai_objective_tilemap = allies_objective_tilemap
	if player_team == Globals.Team.AXIS:
		match Globals.game_mode:
			Globals.GameMode.DEFEND:
				axis_objective_tilemap.visible = false
				allies_objective_tilemap.visible = true
			Globals.GameMode.ATTACK:
				axis_objective_tilemap.visible = true
				allies_objective_tilemap.visible = false
	elif player_team == Globals.Team.ALLIES:
		match Globals.game_mode:
			Globals.GameMode.DEFEND:
				axis_objective_tilemap.visible = true
				allies_objective_tilemap.visible = false
			Globals.GameMode.ATTACK:
				axis_objective_tilemap.visible = false
				allies_objective_tilemap.visible = true
	
	var cells = player_objective_tilemap.get_used_cells() 
	if cells.size() > 0:
		for cell in cells:
			if not Globals.objective_hexes.has(player_team):
				Globals.objective_hexes[player_team] = []
			Globals.objective_hexes[player_team].append(cell)
	else:
		push_error("ObjectiveTileMapLayer has no tiles placed!")
	
	cells = ai_objective_tilemap.get_used_cells() 
	if cells.size() > 0:
		for cell in cells:
			if not Globals.objective_hexes.has(ai_team):
				Globals.objective_hexes[ai_team] = []
			Globals.objective_hexes[ai_team].append(cell)
	else:
		push_error("ObjectiveTileMapLayer has no tiles placed!")


func order_via_option_wheel(map_hex: Vector2i, option: WheelOption.Option):
	if not selected_unit:
		return
	
	if selected_unit.broken or selected_unit.surrendered:
		selected_unit.ui.show_failure()
		return
	
	match option:
		WheelOption.Option.NONE:
			pass
		WheelOption.Option.MOVE_NORMAL:
			selected_unit.order(Globals.UnitCmd.MOVE, map_hex)
		WheelOption.Option.FIRE_AT:
			selected_unit.setAttackState(Unit.AttackState.MANUAL_GROUND)
			selected_unit.order(Globals.UnitCmd.FIRE_AT_HEX, map_hex)
		WheelOption.Option.ASSAULT:
			pass
		WheelOption.Option.STOP:
			selected_unit.order(Globals.UnitCmd.STOP, map_hex)
	
	var local_pos: Vector2 = ground_layer.map_to_local(map_hex)
	hex_glow(local_pos)

#func _on_mouse_button_right_pressed(event_pos: Vector2):
	#event_pos = get_local_mouse_position()
	#var map_hex = ground_layer.local_to_map(event_pos)
	#
	#if selected_unit:
		#if selected_unit.broken:
			#selected_unit.ui.show_failure()
			#return
		#var local_pos: Vector2
		#if selected_unit.squadType == Unit.SquadType.MORTAR:
			#selected_unit.order(Globals.UnitCmd.ATTACK_GROUND, map_hex)
		#else:
			#var units: Array[Node2D] = _find_units_at(map_hex)
			#for unit in units:
				#if not unit.team == Globals.team_player or Debug.enemy_selectable:
					#var _path: Array[Vector3i] = []
					#selected_unit.order(Globals.UnitCmd.ATTACK_UNIT, unit)
					#local_pos = ground_layer.map_to_local(map_hex)
					#hex_glow(local_pos)
					#return
			#selected_unit.order(Globals.UnitCmd.MOVE, map_hex)
		#local_pos = ground_layer.map_to_local(map_hex)
		#hex_glow(local_pos)
	


var previous_selected_hex: Vector2i = Vector2i(-1, -1)
var selected_hex_index: int = 0


func _on_mouse_button_left_pressed(event_pos: Vector2):
	event_pos = get_local_mouse_position()
	var map_hex = ground_layer.local_to_map(event_pos)
	hex_selected.emit(map_hex, event_pos)
	if previous_selected_hex == map_hex:
		selected_hex_index += 1
	else:
		previous_selected_hex = map_hex
		selected_hex_index = 0
	var units: Array[Unit] = LOSHelper.find_units_at(map_hex)
	if units.is_empty():
		if not selected_unit == null:
			_deselect_unit(selected_unit)
			hide_unit_details_in_ui.emit()
		return
	if selected_hex_index >= units.size():
		selected_hex_index = 0
	var unit = units[selected_hex_index]
	if unit: # and not unit.broken  and not unit.surrendered
		if not unit.team == Globals.team_player and not Debug.enemy_selectable:
			return
		if unit == selected_unit:
			_deselect_unit(unit)
			hide_unit_details_in_ui.emit()
		else:
			_select_unit(unit)
			show_unit_details_in_ui.emit(unit)
			LOSHelper.clear_los()


var origin_hex 
var target_hex
var targetCover
var distance
var firepower
func _on_mouse_event_position_changed(_event_pos: Vector2):
	return
	#mouse_event_position_changed.emit(event_pos)
	#if selected_unit:
		#var unit_pos = selected_unit.position
		#var local_event_pos = get_local_mouse_position()
		#LOSHelper.draw_los(unit_pos, local_event_pos)
		#
		#var screen_pos = get_viewport().get_mouse_position()
		#if (target_hex == LOSHelper.ground_layer.local_to_map(local_event_pos) and origin_hex == selected_unit.current_hex):
			#get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
		#else:
			#origin_hex = selected_unit.current_hex
			#target_hex = LOSHelper.ground_layer.local_to_map(local_event_pos)
			##distance = int(origin_hex.distance_to(target_hex))
			#var origin_cube: Vector3i = selected_unit.current_cube
			#var target_cube: Vector3i = LOSHelper.ground_layer.local_to_cube(local_event_pos)
			#distance = LOSHelper.ground_layer.cube_distance(origin_cube, target_cube)
			## safely grab the inner dict for this shooter-hex
			#var cover_map = LOSHelper.los_lookup.get(origin_hex, null)
			#if cover_map and cover_map.has(target_hex):
				#var data        = cover_map[target_hex]
				#targetCover 	= data["target_cover"]
			#else:
				#targetCover = 0  # no LOS or no cover entry
				#get_parent().ui.hide_target_hex_cover_distance()
				#target_hex = null
				#origin_hex = null
				#return
			## now display it
			#firepower = selected_unit.firepower
			#if distance > selected_unit.range:
				#if distance <= selected_unit.range * 2:
					#firepower = firepower / 2
				#else:
					#firepower = 0
			#
			#get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
			##selected_unit.set_cover(targetCover)
	#else:
		#get_parent().ui.hide_target_hex_cover_distance()


func handle_mouse_event_position_changed(event_pos: Vector2):
	mouse_event_position_changed.emit(event_pos)
	if selected_unit:
		var unit_pos = selected_unit.position
		var local_event_pos = get_local_mouse_position()
		LOSHelper.draw_los(unit_pos, local_event_pos)
		
		var screen_pos = get_viewport().get_mouse_position()
		if (target_hex == LOSHelper.ground_layer.local_to_map(local_event_pos) and origin_hex == selected_unit.current_hex):
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
		else:
			origin_hex = selected_unit.current_hex
			target_hex = LOSHelper.ground_layer.local_to_map(local_event_pos)
			var origin_cube: Vector3i = selected_unit.current_cube
			var target_cube: Vector3i = LOSHelper.ground_layer.local_to_cube(local_event_pos)
			distance = LOSHelper.ground_layer.cube_distance(origin_cube, target_cube)
			# safely grab the inner dict for this shooter-hex
			var cover_map = LOSHelper.los_lookup.get(origin_hex, null)
			if cover_map and cover_map.has(target_hex):
				var data        = cover_map[target_hex]
				targetCover 	= data["target_cover"]
			else:
				targetCover = 0  # no LOS or no cover entry
				get_parent().ui.hide_target_hex_cover_distance()
				target_hex = null
				origin_hex = null
				return
			# now display it
			firepower = selected_unit.firepower
			if distance > selected_unit.weapon_range:
				if distance <= selected_unit.weapon_range * 2:
					firepower = firepower / 2
				else:
					firepower = 0
			
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
			#selected_unit.set_cover(targetCover)
	else:
		get_parent().ui.hide_target_hex_cover_distance()


#var last_mouse_position: Vector2
#func _on_camera_moved():
	#var pos = get_local_mouse_position()
	#if abs(pos.x - last_mouse_position.x) > 1 or abs(pos.y - last_mouse_position.y) > 1:
		#handle_mouse_event_position_changed(pos)
		#last_mouse_position = pos


func hex_glow(pos: Vector2):
	var glow = glow_maker_scene.instantiate()
	glow.position = pos
	add_child(glow)


func _on_key_space_pressed(_event_pos: Vector2):
	pass


func _select_unit(unit):
	if selected_unit:
		selected_unit.deselect()
	selected_unit = unit
	unit.select()


func _deselect_unit(unit):
	if selected_unit == unit:
		selected_unit.deselect()
		selected_unit = null
		LOSHelper.clear_los()


func _on_unit_surrendered(_unit):
	pass


func _on_unit_died(unit):
	Globals.units.erase(unit)
	Globals.unit_visible_enemies.erase(unit)
	Globals.unit_enemies_in_los.erase(unit)
	
	Globals.unit_enemy_los_time_s.erase(unit)
	# not working
	#erase_freed_objects_key_from_dict(Globals.unit_enemy_los_time_s)
	for _unit in Globals.unit_enemy_los_time_s:
		if is_instance_valid(_unit):
			Globals.unit_enemy_los_time_s[_unit].erase(unit)
	
	Globals.unit_enemy_spot_conf.erase(unit)
	# not working
	#erase_freed_objects_key_from_dict(Globals.unit_enemy_spot_conf)
	for _unit in Globals.unit_enemy_spot_conf:
		if is_instance_valid(_unit):
			Globals.unit_enemy_spot_conf[_unit].erase(unit)
	
	Globals.unit_enemy_last_seen_unix_s.erase(unit)
	# not working
	#erase_freed_objects_key_from_dict(Globals.unit_enemy_last_seen_unix_s)
	for _unit in Globals.unit_enemy_last_seen_unix_s:
		if is_instance_valid(_unit):
			Globals.unit_enemy_last_seen_unix_s[_unit].erase(unit)
	
	update_visible_hexes()
	show_visible_units()
	draw_fog()
	#unit.queue_free()


func erase_freed_objects_key_from_dict(dict: Dictionary):
	var keys: Array = dict.keys()
	
	var i: int = 0
	while i < keys.size():
		var k = keys[i]

		if k == null:
			dict.erase(k)
		else:
			if k is Object:
				if not is_instance_valid(k):
					dict.erase(k)
		i += 1


func start_game(team: Globals.Team, time: float):
	time_left_seconds = time * 60.0
	Globals.team_player = team
	if team == Globals.Team.AXIS:
		Globals.team_enemy = Globals.Team.ALLIES
	else:
		Globals.team_enemy = Globals.Team.AXIS
		
	set_objective_cells(team)
	#set_objective_cells(Globals.Team.ALLIES)
	#timer_running = true
	
	start_match.emit()
	
	var i_team_0: int = 0
	var i_team_1: int = 0
	for unit in unit_container.get_children():
		if unit.team == Globals.team_player:
			unit.visible = true
		if unit.team == Globals.team_player:
			unit.ui.set_unit_designation(index_to_char(i_team_0))
			i_team_0 += 1
		else:
			unit.ui.set_unit_designation(index_to_char(i_team_1))
			i_team_1 += 1
			
	update_visible_hexes()
	draw_fog()
	show_visible_units()
	
	var axis_ai_active: bool = false
	var allies_ai_active: bool = false
	if team == Globals.Team.ALLIES:
		axis_ai_active = true
	else:
		allies_ai_active = true
	
	var ai_mission_mode: GoapTypes.FormationMissionMode
	match Globals.game_mode:
		Globals.GameMode.DEFEND:
			ai_mission_mode = GoapTypes.FormationMissionMode.ATTACK
		Globals.GameMode.ATTACK:
			ai_mission_mode = GoapTypes.FormationMissionMode.DEFEND
		
	for formation_ai_controller in axis_formation_ai_controllers.get_children():
		var controller: FormationAIController = formation_ai_controller
		if controller.active:
			controller.active = axis_ai_active
			controller.mission_mode = ai_mission_mode
	for formation_ai_controller in allies_formation_ai_controllers.get_children():
		var controller: FormationAIController = formation_ai_controller
		if controller.active:
			controller.active = allies_ai_active
			controller.mission_mode = ai_mission_mode


func index_to_char(i: int) -> String:
	var char_code: int = ord("A") + i
	return String.chr(char_code)


func _on_started_moving():
	if not timer_running:
		game_started_through_moving_unit.emit()
		Globals.game_started = true
	timer_running = true

var last_unit_hex: Vector2i
var last_mouse_position: Vector2
var time_left_seconds_test = 2
func _process(delta):
	if timer_running:
		time_left_seconds -= delta
		if time_left_seconds <= 0:
			time_left_seconds = 0
			timer_running = false
			end_game_check()
		update_timer_label.emit(time_left_seconds)
	
	var mouse_or_unit_position_changed: bool = false
	var pos = get_local_mouse_position()
	if abs(pos.x - last_mouse_position.x) > 1 or abs(pos.y - last_mouse_position.y) > 1:
		mouse_or_unit_position_changed = true
		last_mouse_position = pos
	if selected_unit:
		if not selected_unit.current_hex == last_unit_hex:
			mouse_or_unit_position_changed = true
			last_unit_hex = selected_unit.current_hex
	if mouse_or_unit_position_changed:
		handle_mouse_event_position_changed(pos)
		
	if not Debug.draw_thread_map:
		if not threat_weights.is_empty():
			threat_weights.clear()
			queue_redraw()
	update_los_time(delta)
	
	var units_to_kill: Array[Unit] = Debug.units_to_kill.duplicate()
	for unit in units_to_kill:
		Debug.units_to_kill.erase(unit)
		unit.die()
	
	var units_soldier_to_kill: Array[Unit] = Debug.units_soldier_to_kill.duplicate()
	for unit in units_soldier_to_kill:
		Debug.units_soldier_to_kill.erase(unit)
		unit._on_unit_ui_debug_kill_soldier()
	
	var units_to_surrender: Array[Unit] = Debug.units_to_surrender.duplicate()
	for unit in units_to_surrender:
		Debug.units_to_surrender.erase(unit)
		unit.surrender()
	
	
func update_los_time(delta: float) -> void:
	var now_unix: float = Time.get_unix_time_from_system()

	for unit in Globals.units:
		if not is_instance_valid(unit):
			continue


		var time_map: Dictionary[Unit, float] = Globals.unit_enemy_los_time_s.get(unit, {} as Dictionary[Unit, float])
		var last_seen_map: Dictionary[Unit, float] = Globals.unit_enemy_last_seen_unix_s.get(unit, {} as Dictionary[Unit, float])

		var enemies_in_los: Array = Globals.unit_enemies_in_los.get(unit, [])

		var seen_this_tick: Dictionary[Unit, bool] = {}

		for enemy in enemies_in_los:
			if not is_instance_valid(enemy):
				continue

			seen_this_tick[enemy] = true

			var t: float = time_map.get(enemy, 0.0)
			t += delta
			time_map[enemy] = t

			last_seen_map[enemy] = now_unix

		# cleanup: remove entries for dead refs or enemies not seen for a while
		var units_tracked: Array[Unit] = time_map.keys()
		for unit_tracked in units_tracked:
			if not is_instance_valid(unit_tracked):
				continue
			if not seen_this_tick.has(unit_tracked):
				var last_seen: float = last_seen_map.get(unit_tracked, 0.0)
				
				# E 0:02:39:581   game_controller.gd:702 @ update_los_time(): Condition "!_p->typed_key.validate(key, "erase")" is true. Returning: false
  #<C++ Source>  core/variant/dictionary.cpp:254 @ erase()
  #<Stack Trace> game_controller.gd:702 @ update_los_time()
				#game_controller.gd:667 @ _process()
				
				#if now_unix - last_seen > 10.0:
				time_map.erase(unit_tracked)
				last_seen_map.erase(unit_tracked)

		Globals.unit_enemy_los_time_s[unit] = time_map
		Globals.unit_enemy_last_seen_unix_s[unit] = last_seen_map


func end_game_check():
	if end_game_handled:
		return
	end_game_handled = true
	var occupying_units : Array
	for unit in unit_container.get_children():
		if unit.current_hex == Globals.objective_hexes[unit.team][0]:
			occupying_units.append(unit)
	for unit in occupying_units:
		if not unit.broken:
			var winning_team: Globals.Team = Globals.Team.AXIS
			match Globals.game_mode:
				Globals.GameMode.DEFEND:
					if unit.team == Globals.Team.AXIS:
						winning_team = Globals.Team.AXIS
					if unit.team == Globals.Team.ALLIES:
						winning_team = Globals.Team.ALLIES
				Globals.GameMode.ATTACK:
					if unit.team == Globals.Team.ALLIES:
						winning_team = Globals.Team.ALLIES
					if unit.team == Globals.Team.AXIS:
						winning_team = Globals.Team.AXIS
			show_winner.emit(winning_team)
			return
	show_winner.emit(-1)


func _on_zoom_in():
	camera.zoom_in()


func _on_zoom_out():
	camera.zoom_out()


func _on_spawn_timer_timeout() -> void:
	spawn_formation()


func _on_unit_visiblity_checker_timer_timeout() -> void:
	var next_visible: Dictionary = {}
	
	for unit in Globals.units:
		if not is_instance_valid(unit):
			continue
		var units_visible: Array = []
		var units_visible_by_this_unit: Array = Globals.unit_visible_enemies.get(unit, [])
		var time_map: Dictionary[Unit, float] = Globals.unit_enemy_los_time_s.get(unit, {} as Dictionary[Unit, float])
		var time_map_keys_filtered: Array[Unit] = time_map.keys().filter(func(v): return v != null)
		var conf_map: Dictionary[Unit, float] = Globals.unit_enemy_spot_conf.get(unit, {} as Dictionary[Unit, float])
		for enemy_tracked in time_map_keys_filtered:
			if not is_instance_valid(enemy_tracked):
				continue
			if units_visible_by_this_unit.has(enemy_tracked):
				units_visible.append(enemy_tracked)
				continue
			var time: float = time_map[enemy_tracked]
			
			var p_tick: float = _compute_detect_prob_per_tick(unit, enemy_tracked, 1.0) # 1.0 is delta of one second
			var conf: float = conf_map.get(enemy_tracked, 0.0)
			var r: float = randf()
			if r < p_tick:
				conf += 0.35
			else:
				conf -= 0.10 * 1.0 # 1.0 is delta of one second
			conf = clamp(conf, 0.0, 1.0)
			conf_map[enemy_tracked] = conf
			
			if conf >= 0.55:
				units_visible.append(enemy_tracked)
		var units_at_current_hex: Array = LOSHelper.find_units_at(unit.current_hex)
		for unit_in_current_hex in units_at_current_hex:
			if not unit_in_current_hex.team == unit.team:
				if not units_visible.has(unit_in_current_hex):
					units_visible.append(unit_in_current_hex)
		
		Globals.unit_enemy_spot_conf[unit] = conf_map
		next_visible[unit] = units_visible
	Globals.unit_visible_enemies = next_visible
	show_visible_units()
	
	#var next_visible: Dictionary = {}
#
	#for unit in Globals.units:
		#if not is_instance_valid(unit):
			#continue
#
		#var enemies_in_los: Array = Globals.unit_enemies_in_los.get(unit, [])
		#var filtered: Array = []
#
		#for enemy in enemies_in_los:
			#if not is_instance_valid(enemy):
				#continue
			#filtered.append(enemy)
#
		#next_visible[unit] = filtered
#
	#Globals.unit_visible_enemies = next_visible
	#show_visible_units()

func _compute_detect_prob_per_tick(observer: Unit, enemy: Unit, delta: float) -> float:
	var dist: int = LOSHelper.ground_layer.cube_distance(observer.current_cube, enemy.current_cube)
	if dist < 1:
		dist = 1

	var is_moving: bool = enemy.moving

	var conceal: int = _get_concealment(observer.current_hex, enemy) # 0..N, higher = harder to see
	if conceal > 0:
		conceal = 1

	# score components (tune)
	var score: float = 0.0

	# movement: huge
	if is_moving:
		score += 3.0
	else:
		score += 0.5

	# distance penalty (log-ish)
	score -= 0.25 * float(dist)

	# concealment penalty
	if conceal == 1:
		score -= 0.8 * float(conceal)
	if conceal == 0:
		score += 1
	
	# shooting stimulus (0..1) -> add to score
	var fire_recent: float = enemy.squad_fire.fire_recent
	var fire_recent_mod: float = 10.0 * fire_recent
	score += fire_recent_mod
	# convert score -> hazard rate (lambda >= 0)
	# baseline ensures “sometimes” even if score small
	var lambda: float = 0.00 + 0.15 * max(score, 0.0)
	var p: float = 1.0 - exp(-lambda * delta)

	return clamp(p, 0.0, 0.95)

func _get_concealment(current_hex: Variant, enemy: Node) -> int:
	var cover_map: Variant = LOSHelper.los_lookup.get(current_hex, null)
	if cover_map == null:
		return 0
	if not cover_map.has(enemy.current_hex):
		return 0
	var data: Variant = cover_map[enemy.current_hex]
	if data is Dictionary:
		if data.has("target_conceal"):
			return int(data["target_conceal"])
		if data.has("target_cover"):
			# fallback if you have nothing else
			return int(data["target_cover"])
	return 0


func _on_close_combat_resolve_timer_timeout() -> void:
	return
	var units_to_die: Array[Unit]
	set_close_combat_hexes_and_units()
	for unit in Globals.units_in_close_combat:
		if not is_instance_valid(unit):
			continue
		#for s in unit.squad_fire.soldiers:
			#s
		var r: float = randf()
		if r < 0.1:
			units_to_die.append(unit)
	for unit in units_to_die:
		unit.die()
	
	

func update_close_combat(instance: CloseCombatInstance, dt: float) -> void:
	var ready_attackers: Array[Soldier] = []
	var ready_defenders: Array[Soldier] = []

	instance.elapsed += dt

	if not instance.opening_shock_done:
		#resolve_opening_shock(instance)
		instance.opening_shock_done = true

	collect_ready_fighters(instance.attackers, dt, ready_attackers)
	collect_ready_fighters(instance.defenders, dt, ready_defenders)

	resolve_ready_group(ready_attackers, instance.defenders)
	resolve_ready_group(ready_defenders, instance.attackers)

	#cleanup_dead(instance.attackers)
	#cleanup_dead(instance.defenders)
#
	#update_close_combat_morale(instance)
	#check_close_combat_end(instance)



func collect_ready_fighters(
	group: Array[Soldier],
	dt: float,
	ready: Array[Soldier]
) -> void:
	for i in range(group.size()):
		var fighter: Soldier = group[i]
		if not fighter.alive:
			continue
		if fighter.stunned_time > 0.0:
			fighter.stunned_time -= dt
			if fighter.stunned_time < 0.0:
				fighter.stunned_time = 0.0
			continue

		fighter.cooldown_remaining -= dt
		if fighter.cooldown_remaining <= 0.0:
			ready.append(fighter)


func resolve_ready_group(
	actors: Array[Soldier],
	targets: Array[Soldier]
) -> void:
	for i in range(actors.size()):
		var actor: Soldier = actors[i]
		var target: Soldier = select_target(actor, targets)
		if target == null:
			continue

		#resolve_single_attack(actor, target)
		actor.cooldown_remaining = actor.attack_interval


func select_target(
	actor: Soldier,
	targets: Array[Soldier]
) -> Soldier:
	var best_target: Soldier = null
	var best_score: float = -1000000.0

	for i in range(targets.size()):
		var target: Soldier = targets[i]
		if not target.alive:
			continue

		var score: float = 0.0
		#score -= CloseCombatInstance.compute_defense_power(target)

		if target.stunned_time > 0.0:
			score += 2.0

		if target.morale_attack_mult < 0.5:
			score += 1.5

		if score > best_score:
			best_score = score
			best_target = target

	return best_target
