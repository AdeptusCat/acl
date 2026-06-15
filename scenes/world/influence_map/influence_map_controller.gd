class_name InfluenceMapController
extends Node2D

signal influence_maps_updated()

const REBUILD_CELLS_PER_FRAME: int = 400
const LOS_SOURCES_PER_FRAME: int = 1

enum CompositeSource {
	SELF,
	ENEMY
}

enum TacticalTask {
	NONE,
	DEFEND_OBJECTIVE,
	ATTACK_OBJECTIVE
}

var maps_by_team: Dictionary[int, InfluenceMap] = {}

var allied_weights: PackedFloat32Array = PackedFloat32Array()
var axis_weights: PackedFloat32Array = PackedFloat32Array()

var center_of_mass: Dictionary[Globals.Team, Vector2i] = {
	Globals.Team.AXIS: Vector2i.ZERO,
	Globals.Team.ALLIES: Vector2i.ZERO,
}

var formations: Dictionary[Globals.Team, FormationIdentification] = {
	Globals.Team.AXIS: null,
	Globals.Team.ALLIES: null,
}

var rebuild_pending: bool = false
var objective_hex: Vector2i = Vector2i(11, 13)

var los_rebuild_active: bool = false
var los_rebuild_map: InfluenceMap = null
var los_rebuild_sources: Array[ProjectionSource] = []
var los_rebuild_modes: Array[bool] = []
var los_rebuild_cursor: int = 0

var update_counter: float = 0.0
var update_threshold: float = 1.0
var maps_initialized: bool = false


func _process(delta: float) -> void:
	_update_rebuild_timer(delta)
	_process_los_rebuild()
	_process_budgeted_rebuild()


func _update_rebuild_timer(delta: float) -> void:
	update_counter += delta

	if update_counter > update_threshold:
		update_counter = 0.0
		create_maps(update_threshold)


func _process_budgeted_rebuild() -> void:
	if not rebuild_pending:
		return

	var all_done: bool = true

	for team: int in maps_by_team.keys():
		var influence_map: InfluenceMap = maps_by_team[team]
		var done: bool = influence_map.rebuild_dirty_composite_budgeted(REBUILD_CELLS_PER_FRAME)

		if not done:
			all_done = false

	if not all_done:
		return

	rebuild_pending = false
	influence_maps_updated.emit()


func _run_post_rebuild_tactical_tasks() -> void:
	return


func create_axis_defense_config(
	defending_team: int,
	p_objective_hex: Vector2i
) -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()

	config.unit_team = defending_team
	config.enemy_team = Globals.get_enemy_team(defending_team)
	config.unit_group = ""
	config.enemy_group = ""
	config.task = TacticalTask.DEFEND_OBJECTIVE
	config.objective_hex = p_objective_hex

	config.projected_line_max_cells = 6
	config.anchor_skip_front = 1
	config.anchor_count = 4
	config.los_skip_front = 1
	config.los_count = 4
	config.move_improvement_ratio = 0.8

	return config


func _create_axis_defense_config() -> InfluenceProjectionConfig:
	return create_axis_defense_config(Globals.Team.AXIS, objective_hex)


func _create_los_config_for_team(team: int) -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()

	config.unit_team = team
	config.enemy_team = Globals.get_enemy_team(team)
	config.unit_group = ""
	config.enemy_group = ""
	config.task = TacticalTask.DEFEND_OBJECTIVE
	config.objective_hex = objective_hex

	config.projected_line_max_cells = 8
	config.anchor_skip_front = 1
	config.anchor_count = 1
	config.los_skip_front = 4
	config.los_count = 4
	config.move_improvement_ratio = 0.8

	return config


func get_sorted_threat_axes_for_team(
	defending_team: int,
	p_objective_hex: Vector2i
) -> Array[ThreatAxis]:
	var result: Array[ThreatAxis] = []
	var enemy_team: int = Globals.get_enemy_team(defending_team)

	if not formations.has(enemy_team):
		return result

	var formation: FormationIdentification = formations[enemy_team]
	if formation == null:
		return result

	if formation.front != null:
		var front_axis: ThreatAxis = _create_threat_axis_from_formation_group(
			formation.front,
			p_objective_hex,
			"front"
		)
		result.append(front_axis)

	var flank_index: int = 0
	for flank: FormationGroup in formation.flanks:
		if flank == null:
			continue

		var flank_axis: ThreatAxis = _create_threat_axis_from_formation_group(
			flank,
			p_objective_hex,
			"flank_%d" % flank_index
		)
		result.append(flank_axis)
		flank_index += 1

	result.sort_custom(_sort_threat_axis_by_score_descending)
	return result


