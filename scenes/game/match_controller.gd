extends Node2D

@onready var unit_container: Node2D = $UnitContainer
@onready var los_renderer: Node2D = $LOSRenderer
@onready var camera: Camera2D = $Camera2D
@onready var close_combat_locations: Node2D = $CloseCombatLocations
@onready var close_combat_instances: Node2D = $CloseCombatInstances
@onready var win_condition_timer: Timer = $WinConditionTimer
@onready var influence_map_debug_draw: InfluenceMapDebugDraw = $InfluenceMapDebugDraw
@onready var influence_map_controller: InfluenceMapController = $InfluenceMapController
@onready var defense_director: DefenseDirector = $DefenseDirector
@onready var platoon_ai: PlatoonAI = $PlatoonAi


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
var timer_running: bool = false

var selected_unit: Unit = null


signal update_timer_label(time_left_seconds: float)
signal show_winner(winner_team: int, outcome_level: VictoryCondition.OutcomeLevel, timeout: bool)
signal set_objective_text(hex: String)
signal mouse_event_position_changed(event_pos: Vector2)
signal show_unit_details_in_ui(unit: Unit)
signal hide_unit_details_in_ui
signal game_started_through_moving_unit
signal hex_selected(map_hex: Vector2i, event_pos: Vector2)
signal start_match

var end_game_handled: bool = false

var point_array: Array[Vector2]
var threat_weights: Dictionary = {}

func draw_points(_point_array: Array[Vector2]) -> void:
	point_array = _point_array
	queue_redraw()
func _draw() -> void:
	#for point in point_array:
		##draw_line(point, point, Color(1, 0, 0), 2.0)
		#draw_circle(point, 5.0, Color.RED)
	if threat_weights.is_empty():
		return
		
	var weights: Array = threat_weights.values()
	var min_weight: float = weights.min()
	var max_weight: float = weights.max()

	for hex: Vector2i in threat_weights:
		var norm: float = _normalize_weight(threat_weights[hex], min_weight, max_weight)
		var color: Color = Color(1, 1 - norm, 0)  # Red to Green
		var pos: Vector2 = ground_layer.map_to_local(hex) #+ Vector2(32, 32)
		draw_circle(pos, 4, color)
		
func _normalize_weight(w: float, min_w: float, max_w: float) -> float:
	if max_w == min_w:
		return 0.0
	return clamp((w - min_w) / (max_w - min_w), 0.0, 1.0)
	
func _on_draw_threat(_threat_weights: Dictionary[int, Dictionary]) -> void:
	# return #debug
	if Debug.draw_thread_map:
		if Debug.draw_thread_map_enemy:
			threat_weights = _threat_weights[Globals.team_enemy]
		else:
			threat_weights = _threat_weights[Globals.team_player]#
		queue_redraw()
	

func setup() -> void:
	#MovementSystem.draw_threat.connect(_on_draw_threat)
	#camera.camera_moved.connect(_on_camera_moved)
	#combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)
	#for child in $"../UnitManager".get_children():
		#child.unit_arrived_at_hex.connect(move_sys._on_arrived)
	for unit: Unit in get_tree().get_nodes_in_group("units"):
		if unit is Unit:
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
			unit.squad_fire.shooting.connect(_on_unit_shooting)
			Globals.register_unit(unit.team, unit.company, unit.platoon, unit.squad, unit)
			
	for unit: Unit in Globals.get_units():
		if unit is Unit:
			# assign platoon headquarter to squad 
			if not unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS and not unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
				unit.command_squad = Globals.get_unit(unit.team, unit.company, unit.platoon, 0)
			# assign company headquarter to platoon headquarter 
			if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
				unit.command_squad = Globals.get_unit(unit.team, unit.company, 0, 0)
	
	LOS.draw_los_to_enemy.connect(los_renderer._on_draw_los_to_enemy)
	
	#update_timer_label.emit(time_left_seconds)
	
	var map_size : Vector2 = Vector2(ground_layer.tile_set.tile_size) * Vector2(LOSHelper.grid_size.x, LOSHelper.grid_size.y)
	camera.set_camera_limit(map_size) 
	
	$CommandConnectivityRenderer.setup()
	#for x in range(LOSHelper.grid_size.x):
		#for y in range(LOSHelper.grid_size.y):
			#fog_of_war_layer.set_cell(Vector2i(x, y), 0)
	
	#fog_of_war_layer.set_cell(Vector2i(1, 1), 0)
	#fog_of_war_layer.set_cell(tile_map_layer, new_tile_map_cell_position, tile_map_cell_source_id, tile_map_cell_atlas_coords, tile_map_cell_alternative)
	
	influence_map_controller.create_maps(1.0)
	influence_map_debug_draw.tile_map_layer = LOSHelper.ground_layer
	influence_map_debug_draw.influence_controller = influence_map_controller
	influence_map_debug_draw.set_team(Globals.Team.ALLIES)
	influence_map_debug_draw.set_debug_view(InfluenceMapDebugDraw.DebugView.FIRE_POWER)
	
	influence_map_debug_draw.setup()