func _create_threat_axis_from_formation_group(
	group: FormationGroup,
	p_objective_hex: Vector2i,
	axis_name: String
) -> ThreatAxis:
	var axis: ThreatAxis = ThreatAxis.new()

	axis.axis_name = axis_name
	axis.axis_type = ThreatAxis.AxisType.SCRIPTED
	axis.source_hex = group.seed_hex
	axis.target_hex = p_objective_hex
	axis.estimated_enemy_count = group.units.size()
	axis.estimated_firepower = group.units.size()
	axis.enemy_units = group.units
	axis.confidence = 1.0
	axis.proximity_to_objective = 0.7
	axis.attack_lane_quality = 0.8
	axis.flank_danger = 0.2
	axis.time_pressure = 0.6
	axis.recompute_score()

	return axis


func _sort_threat_axis_by_score_descending(axis_a: ThreatAxis, axis_b: ThreatAxis) -> bool:
	return axis_a.score > axis_b.score


func analyze_defense_positions_for_threat_axis(
	defending_team: int,
	p_objective_hex: Vector2i,
	axis: ThreatAxis,
	assigned_units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	var empty_result: Array[DefensePositionResult] = []

	if axis == null:
		return empty_result

	var config: InfluenceProjectionConfig = create_axis_defense_config(
		defending_team,
		p_objective_hex
	)
	config.threat_axis = axis

	return DefensePositionAnalyzer.analyze_best_positions_for_threat_axis(
		self,
		config,
		assigned_units,
		axis.enemy_units,
		reserved_hexes_by_unit
	)


func analyze_objective_defense_positions(
	defending_team: int,
	p_objective_hex: Vector2i,
	assigned_units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	var config: InfluenceProjectionConfig = create_axis_defense_config(
		defending_team,
		p_objective_hex
	)

	return DefensePositionAnalyzer.analyze_objective_defense_positions(
		self,
		config,
		assigned_units,
		reserved_hexes_by_unit
	)


func create_maps(_delta: float) -> void:

	if not is_instance_valid(LOSHelper.ground_layer):
		return

	if not maps_initialized:
		_initialize_maps()
		rebuild_static_terrain_layers()
		maps_initialized = true

	rebuild_dynamic_tactical_layers()


func _initialize_maps() -> void:
	var used_bounds: Rect2i = LOSHelper.ground_layer.get_used_rect()

	var allied_map: InfluenceMap = InfluenceMap.new()
	var axis_map: InfluenceMap = InfluenceMap.new()

	allied_map.configure(used_bounds)
	axis_map.configure(used_bounds)

	allied_weights = create_default_weights()
	axis_weights = create_default_weights()

	allied_map.configure_composite_weights(
		allied_weights,
		0.0,
		0.0,
		20.0
	)

	axis_map.configure_composite_weights(
		axis_weights,
		0.0,
		0.0,
		20.0
	)

	maps_by_team[Globals.Team.ALLIES] = allied_map
	maps_by_team[Globals.Team.AXIS] = axis_map


func create_default_weights() -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(InfluenceMap.Layer.COUNT)
	weights.fill(0.0)

	weights[InfluenceMap.Layer.TERRAIN_COVER] = 0.10
	weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.10
	weights[InfluenceMap.Layer.THREAT] = -0.01
	weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.10

	return weights


func _create_default_weights() -> PackedFloat32Array:
	return create_default_weights()


func get_map_for_team(team: int) -> InfluenceMap:
	if maps_by_team.has(team):
		return maps_by_team[team]

	return null


func get_movement_weight(team: int, cell: Vector2i) -> float:
	if not maps_by_team.has(team):
		return 1.0

	var influence_map: InfluenceMap = maps_by_team[team]
	return influence_map.get_composite_value(cell, 1.0)


func rebuild_static_terrain_layers() -> void:
	for team: int in maps_by_team.keys():
		var influence_map: InfluenceMap = maps_by_team[team]

		influence_map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.TERRAIN_MOVE_COST, 0.0)

		_write_static_terrain_for_map(influence_map)

	rebuild_pending = true


func rebuild_dynamic_tactical_layers() -> void:
	for team: int in maps_by_team.keys():
		var influence_map: InfluenceMap = maps_by_team[team]

		_clear_dynamic_layers_for_team(influence_map)
		_write_visibility_for_team(influence_map, team)
		_write_unit_influence_for_team(influence_map, team)

		var config: InfluenceProjectionConfig = _create_los_config_for_team(team)
		_begin_los_rebuild_for_team(influence_map, config)

	rebuild_pending = true


func _write_unit_influence_for_team(influence_map: InfluenceMap, team: int) -> void:
	var units: Array[Unit] = Globals.get_units()

	for unit: Unit in units:
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		var write_mode: int = InfluenceMap.WriteMode.ADD
		if team != unit.team:
			write_mode = InfluenceMap.WriteMode.SUBTRACT

		influence_map.stamp_radius(
			InfluenceMap.Layer.UNIT_INFLUENCE,
			unit.current_hex,
			InfluenceMap.UNIT_INFLUENCE_RADIUS,
			InfluenceMap.UNIT_INFLUENCE_VALUE,
			write_mode,
			InfluenceMap.FalloffMode.LINEAR
		)

	var max_value_index: int = influence_map.get_max_value_index(
		influence_map._layers[InfluenceMap.Layer.UNIT_INFLUENCE]
	)

	if max_value_index >= 0:
		center_of_mass[team] = influence_map.index_to_cell(max_value_index)

	var gradients: Array[UnitInfluenceGradient] = calculate_enemy_gradients_to_team_center(
		Globals.get_enemy_team(team),
		team,
		center_of_mass[team]
	)

	var best_gradient: UnitInfluenceGradient = influence_map.get_largest_gradient(gradients)
	var formation: FormationIdentification = identify_formations_from_gradients(
		influence_map,
		gradients,
		best_gradient
	)

	formations[team] = formation


func identify_formations_from_gradients(
	_influence_map: InfluenceMap,
	gradients: Array[UnitInfluenceGradient],
	best_gradient: UnitInfluenceGradient
) -> FormationIdentification:
	return FormationAnalyzer.identify_from_gradients(gradients, best_gradient)


func _write_static_terrain_for_map(influence_map: InfluenceMap) -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		return

	var used_cells: Array[Vector2i] = LOSHelper.ground_layer.get_used_cells()

	for cell: Vector2i in used_cells:
		var cover_value: float = _get_cover_value_for_cell(cell)
		var move_cost: float = _get_move_cost_for_cell(cell)

		influence_map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, cover_value)
		influence_map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, move_cost)


func _write_visibility_for_team(influence_map: InfluenceMap, team: int) -> void:
	var enemy_team: int = Globals.get_enemy_team(team)
	var visible_hexes: Array = LOSHelper.visible_hexes.get(enemy_team, [])

	for cell: Vector2i in visible_hexes:
		influence_map.max_layer_value(InfluenceMap.Layer.VISIBILITY, cell, 1.0)


func rebuild_los_influence_for_team(influence_map: InfluenceMap, team: int) -> void:
	var config: InfluenceProjectionConfig = _create_los_config_for_team(team)
	LosInfluenceProjector.rebuild_los_influence_for_team(influence_map, config)


func _clear_los_influence_layers(influence_map: InfluenceMap) -> void:
	LosInfluenceProjector.clear_los_layers(influence_map)


func _project_actual_friendly_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	LosInfluenceProjector.project_actual_friendly_los(influence_map, config)


func _project_simulated_enemy_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	LosInfluenceProjector.project_simulated_enemy_los(influence_map, config)


func _project_actual_enemy_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	LosInfluenceProjector.project_actual_enemy_los(influence_map, config)


func _project_los_from_source(
	influence_map: InfluenceMap,
	source: ProjectionSource,
	project_as_friendly: bool
) -> void:
	LosInfluenceProjector.project_los_from_source(influence_map, source, project_as_friendly)


func _project_friendly_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	LosInfluenceProjector.project_friendly_los_record(
		influence_map,
		observer_hex,
		target_hex,
		los_data,
		unit_firepower,
		unit_effectiveness
	)


func _project_enemy_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	LosInfluenceProjector.project_enemy_los_record(
		influence_map,
		observer_hex,
		target_hex,
		los_data,
		unit_firepower,
		unit_effectiveness
	)


func _read_los_float(data: Dictionary, key: String, fallback: float) -> float:
	return LosInfluenceProjector.read_los_float(data, key, fallback)


func _get_unit_firepower(unit: Unit) -> float:
	return InfluenceUnitQuery.get_unit_firepower(unit)


func _get_unit_effectiveness(unit: Unit) -> float:
	return InfluenceUnitQuery.get_unit_effectiveness(unit)