func spawn_formation() -> void:
	if Globals.game_mode == Globals.GameMode.ATTACK:
		return
	#var team: Globals.Team
	#var location: Vector2i
	#var roll: int = randi_range(0, 4)
	#
	#match Globals.team_player:
		#Globals.Team.AXIS:
			#team = Globals.Team.ALLIES
			#if roll == 0:
				#location = Vector2i(21, 20)
			#elif roll == 1:
				#location = Vector2i(6, 16)
			#elif roll == 2:
				#location = Vector2i(12, 10)
			#elif roll == 3:
				#location = Vector2i(31, 1)
			#else:
				#location = Vector2i(16, 7)
		#Globals.Team.ALLIES:
			#team = Globals.Team.AXIS
			#if roll == 0:
				#location = Vector2i(27,7)
			#elif roll == 1:
				#location = Vector2i(22,12)
			#elif roll == 2:
				#location = Vector2i(9,17)
			#elif roll == 3:
				#location = Vector2i(11,0)
			#else:
				#location = Vector2i(19,12)
#
	#var formation_ai_controller: FormationAIController = formation_ai_controller_scene.instantiate()
	#formation_ai_controller.active = true
	#formation_ai_controller.mission_mode = GoapTypes.FormationMissionMode.ATTACK
	#formation_ai_controller.team = team
	#var formation_id: int
	#match Globals.team_player:
		#Globals.Team.AXIS:
			#formation_id = $AlliesFormationAIControllers.get_child_count() + 1
			#formation_ai_controller.formation_id = formation_id
			#$AlliesFormationAIControllers.add_child(formation_ai_controller)
		#Globals.Team.ALLIES:
			#formation_id = $AxisFormationAIControllers.get_child_count() + 1
			#formation_ai_controller.formation_id = formation_id
			#$AxisFormationAIControllers.add_child(formation_ai_controller)
	#
	#spawn_unit(team, location, Globals.SquadType.Rifle, formation_id)
	#spawn_unit(team, location, Globals.SquadType.MG, formation_id)
	#spawn_unit(team, location, Globals.SquadType.PLATOON_HEADQUARTERS, formation_id)
	
	


func spawn_unit(team: Globals.Team, location: Vector2i, squad_type: Globals.SquadType, formation_id: int) -> void:
	MatchUnitSpawner.spawn_unit(self, team, location, squad_type, formation_id)


func draw_fog() -> void:
	MatchVisibilityCoordinator.draw_fog(self)


func show_visible_units() -> void:
	MatchVisibilityCoordinator.show_visible_units(self)


func update_visible_hexes() -> void:
	MatchVisibilityCoordinator.update_visible_hexes(self)


func _on_unit_entered_hex(unit_entering_hex: Unit, hex_entered: Vector2i) -> void:
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
						if unit.is_good_order():
							unit.surrender()
	
	set_close_combat_hexes_and_units()
	
	
	#var _units: Array
	#for _unit in Globals.units:
		#if _unit.current_hex == map_hex: 
			#_units.append(_unit)
	
	#get_parent().ui.show_unit_data(map_hex, _units)
	#for x in range(LOSHelper.grid_size.x):
		#for y in range(LOSHelper.grid_size.y):
			#fog_of_war_layer.set_cell(Vector2(x, y), -1)
	
	#
	#LOSHelper.grid_size.y
	#var visible_hexes: Array
	#for u in units:
		#if u.team == current_team:
			#var visible_hexes_from_unit = LOSHelper.los_lookup.get(unit.current_hex, [])
			


func set_close_combat_hexes_and_units() -> void:
	CloseCombatCoordinator.set_close_combat_hexes_and_units(self)


func setup_game() -> void:
	
	
	for unit: Unit in Globals.get_units():
		unit.update_terrain_defense_bonus()
	
	#for unit in unit_container2.get_children():
		#unit.reparent(unit_container)
	#remove_child(unit_container3)
	
	#for unit in unit_container3.get_children():
		#unit.reparent(unit_container)
	#remove_child(unit_container2)
	
	set_objective_text.emit("")
	for unit: Node in unit_container.get_children():
		unit.visible = false
	
	for unit: Unit in Globals.get_units():
		LOS._on_unit_entered_hex(unit, unit.current_hex)

func set_objective_layer(team: Globals.Team, tilemap: TileMapLayer) -> void:
	MatchVictoryCoordinator.set_objective_layer(self, team, tilemap)


func set_objective_cells(player_team: Globals.Team) -> void:
	MatchVictoryCoordinator.set_objective_cells(self, player_team)