func _calculate_los_fire_threat(
	enemy_firepower: float,
	enemy_effectiveness: float,
	target_cover: float,
	hindrance: float,
	distance: int
) -> float:
	return LosInfluenceProjector.calculate_los_fire_threat(
		enemy_firepower,
		enemy_effectiveness,
		target_cover,
		hindrance,
		distance
	)


func _get_range_threat_multiplier(distance: int) -> float:
	return LosInfluenceProjector.get_range_threat_multiplier(distance)


func _write_friendly_support_for_team(influence_map: InfluenceMap, team: int) -> void:
	for unit: Unit in Globals.get_units():
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		if unit.team != team:
			continue

		var support_radius: int = 5
		var support_value: float = _get_unit_support_value(unit)

		influence_map.stamp_radius(
			InfluenceMap.Layer.FRIENDLY_SUPPORT,
			unit.current_hex,
			support_radius,
			support_value,
			InfluenceMap.WriteMode.ADD,
			InfluenceMap.FalloffMode.LINEAR
		)


func _write_known_enemy_positions_for_team(influence_map: InfluenceMap, team: int) -> void:
	var enemy_team: int = Globals.get_enemy_team(team)

	for unit: Unit in Globals.get_units():
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		if unit.team != enemy_team:
			continue

		if not _team_has_contact_on_unit(team, unit):
			continue

		influence_map.stamp_radius(
			InfluenceMap.Layer.KNOWN_ENEMY_POSITION,
			unit.current_hex,
			2,
			1.0,
			InfluenceMap.WriteMode.MAX,
			InfluenceMap.FalloffMode.LINEAR
		)


func _get_cover_value_for_cell(cell: Vector2i) -> float:
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(
		LOSHelper.ground_layer.map_to_local(cell)
	)
	var terrain_defence_bonus_normalized: float = remap(terrain_defence_bonus, 0.0, 3.0, 0.0, 1.0)
	return terrain_defence_bonus_normalized


func _get_move_cost_for_cell(cell: Vector2i) -> float:
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(
		LOSHelper.ground_layer.map_to_local(cell)
	)

	if terrain_defence_bonus > 0:
		return 1.0

	return 0.0


func _get_unit_threat_value(unit: Unit) -> float:
	var threat: float = 1.0

	if unit.combat_stats != null:
		threat *= unit.combat_stats.combat_effectiveness

	return threat


func _get_unit_support_value(unit: Unit) -> float:
	var support: float = 1.0

	if unit.combat_stats != null:
		support *= unit.combat_stats.combat_effectiveness

	return support


func _team_has_contact_on_unit(team: int, enemy_unit: Unit) -> bool:
	var visible_enemies: Array = Globals.team_visible_enemies.get(team, [])

	if visible_enemies.has(enemy_unit):
		return true

	return false


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event == null:
		return

	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_button_event.pressed == false:
		return

	if mouse_button_event.ctrl_pressed == false:
		return

	objective_hex = LOSHelper.ground_layer.local_to_map(get_global_mouse_position())
	print("objective hex: ", objective_hex)


func _calculate_unit_gradient_to_influence_center(
	unit: Unit,
	target_map: InfluenceMap,
	target_center_hex: Vector2i
) -> UnitInfluenceGradient:
	var from_hex: Vector2i = unit.current_hex
	var value_here: float = target_map.get_unit_influence_value(target_map, from_hex)

	var best_hex: Vector2i = from_hex
	var best_value: float = value_here
	var best_score: float = -INF

	var current_center_distance: int = LOSHelper.get_hex_distance(from_hex, target_center_hex)
	var neighbors: Array[Vector2i] = LOSHelper.get_hex_neighbors(from_hex)

	for neighbor_hex: Vector2i in neighbors:
		if not target_map.is_valid_cell(neighbor_hex):
			continue

		var neighbor_value: float = target_map.get_unit_influence_value(target_map, neighbor_hex)
		var influence_gain: float = neighbor_value - value_here

		var neighbor_center_distance: int = LOSHelper.get_hex_distance(neighbor_hex, target_center_hex)
		var center_gain: float = float(current_center_distance - neighbor_center_distance)

		var score: float = influence_gain
		score += center_gain * InfluenceMap.UNIT_INFLUENCE_CENTER_PULL_WEIGHT

		if score > best_score:
			best_score = score
			best_hex = neighbor_hex
			best_value = neighbor_value

	return UnitInfluenceGradient.new(
		unit,
		from_hex,
		best_hex,
		value_here,
		best_value
	)


func calculate_enemy_gradient_steps_to_team_center(
	enemy_team: int,
	target_team: int,
	target_center_hex: Vector2i
) -> Dictionary:
	var result: Dictionary = {}

	if not maps_by_team.has(target_team):
		return result

	var target_map: InfluenceMap = maps_by_team[target_team]
	var enemies: Array[Unit] = Globals.get_units_for_team(enemy_team)

	for enemy: Unit in enemies:
		if not InfluenceUnitQuery.is_valid_living_unit(enemy):
			continue

		var next_hex: Vector2i = target_map.get_best_gradient_neighbor(
			InfluenceMap.Layer.UNIT_INFLUENCE,
			enemy.current_hex,
			target_center_hex,
			InfluenceMap.UNIT_INFLUENCE_CENTER_PULL_WEIGHT
		)

		result[enemy] = next_hex

	return result


func calculate_enemy_gradients_to_team_center(
	enemy_team: int,
	target_team: int,
	target_center_hex: Vector2i
) -> Array[UnitInfluenceGradient]:
	var result: Array[UnitInfluenceGradient] = []

	if not maps_by_team.has(enemy_team):
		return result

	var target_map: InfluenceMap = maps_by_team[enemy_team]
	var enemies: Array[Unit] = Globals.get_units_for_team(target_team)

	for enemy: Unit in enemies:
		if not InfluenceUnitQuery.is_valid_living_unit(enemy):
			continue

		var gradient: UnitInfluenceGradient = _calculate_unit_gradient_to_influence_center(
			enemy,
			target_map,
			target_center_hex
		)

		result.append(gradient)

	return result


func _project_simulated_enemy_los_from_units(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	enemy_units: Array[Unit]
) -> void:
	LosInfluenceProjector.project_simulated_enemy_los_from_units(
		influence_map,
		config,
		enemy_units
	)


func _create_axis_composite_from_enemy_units(
	source_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	axis_enemy_units: Array[Unit]
) -> PackedFloat32Array:
	return LosInfluenceProjector.create_axis_composite_from_enemy_units(
		source_map,
		config,
		axis_enemy_units,
		create_default_weights()
	)


func _begin_los_rebuild_for_team(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	LosInfluenceProjector.begin_budgeted_rebuild_for_team(self, influence_map, config)


func _process_los_rebuild() -> void:
	LosInfluenceProjector.process_budgeted_rebuild(self, LOS_SOURCES_PER_FRAME)


func _clear_dynamic_layers_for_team(influence_map: InfluenceMap) -> void:
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.VISIBILITY, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.FIRE_POWER, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.FRIENDLY_SUPPORT, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.KNOWN_ENEMY_POSITION, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.UNIT_INFLUENCE, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.COVER_VS_ENEMY_FIRE, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.VISIBILITY_HINDRANCE, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.RETURN_FIRE_PENALTY, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.THREAT, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
	influence_map.clear_layer_without_dirty(InfluenceMap.Layer.ENEMY_VULNERABILITY, 0.0)

	influence_map.mark_all_dirty()


func _get_config_units(team: int, group_name: String) -> Array[Unit]:
	return InfluenceUnitQuery.get_config_units(team, group_name)


func _is_valid_living_unit(unit: Unit) -> bool:
	return InfluenceUnitQuery.is_valid_living_unit(unit)


func _get_squad_type_priority(squad_type: Globals.SquadType) -> int:
	return InfluenceUnitQuery.get_squad_type_priority(squad_type)


func _compare_units_by_squad_type_priority(unit_a: Unit, unit_b: Unit) -> bool:
	return InfluenceUnitQuery.compare_units_by_squad_type_priority(unit_a, unit_b)


func _create_projected_approach_stamp(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	enemy_units: Array[Unit]
) -> InfluenceStamp:
	return DefensePositionAnalyzer.create_projected_approach_stamp(
		influence_map,
		config,
		enemy_units
	)


func _create_projected_approach_stamp_with_threataxis(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> InfluenceStamp:
	return DefensePositionAnalyzer.create_projected_approach_stamp_for_threat_axis(
		influence_map,
		config
	)


func _build_projected_line_sources_from_axis_alt(
	axis: ThreatAxis,
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	return ProjectionSourceBuilder.build_from_threat_axis(axis, objective, max_cells, skip_front, count)


func _build_projected_line_sources(
	units: Array[Unit],
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	return ProjectionSourceBuilder.build_from_units(units, objective, max_cells, skip_front, count)


func _get_projected_line_hexes(
	from_hex: Vector2i,
	to_hex: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[Vector2i]:
	return ProjectionSourceBuilder.get_projected_line_hexes(from_hex, to_hex, max_cells, skip_front, count)