func order_via_option_wheel(map_hex: Vector2i, option: WheelOption.Option) -> void:
	MatchInteractionHandler.order_via_option_wheel(self, map_hex, option)


var previous_selected_hex: Vector2i = Vector2i(-1, -1)
var selected_hex_index: int = 0


func _on_mouse_button_left_pressed(event_pos: Vector2) -> void:
	MatchInteractionHandler.on_mouse_button_left_pressed(self, event_pos)


var origin_hex: Variant
var target_hex: Variant
var targetCover: int
var distance: int
var firepower: float
func _on_mouse_event_position_changed(_event_pos: Vector2) -> void:
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


func handle_mouse_event_position_changed(event_pos: Vector2) -> void:
	MatchInteractionHandler.handle_mouse_event_position_changed(self, event_pos)


func hex_glow(pos: Vector2) -> void:
	MatchInteractionHandler.hex_glow(self, pos)


func _on_key_space_pressed(_event_pos: Vector2) -> void:
	pass


func _select_unit(unit: Unit) -> void:
	MatchInteractionHandler.select_unit(self, unit)


func _deselect_unit(unit: Unit) -> void:
	MatchInteractionHandler.deselect_unit(self, unit)


func _on_unit_surrendered(_unit: Unit) -> void:
	pass


func _on_unit_died(unit: Unit) -> void:
	var enemy_team: Globals.Team
	if unit.team == Globals.Team.AXIS:
		enemy_team = Globals.Team.ALLIES
	if unit.team == Globals.Team.ALLIES:
		enemy_team = Globals.Team.AXIS
	Globals.units_destroyed.units_collection[enemy_team].units.append(unit)
	Globals.unit_visible_enemies.erase(unit)
	Globals.unit_enemies_in_los.erase(unit)
	
	update_visible_hexes()
	show_visible_units()
	draw_fog()
	#unit.queue_free()


func erase_freed_objects_key_from_dict(dict: Dictionary) -> void:
	var keys: Array = dict.keys()
	
	var i: int = 0
	while i < keys.size():
		var k: Variant = keys[i]

		if k == null:
			dict.erase(k)
		else:
			if k is Object:
				if not is_instance_valid(k):
					dict.erase(k)
		i += 1


func start_game(team: Globals.Team, time: float) -> void:
	
	time_left_seconds = time * 60.0 # * 60.0
	Globals.team_player = team
	if team == Globals.Team.AXIS:
		Globals.team_enemy = Globals.Team.ALLIES
	else:
		Globals.team_enemy = Globals.Team.AXIS
	
	
	
	set_objective_cells(team)
	#timer_running = true
	
	start_match.emit()
	
	var i_team_0: int = 0
	var i_team_1: int = 0
	for unit: Unit in Globals.get_units():
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
	win_condition_timer.start()
	set_victory_conditions()
	
	var axis_ai_active: bool = false
	var allies_ai_active: bool = false
	if team == Globals.Team.ALLIES:
		axis_ai_active = true
	else:
		allies_ai_active = true
	
	
	#defense_director.manual_threat_axes = create_test_axes()
	defense_director.assign_order_to_platoon()
	$DefenseDirector2.assign_order_to_platoon()
	$PlatoonAi
	#var ai_mission_mode: GoapTypes.FormationMissionMode
	#ai_mission_mode = GoapTypes.FormationMissionMode.ATTACK
	#match Globals.game_mode:
		#Globals.GameMode.DEFEND:
			#ai_mission_mode = GoapTypes.FormationMissionMode.ATTACK
		#Globals.GameMode.ATTACK:
			#ai_mission_mode = GoapTypes.FormationMissionMode.DEFEND
		
	#for formation_ai_controller in axis_formation_ai_controllers.get_children():
		#formation_ai_controller._refresh_squad_list()
		#var controller: FormationAIController = formation_ai_controller
		#if controller.active:
			#controller.active = axis_ai_active
			#controller.mission_mode = ai_mission_mode
	#for formation_ai_controller in allies_formation_ai_controllers.get_children():
		#formation_ai_controller._refresh_squad_list()
		#var controller: FormationAIController = formation_ai_controller
		#if controller.active:
			#controller.active = allies_ai_active
			#controller.mission_mode = ai_mission_mode


func create_test_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = []

	var north_axis: ThreatAxis = ThreatAxis.new()
	north_axis.axis_name = "North Road"
	north_axis.axis_type = ThreatAxis.AxisType.SCRIPTED
	north_axis.source_hex = Vector2i(10, 2)
	north_axis.target_hex = influence_map_controller.objective_hex
	north_axis.estimated_enemy_count = 8
	north_axis.estimated_firepower = 3.0
	north_axis.confidence = 1.0
	north_axis.proximity_to_objective = 0.7
	north_axis.attack_lane_quality = 0.8
	north_axis.flank_danger = 0.2
	north_axis.time_pressure = 0.6
	north_axis.recompute_score()
	axes.append(north_axis)

	var east_axis: ThreatAxis = ThreatAxis.new()
	east_axis.axis_name = "East Woods"
	east_axis.axis_type = ThreatAxis.AxisType.SCRIPTED
	east_axis.source_hex = Vector2i(18, 8)
	north_axis.target_hex = influence_map_controller.objective_hex
	east_axis.estimated_enemy_count = 5
	east_axis.estimated_firepower = 2.0
	east_axis.confidence = 0.8
	east_axis.proximity_to_objective = 0.5
	east_axis.attack_lane_quality = 0.6
	east_axis.flank_danger = 0.9
	east_axis.time_pressure = 0.4
	east_axis.recompute_score()
	axes.append(east_axis)

	return axes


func index_to_char(i: int) -> String:
	var char_code: int = ord("A") + i
	return String.chr(char_code)


func _on_started_moving() -> void:
	if not timer_running:
		game_started_through_moving_unit.emit()
		Globals.game_started = true
	timer_running = true

var last_unit_hex: Vector2i
var last_mouse_position: Vector2
var time_left_seconds_test: int = 2
func _process(delta: float) -> void:
	if timer_running:
		var elapsed: float = minf(delta, maxf(time_left_seconds, 0.0))
		for team: Globals.Team in Globals.victory_conditions:
			for condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
				condition.advance_time(elapsed)
		time_left_seconds -= delta
		if time_left_seconds <= 0:
			time_left_seconds = 0
			timer_running = false
			_on_win_condition_timer_timeout()
		update_timer_label.emit(time_left_seconds)
	
	var mouse_or_unit_position_changed: bool = false
	var pos: Vector2 = get_local_mouse_position()
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
	for unit: Unit in units_to_kill:
		Debug.units_to_kill.erase(unit)
		unit.die()
	
	var units_soldier_to_kill: Array[Unit] = Debug.units_soldier_to_kill.duplicate()
	for unit: Unit in units_soldier_to_kill:
		Debug.units_soldier_to_kill.erase(unit)
		unit._on_unit_ui_debug_kill_soldier()
	
	var units_to_surrender: Array[Unit] = Debug.units_to_surrender.duplicate()
	for unit: Unit in units_to_surrender:
		Debug.units_to_surrender.erase(unit)
		unit.surrender()


func update_los_time(delta: float) -> void:
	MatchVisibilityCoordinator.update_los_time(self, delta)


func move_camera(hex: Vector2i) -> void:
	camera.position	= LOSHelper.ground_layer.map_to_local(hex)


func _on_zoom_in() -> void:
	camera.zoom_in()


func _on_zoom_out() -> void:
	camera.zoom_out()


func _on_spawn_timer_timeout() -> void:
	spawn_formation()


func _on_unit_visibility_checker_timer_timeout() -> void:
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(self)


func _compute_detect_prob_per_tick(observer: Unit, enemy: Unit, delta: float) -> float:
	return MatchVisibilityCoordinator.compute_detect_prob_per_tick(self, observer, enemy, delta)


func _get_concealment(current_hex: Variant, enemy: Node) -> int:
	return MatchVisibilityCoordinator.get_concealment(self, current_hex, enemy)


func _on_close_combat_resolve_timer_timeout() -> void:
	return
	var units_to_die: Array[Unit]
	set_close_combat_hexes_and_units()
	for unit: Unit in Globals.units_in_close_combat:
		if not is_instance_valid(unit):
			continue
		#for s in unit.squad_fire.soldiers:
			#s
		var r: float = randf()
		if r < 0.1:
			units_to_die.append(unit)
	for unit: Unit in units_to_die:
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
	for i: int in range(group.size()):
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
	for i: int in range(actors.size()):
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

	for i: int in range(targets.size()):
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


func set_victory_conditions() -> void:
	MatchVictoryCoordinator.set_victory_conditions(self)


func _on_win_condition_timer_timeout() -> void:
	MatchVictoryCoordinator.on_win_condition_timer_timeout(self)


func end_game_check() -> void:
	if end_game_handled:
		return


func _on_unit_shooting(shooter: Unit) -> void:
	MatchVisibilityCoordinator.on_unit_shooting(self, shooter)


func spawn_units_from_match_save(match_save: MatchSaveData) -> void:
	MatchUnitSpawner.spawn_units_from_match_save(self, match_save)


func spawn_unit_from_save(team: Globals.Team, location: Vector2i, squad_loadout: SquadLoadoutSpec, formation_id: int) -> void:
	MatchUnitSpawner.spawn_unit_from_save(self, team, location, squad_loadout, formation_id)
