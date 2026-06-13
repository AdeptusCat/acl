class_name InfluenceMapController
extends Node2D

signal influence_maps_updated()

const REBUILD_CELLS_PER_FRAME: int = 400

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
#var reserved_hexes: Array[Vector2i] = []
var reserved_hexes: Dictionary[Unit, Vector2i] = {}

var rebuild_pending: bool = false

var objective_hex: Vector2i = Vector2i(11, 13)
#var objective_hex: Vector2i = Vector2i(11, 10)

enum CompositeSource {
	SELF,
	ENEMY
}

enum TacticalTask {
	NONE,
	DEFEND_OBJECTIVE,
	ATTACK_OBJECTIVE
}

const FORMATION_GROUP_RADIUS: int = 3

enum FormationRole {
	FRONT,
	FLANK
}

class FormationGroup:
	var role: FormationRole = FormationRole.FRONT
	var seed_gradient: InfluenceMap.UnitInfluenceGradient = null
	var seed_unit: Unit = null
	var seed_hex: Vector2i = Vector2i.ZERO
	var gradients: Array[InfluenceMap.UnitInfluenceGradient] = []
	var units: Array[Unit] = []

	func _init(
		p_role: FormationRole,
		p_seed_gradient: InfluenceMap.UnitInfluenceGradient
	) -> void:
		role = p_role
		seed_gradient = p_seed_gradient

		if seed_gradient != null:
			seed_unit = seed_gradient.unit
			seed_hex = seed_gradient.from_hex


class FormationIdentification:
	var front: FormationGroup = null
	var flanks: Array[FormationGroup] = []

class InfluenceProjectionConfig:
	var unit_team: int = Globals.Team.AXIS
	var enemy_team: int = Globals.Team.ALLIES
	var unit_group: String = ""
	var enemy_group: String = ""
	var task: int = TacticalTask.DEFEND_OBJECTIVE
	var objective_hex: Vector2i = Vector2i.ZERO
	var enemy_units: Array[Unit]

	var projected_line_max_cells: int = 8

	# Used for destination stamp.
	var anchor_skip_front: int = 3
	var anchor_count: int = 1

	# Used for simulated enemy LOS.
	var los_skip_front: int = 4
	var los_count: int = 4

	var move_improvement_ratio: float = 0.8
	var threat_axis: ThreatAxis = null


class ProjectionSource:
	var unit: Unit = null
	var observer_hex: Vector2i = Vector2i.ZERO
	var firepower: float = 0.0
	var effectiveness: float = 0.0

	func _init(
		p_unit: Unit,
		p_observer_hex: Vector2i,
		p_firepower: float,
		p_effectiveness: float
	) -> void:
		unit = p_unit
		observer_hex = p_observer_hex
		firepower = p_firepower
		effectiveness = p_effectiveness

class CompositeTerm:
	var source: int = CompositeSource.SELF
	var layer: int = InfluenceMap.Layer.TERRAIN_COVER
	var weight: float = 0.0

	func _init(p_source: int, p_layer: int, p_weight: float) -> void:
		source = p_source
		layer = p_layer
		weight = p_weight

#func _ready() -> void:
	#create_maps()

var update_counter: float = 0
var update_threshold: float = 1.0

func _process(_delta: float) -> void:
	_update_rebuild_timer(_delta)
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
	#_run_post_rebuild_tactical_tasks()
	
	## test ###
	#var influence_map1: InfluenceMap = maps_by_team[Globals.Team.AXIS]
	#influence_map1._layers[InfluenceMap.Layer.ORIGIN_INFLUENCE]
	#var stamp: InfluenceMap.InfluenceStamp = influence_map1.create_radius_stamp(
			#Vector2i(5,5),
			#5,
			#1.0,
			#InfluenceMap.FalloffMode.EXPONENTIAL
		#)
	#var result: PackedFloat32Array = influence_map1.write_stamp_to_layer_with_return(
			#influence_map1._layers[InfluenceMap.Layer.ORIGIN_INFLUENCE],
			#stamp,
			#InfluenceMap.WriteMode.ADD
		#)
	#influence_map1._layers[InfluenceMap.Layer.ORIGIN_INFLUENCE] = result


func _run_post_rebuild_tactical_tasks() -> void:
	var config: InfluenceProjectionConfig = _create_axis_defense_config()
	config.objective_hex = objective_hex
	_assign_best_positions_for_config(config)


func run_post_rebuild_tactical_tasks_with_threataxis(axis: ThreatAxis, units: Array[Unit]) -> void:
	var config: InfluenceProjectionConfig = _create_axis_defense_config()
	config.objective_hex = objective_hex
	config.threat_axis = axis
	_assign_best_positions_for_config_and_threataxis(config, units, axis.enemy_units)


func _create_axis_defense_config() -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()

	config.unit_team = Globals.Team.AXIS
	config.enemy_team = Globals.Team.ALLIES
	config.unit_group = ""
	config.enemy_group = ""
	config.task = TacticalTask.DEFEND_OBJECTIVE
	config.objective_hex = objective_hex
	
	# we draw a line from objective_hex to an enemy unit
	# the line is at most projected_line_max_cells long or shorter if enemy closer
	# the first los_skip_front/anchor_skip_front hexes are skipped
	# the amount of hexes considered are los_count/anchor_count
	
	# Simulated enemy LOS
	# enemy -> [skip skip skip skip] [LOS LOS LOS LOS] -> objective
	# los_skip_front / los_count is for estimating where enemies can see or project threat from.
	
	# anchor_skip_front / anchor_count is for choosing the projected 
	# enemy -> [skip skip skip] [ANCHOR] -> objective
	# destination/pressure point used to pull movement toward a tactical position.
	
	# forward defense
	#config.projected_line_max_cells = 8
	#config.anchor_skip_front = 4 # simulate enemies at this distance from objective
	#config.anchor_count = 1
	#config.los_skip_front = 4
	#config.los_count = 1
	#config.move_improvement_ratio = 0.8
	
	# home defense
	config.projected_line_max_cells = 6 # how many hexes from objective to the actual enemy are used to create fake LOS
	config.anchor_skip_front = 1 # simulate enemies at this distance from objective
	config.anchor_count = 4 # the amount of simulated LOS positions actually considered
	config.los_skip_front = 1
	config.los_count = 4
	config.move_improvement_ratio = 0.8
	
	# EXAMPLE
	#config.projected_line_max_cells = 8
	#config.anchor_skip_front = 1
	#config.anchor_count = 3
	#objective
	#0 1 2 3 4 5 6 7 enemy direction
	#Selected anchors:
	#[1 2 3]
	
	return config


func _assign_best_positions_for_config(config: InfluenceProjectionConfig) -> void:
	var units: Array[Unit] = _get_config_units(config.unit_team, config.unit_group)
	var enemy_units: Array[Unit] = _get_config_units(config.enemy_team, config.enemy_group)

	if units.is_empty():
		return

	if enemy_units.is_empty():
		return

	var reserved_hexes: Array[Vector2i] = []
	
	var ordered_units: Array[Unit] = []

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		if not maps_by_team.has(unit.team):
			continue

		ordered_units.append(unit)

	ordered_units.sort_custom(_compare_units_by_squad_type_priority)

	for unit: Unit in ordered_units:
		var influence_map: InfluenceMap = maps_by_team[unit.team]

		var approach_stamp: InfluenceMap.InfluenceStamp = _create_projected_approach_stamp(
			influence_map,
			config,
			enemy_units
		)

		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(reserved_hexes)

		var composite: PackedFloat32Array = influence_map._composite

		var result: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		result = influence_map.multiply_layers_with_return(result, reserved_stamp)

		var best_index: int = influence_map.get_max_value_index(result)
		if best_index == -1:
			continue

		var best_value: float = result[best_index]
		var best_hex: Vector2i = influence_map.index_to_cell(best_index)

		reserved_hexes.append(best_hex)

		var previous_best_value: float = -INF
		if unit.best_index >= 0 and unit.best_index < result.size():
			previous_best_value = result[unit.best_index]

		# TODO convert this to platoon ai
		if best_value * config.move_improvement_ratio > previous_best_value:
			unit.order(Globals.UnitCmd.MOVE, best_hex)
			unit.best_index = best_index

		unit.influence_map = result




func _assign_best_positions_for_config_and_threataxis(
	config: InfluenceProjectionConfig,
	axis_units: Array[Unit],
	axis_enemy_units: Array[Unit]
) -> void:
	var units: Array[Unit] = axis_units

	if units.is_empty():
		units = _get_config_units(config.unit_team, config.unit_group)

	if units.is_empty():
		return

	if config.threat_axis == null:
		var enemy_units: Array[Unit] = _get_config_units(config.enemy_team, config.enemy_group)
		if enemy_units.is_empty():
			return
	
	var influence_map: InfluenceMap = maps_by_team[units[0].team]

	var composite: PackedFloat32Array = _create_axis_composite_from_enemy_units(
		influence_map,
		config,
		axis_enemy_units
	)
	
	var ordered_units: Array[Unit] = []

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		if not maps_by_team.has(unit.team):
			continue

		ordered_units.append(unit)

	ordered_units.sort_custom(_compare_units_by_squad_type_priority)

	for unit: Unit in ordered_units:
		#var influence_map: InfluenceMap = maps_by_team[unit.team]

		var approach_stamp: InfluenceMap.InfluenceStamp = _create_projected_approach_stamp_with_threataxis(
			influence_map,
			config
		)
		var approach_stamp_full: PackedFloat32Array = influence_map.stamp_to_full_map_array(
			approach_stamp,
			0.0
		)
		
		var reserved_hexes_duplicate: Dictionary[Unit, Vector2i] = reserved_hexes.duplicate()
		reserved_hexes_duplicate.erase(unit)
		var reserved_hexes_array: Array[Vector2i]
		for hex in reserved_hexes_duplicate.values():
			reserved_hexes_array.append(hex)
			
		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(reserved_hexes_array)
		var reserved_stamp_full: PackedFloat32Array = reserved_stamp.duplicate()
		#var composite: PackedFloat32Array = influence_map._composite
		#var composite: PackedFloat32Array = _create_axis_composite_from_enemy_units(
			#influence_map,
			#config,
			#axis_enemy_units
		#)

		var result: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		result = influence_map.multiply_layers_with_return(result, reserved_stamp)
		
		
		result = influence_map.apply_positive_mask_layer_with_return(
			result,
			influence_map._layers[InfluenceMap.Layer.UNIT_INFLUENCE]
		)

		var best_index: int = influence_map.get_max_value_index(result)
		if best_index == -1:
			continue

		var best_value: float = result[best_index]
		var best_hex: Vector2i = influence_map.index_to_cell(best_index)
		
		reserved_hexes[unit] = best_hex

		var previous_best_value: float = -INF
		if unit.best_index >= 0 and unit.best_index < result.size():
			previous_best_value = result[unit.best_index]
		
		# TODO use unit influence layer to mask the approach stamp, positive unit influence allows defense to grow there
		# TODO use global reserved hexes layer otherwise different defense axis cannot see whos reserving hexes
		
		# TODO calculate COMPOSITE and its enemy LOS simulation for that particular axis to defend and not all enemy LOS 
		# otherwise the unit cannot concentrate on defending its axis 
		
		# TODO convert this to platoon ai
		if best_value * config.move_improvement_ratio > previous_best_value:
			prints(unit, best_value,previous_best_value,best_hex)
			unit.order(Globals.UnitCmd.MOVE, best_hex)
			unit.best_index = best_index
			
		# FIXME it seems like the composite enemy LOS calculation if wrong? its not projecting towards the enemies?
		#unit.influence_map = reserved_stamp_full
		#unit.influence_map = aapproach_stamp_full
		#unit.influence_map = compossite
		unit.influence_map = result
		pass



func _get_squad_type_priority(squad_type: Globals.SquadType) -> int:
	if squad_type == Globals.SquadType.MG:
		return 0

	if squad_type == Globals.SquadType.Rifle:
		return 1

	if squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		return 2

	if squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return 3

	if squad_type == Globals.SquadType.ANTITANK:
		return 4

	if squad_type == Globals.SquadType.MORTAR:
		return 5

	return 999


func _compare_units_by_squad_type_priority(unit_a: Unit, unit_b: Unit) -> bool:
	var priority_a: int = _get_squad_type_priority(unit_a.squad_type)
	var priority_b: int = _get_squad_type_priority(unit_b.squad_type)

	if priority_a == priority_b:
		return unit_a.get_instance_id() < unit_b.get_instance_id()

	return priority_a < priority_b


func _create_projected_approach_stamp(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	enemy_units: Array[Unit]
) -> InfluenceMap.InfluenceStamp:
	var sources: Array[ProjectionSource] = _build_projected_line_sources(
		enemy_units,
		config.objective_hex,
		config.projected_line_max_cells,
		config.anchor_skip_front,
		config.anchor_count
	)

	var combined_stamp: InfluenceMap.InfluenceStamp = null
	var has_stamp: bool = false

	for source: ProjectionSource in sources:
		var stamp: InfluenceMap.InfluenceStamp = influence_map.create_radius_stamp(
			source.observer_hex,
			2,
			1.0,
			InfluenceMap.FalloffMode.SQUARE_ROOT
		)

		if not has_stamp:
			combined_stamp = stamp
			has_stamp = true
		else:
			combined_stamp = influence_map.add_stamps_with_return(
				combined_stamp,
				stamp
			)

	if not has_stamp:
		combined_stamp = InfluenceMap.InfluenceStamp.new(Vector2i.ZERO, Vector2i.ZERO)

	return combined_stamp



func _create_projected_approach_stamp_with_threataxis(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> InfluenceMap.InfluenceStamp:
	var sources: Array[ProjectionSource] = []

	if config.threat_axis != null:
		sources = _build_projected_line_sources_from_axis_alt(
			config.threat_axis,
			config.objective_hex,
			config.projected_line_max_cells,
			config.anchor_skip_front,
			config.anchor_count
		)
	else:
		var enemy_units: Array[Unit] = _get_config_units(config.enemy_team, config.enemy_group)
		sources = _build_projected_line_sources(
			enemy_units,
			config.objective_hex,
			config.projected_line_max_cells,
			config.anchor_skip_front,
			config.anchor_count
		)

	var combined_stamp: InfluenceMap.InfluenceStamp = null
	var has_stamp: bool = false

	for source: ProjectionSource in sources:
		var stamp: InfluenceMap.InfluenceStamp = influence_map.create_radius_stamp(
			source.observer_hex,
			3,
			1.0,
			InfluenceMap.FalloffMode.SQUARE_ROOT
		)

		if not has_stamp:
			combined_stamp = stamp
			has_stamp = true
		else:
			combined_stamp = influence_map.add_stamps_with_return(
				combined_stamp,
				stamp,
				1.0
			)

	if not has_stamp:
		combined_stamp = InfluenceMap.InfluenceStamp.new(Vector2i.ZERO, Vector2i.ZERO)

	return combined_stamp


func _build_projected_line_sources_from_axis_alt(
	axis: ThreatAxis,
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	var sources: Array[ProjectionSource] = []

	if axis == null:
		return sources

	var projected_hexes: Array[Vector2i] = _get_projected_line_hexes(
		objective,
		axis.source_hex,
		max_cells,
		skip_front,
		count
	)

	for observer_hex: Vector2i in projected_hexes:
		var source: ProjectionSource = ProjectionSource.new(
			null,
			observer_hex,
			1.0,
			1.0
		)

		sources.append(source)

	return sources



#func _create_projected_approach_stamp(
	#influence_map: InfluenceMap,
	#config: InfluenceProjectionConfig,
	#enemy_units: Array[Unit]
#) -> PackedFloat32Array:
	#var sources: Array[ProjectionSource] = _build_projected_line_sources(
		#enemy_units,
		#config.objective_hex,
		#config.projected_line_max_cells,
		#config.anchor_skip_front,
		#config.anchor_count
	#)
#
	#var combined_stamp: PackedFloat32Array = PackedFloat32Array()
	#var has_stamp: bool = false
#
	#for source: ProjectionSource in sources:
		##var stamp: PackedFloat32Array = influence_map.create_origin_stamp(source.observer_hex)
		#var stamp: PackedFloat32Array = influence_map.create_radius_stamp(
			#source.observer_hex,
			#3,
			#1.0,
			#InfluenceMap.FalloffMode.SQUARE_ROOT
		#)
		#
#
		#if not has_stamp:
			#combined_stamp = stamp
			#has_stamp = true
		#else:
			#combined_stamp = influence_map.add_layers_with_return(combined_stamp, stamp)
#
	#return combined_stamp


func _build_projected_line_sources(
	units: Array[Unit],
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	var sources: Array[ProjectionSource] = []

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		var projected_hexes: Array[Vector2i] = _get_projected_line_hexes(
			objective,
			unit.current_hex,
			max_cells,
			skip_front,
			count
		)

		var firepower: float = _get_unit_firepower(unit)
		var effectiveness: float = _get_unit_effectiveness(unit)

		for observer_hex: Vector2i in projected_hexes:
			var source: ProjectionSource = ProjectionSource.new(
				unit,
				observer_hex,
				firepower,
				effectiveness
			)

			sources.append(source)

	return sources


func _get_projected_line_hexes(
	from_hex: Vector2i,
	to_hex: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not is_instance_valid(LOSHelper.ground_layer):
		return result

	var from_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(from_hex)
	var to_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(to_hex)
	var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(from_cube, to_cube)

	if line.is_empty():
		return result

	var start_index: int = skip_front
	if start_index < 0:
		start_index = 0

	var end_index: int = line.size()

	if max_cells > 0 and max_cells < end_index:
		end_index = max_cells

	if count > 0:
		var counted_end_index: int = start_index + count
		if counted_end_index < end_index:
			end_index = counted_end_index

	if start_index >= end_index:
		return result

	for index: int in range(start_index, end_index):
		var cube: Vector3i = line[index]
		var hex: Vector2i = LOSHelper.ground_layer.cube_to_map(cube)

		if hex == from_hex:
			continue

		if hex == Vector2i.ZERO:
			continue

		result.append(hex)

	return result


func _get_config_units(team: int, group_name: String) -> Array[Unit]:
	var result: Array[Unit] = []
	var units: Array[Unit] = Globals.get_units_for_team(team)

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		if group_name != "":
			if not unit.is_in_group(group_name):
				continue

		result.append(unit)

	return result


func _is_valid_living_unit(unit: Unit) -> bool:
	if not is_instance_valid(unit):
		return false

	if not unit.alive:
		return false

	return true


#func _process(_delta: float) -> void:
	#update_counter += _delta
	#if update_counter > update_threshold:
		#update_counter = 0.0
		##rebuild_dynamic_tactical_layers()
		#create_maps(update_threshold)
	#
	#if not rebuild_pending:
		#return
#
	#var all_done: bool = true
#
	#for team: int in maps_by_team.keys():
		#var influence_map: InfluenceMap = maps_by_team[team]
		#var done: bool = influence_map.rebuild_dirty_composite_budgeted(REBUILD_CELLS_PER_FRAME)
#
		#if not done:
			#all_done = false
#
	#if all_done:
		#rebuild_pending = false
		#influence_maps_updated.emit()
		#
		#
		#
		#var objective_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(objective_hex)
	##var unit: Unit = Globals.get_units()[0]
		##for unit in Globals.get_units_for_team(Globals.Team.ALLIES):
			##var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(objective_cube, unit.current_cube)
			##line.resize(4)
		#
		#var reserved_hexes: Array[Vector2i]
		#for unit in Globals.get_units_for_team(Globals.Team.AXIS):
			#var influence_map: InfluenceMap = maps_by_team[unit.team]
			#
			#var unit_stamp: PackedFloat32Array = influence_map.create_unit_stamp(unit)
			#var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(reserved_hexes)
			##var stamp: PackedFloat32Array = influence_map.create_origin_stamp(unit.current_hex)
			##var stamp: PackedFloat32Array = influence_map.create_origin_stamp(objective_hex)
			##var stamp: PackedFloat32Array = influence_map.create_origin_stasmp(objective_hex)
			#
			#var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(objective_cube, Globals.get_units_for_team(Globals.Team.ALLIES)[0].current_cube)
			##line.resize(4)
			#line.resize(8)
			#for i in range(3):
				#line.pop_front()
			#var defense_cube: Vector3i = line.pop_front()
			#var defense_hex: Vector2i = LOSHelper.ground_layer.cube_to_map(defense_cube)
			#var stamp: PackedFloat32Array = influence_map.create_origin_stamp(defense_hex)
			#
			##var stamp_alt: PackedFloat32Array = influence_map.create_origin_stamp(objective_hex)
			#var composite: PackedFloat32Array = influence_map._composite
			#var result: PackedFloat32Array = influence_map.multiply_layers_with_return(stamp, composite)
			#result = influence_map.multiply_layers_with_return(result, reserved_stamp)
			#
			##var composite: PackedFloat32Array = influence_map._composite
			###var result: PackedFloat32Array = influence_map.multiply_layers_with_return(stamp, composite)
			##var result: PackedFloat32Array = composite
			##result = influence_map.multiply_layers_with_return(result, reserved_stamp)
			###result = influence_map.multiply_layers_with_return(result, unit_stamp)
			#
			##var result: PackedFloat32Array = influence_map.add_layers_with_return(stamp, composite)
			##result = influence_map.multiply_layers_with_return(stamp, result)
			##result = influence_map.multiply_layers_with_return(result, unit_stamp)
			#
			##var result: PackedFloat32Array = stamp
			#
			#var best_index: int = influence_map.get_max_value_index(result)
			#if best_index == -1:
				#continue
			#
			#var best_value: float = result[best_index]
			#var best_hex: Vector2i = influence_map.index_to_cell(best_index)
			#reserved_hexes.append(best_hex)
			#
			#var prev_best_value: float = result[unit.best_index]
			#if best_value * 0.8 > prev_best_value:
				#unit.order(Globals.UnitCmd.MOVE, best_hex)
				#unit.best_index = best_index
			#unit.influence_map = result
			#
			##print(unit.name, " best hex: ", best_hex, " value: ", best_value)
			#pass
			### CAREFUL ##
			##maps_by_team[unit.team]._composite = stamp
			##maps_by_team[unit.team]._composite = unit_stamp
		#pass
		#
	#


func create_maps(delta) -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		return

	var bounds: Rect2i = LOSHelper.ground_layer.get_used_rect()

	var allied_map: InfluenceMap = InfluenceMap.new()
	var axis_map: InfluenceMap = InfluenceMap.new()

	allied_map.configure(bounds)
	axis_map.configure(bounds)

	allied_weights = _create_default_weights()
	axis_weights = _create_default_weights()

	allied_map.configure_composite_weights(allied_weights, 0.0, 0.00, 20.0)
	axis_map.configure_composite_weights(axis_weights, 0.0, 0.00, 20.0)

	maps_by_team[Globals.Team.ALLIES] = allied_map
	maps_by_team[Globals.Team.AXIS] = axis_map
	
	var origin_hex: Vector2i = Vector2i(11, 3)
	#var allied_map: InfluenceMap = maps_by_team[Globals.Team.ALLIES]
	#if allied_map != null:
		#allied_map.stamp_origin_influence(origin_hex)
	#if allied_map != null:
		#allied_map.update_origin_influence_decay(delta)
	#if axis_map != null:
		#axis_map.stamp_origin_influence(origin_hex)
	#if axis_map != null:
		#axis_map.update_origin_influence_decay(delta)
	
	rebuild_pending = true
	
	rebuild_static_terrain_layers()
	rebuild_dynamic_tactical_layers()
	
	# multiplying leads to interesting results
	#maps_by_team[Globals.Team.AXIS].multiply_layers(
	#InfluenceMap.Layer.THREAT,
	#InfluenceMap.Layer.FIRE_POWER,
	#InfluenceMap.Layer.TERRAIN_COVER
	#)


func _create_default_weights() -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(InfluenceMap.Layer.COUNT)
	weights.fill(0.0)

	# Negative values increase movement cost / danger.
	# Positive values reduce movement cost / attract movement.
	
	#TERRAIN_COVER,
	#TERRAIN_MOVE_COST,
	#ENEMY_VISIBILITY,
	#VISIBILITY,
	#FIRE_POWER,
	#THREAT,
	#ENEMY_VULNERABILITY,
	#COVER_VS_ENEMY_FIRE,
	#VISIBILITY_HINDRANCE,

	#weights[InfluenceMap.Layer.TERRAIN_COVER] = -0.40
	#weights[InfluenceMap.Layer.TERRAIN_MOVE_COST] = 1.00
	#weights[InfluenceMap.Layer.VISIBILITY] = 2.00
	#weights[InfluenceMap.Layer.FIRE_POWER] = 3.00
	#weights[InfluenceMap.Layer.FRIENDLY_SUPPORT] = -0.50
	#weights[InfluenceMap.Layer.OBJECTIVE_PRESSURE] = -0.75
	#weights[InfluenceMap.Layer.KNOWN_ENEMY_POSITION] = 1.50
	#weights[InfluenceMap.Layer.NO_GO] = 20.00
	
	# this works with predicted enemy aproach
	weights[InfluenceMap.Layer.TERRAIN_COVER] = 0.10
	weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.10
	weights[InfluenceMap.Layer.THREAT] = -0.01 # this only makes good close hexes undesirable
	#weights[InfluenceMap.Layer.ENEMY_VISIBILITY] = -1.0
	weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.10
	#weights[InfluenceMap.Layer.ORIGIN_INFLUENCE] = -2.00
	
	## this works quite well for attacker
	#weights[InfluenceMap.Layer.TERRAIN_COVER] = 0.10
	#weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.10
	#weights[InfluenceMap.Layer.THREAT] = -0.1 # this only makes good close hexes undesirable
	###weights[InfluenceMap.Layer.ENEMY_VISIBILITY] = -1.0
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.10
	##weights[InfluenceMap.Layer.ORIGIN_INFLUENCE] = -2.00
	
	# this works good for the attacker
	# might also work for defender
	#weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.50
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.50
	
	# this works for defender quite well since it look for strong points to defend
	# attacker is attracted to move back because its safer
	#weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.90
	#weights[InfluenceMap.Layer.THREAT] = -1.5
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.50
	
	
	#weights[InfluenceMap.Layer.THREAT] = 1.5
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = -0.50
	
	#TERRAIN_COVER,
	#TERRAIN_MOVE_COST,
	#
	#VISIBILITY,
	#FIRE_POWER,
	#
	#COVER_VS_ENEMY_FIRE,
	#VISIBILITY_HINDRANCE,
	#RETURN_FIRE_PENALTY,
	#
	#FRIENDLY_SUPPORT,
	#OBJECTIVE_PRESSURE,
	#KNOWN_ENEMY_POSITION,
	#NO_GO,
	
	#COUNT
	
	return weights


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

		influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.FIRE_POWER, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.FRIENDLY_SUPPORT, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.KNOWN_ENEMY_POSITION, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.UNIT_INFLUENCE, 0.0)

		_write_visibility_for_team(influence_map, team)
		rebuild_los_influence_for_team(influence_map, team)
		_write_unit_influence_for_team(influence_map, team)
		#_write_friendly_support_for_team(influence_map, team)
		#_write_known_enemy_positions_for_team(influence_map, team)

	rebuild_pending = true


func _write_unit_influence_for_team(influence_map: InfluenceMap, team: int) -> void:
	#var units: Array[Unit] = Globals.get_units_for_team(team)
	var units: Array[Unit] = Globals.get_units()

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue
		
		var write_mode: InfluenceMap.WriteMode = InfluenceMap.WriteMode.ADD
		if not team == unit.team:
			write_mode = InfluenceMap.WriteMode.SUBSTRACT
		
		influence_map.stamp_radius(
			InfluenceMap.Layer.UNIT_INFLUENCE,
			unit.current_hex,
			InfluenceMap.UNIT_INFLUENCE_RADIUS,
			InfluenceMap.UNIT_INFLUENCE_VALUE,
			write_mode,
			InfluenceMap.FalloffMode.LINEAR
		)
	
	var max_value_index: int = influence_map.get_max_value_index(influence_map._layers[InfluenceMap.Layer.UNIT_INFLUENCE])
	center_of_mass[team] = influence_map.index_to_cell(max_value_index)
	
	var gradients: Array[InfluenceMap.UnitInfluenceGradient] = calculate_enemy_gradients_to_team_center(
		Globals.get_enemy_team(team),
		team,
		center_of_mass[team]
	)
	
	#for gradient: InfluenceMap.UnitInfluenceGradient in gradients:
		#print(
			#gradient.unit.name,
			#" from ",
			#gradient.from_hex,
			#" next ",
			#gradient.next_hex,
			#" gain ",
			#gradient.influence_gain
		#)
	
	var best_gradient: InfluenceMap.UnitInfluenceGradient = influence_map.get_largest_gradient(gradients)
	#if best_gradient != null:
		#var best_unit: Unit = best_gradient.unit
		#var from_hex: Vector2i = best_gradient.from_hex
		#var next_hex: Vector2i = best_gradient.next_hex
		#var gradient_value: float = best_gradient.influence_gain
#
		#print(best_unit.name)
		#print(from_hex)
		#print(next_hex)
		#print(gradient_value)
	
	var formation: FormationIdentification = identify_formations_from_gradients(
		influence_map,
		gradients,
		best_gradient
	)
	
	formations[team] = formation
	
	print(Globals.TEAM_NAMES[team])
	if formation.front != null:
		print("FRONT seed unit: ", formation.front.seed_unit.name)
		print("FRONT seed hex: ", formation.front.seed_hex)
		print("FRONT unit count: ", formation.front.units.size())

	for flank: FormationGroup in formation.flanks:
		print("FLANK seed unit: ", flank.seed_unit.name)
		print("FLANK seed hex: ", flank.seed_hex)
		print("FLANK unit count: ", flank.units.size())
	
	pass


func identify_formations_from_gradients(
	influence_map: InfluenceMap,
	gradients: Array[InfluenceMap.UnitInfluenceGradient],
	best_gradient: InfluenceMap.UnitInfluenceGradient
) -> FormationIdentification:
	var result: FormationIdentification = FormationIdentification.new()

	if best_gradient == null:
		return result

	var assigned_units: Dictionary = {}

	var front_group: FormationGroup = FormationGroup.new(
		FormationRole.FRONT,
		best_gradient
	)

	result.front = front_group

	for gradient: InfluenceMap.UnitInfluenceGradient in gradients:
		if not _is_valid_gradient(gradient):
			continue

		var distance_to_front: int = LOSHelper.get_hex_distance(
			gradient.from_hex,
			best_gradient.from_hex
		)

		if distance_to_front <= FORMATION_GROUP_RADIUS:
			_add_gradient_to_formation_group(front_group, gradient, assigned_units)

	var remaining_gradients: Array[InfluenceMap.UnitInfluenceGradient] = _get_unassigned_gradients(
		gradients,
		assigned_units
	)

	while not remaining_gradients.is_empty():
		var flank_seed: InfluenceMap.UnitInfluenceGradient = influence_map.get_largest_gradient(
			remaining_gradients
		)

		if flank_seed == null:
			break

		var flank_group: FormationGroup = FormationGroup.new(
			FormationRole.FLANK,
			flank_seed
		)

		_add_gradient_to_formation_group(flank_group, flank_seed, assigned_units)

		for gradient: InfluenceMap.UnitInfluenceGradient in remaining_gradients:
			if not _is_valid_gradient(gradient):
				continue

			if _is_unit_assigned(gradient.unit, assigned_units):
				continue

			var distance_to_flank: int = LOSHelper.get_hex_distance(
				gradient.from_hex,
				flank_seed.from_hex
			)

			if distance_to_flank <= FORMATION_GROUP_RADIUS:
				_add_gradient_to_formation_group(flank_group, gradient, assigned_units)

		result.flanks.append(flank_group)

		remaining_gradients = _get_unassigned_gradients(
			gradients,
			assigned_units
		)

	return result


func _add_gradient_to_formation_group(
	group: FormationGroup,
	gradient: InfluenceMap.UnitInfluenceGradient,
	assigned_units: Dictionary
) -> void:
	if not _is_valid_gradient(gradient):
		return

	if _is_unit_assigned(gradient.unit, assigned_units):
		return

	group.gradients.append(gradient)
	group.units.append(gradient.unit)
	assigned_units[gradient.unit.get_instance_id()] = true


func _get_unassigned_gradients(
	gradients: Array[InfluenceMap.UnitInfluenceGradient],
	assigned_units: Dictionary
) -> Array[InfluenceMap.UnitInfluenceGradient]:
	var result: Array[InfluenceMap.UnitInfluenceGradient] = []

	for gradient: InfluenceMap.UnitInfluenceGradient in gradients:
		if not _is_valid_gradient(gradient):
			continue

		if _is_unit_assigned(gradient.unit, assigned_units):
			continue

		result.append(gradient)

	return result


func _is_valid_gradient(gradient: InfluenceMap.UnitInfluenceGradient) -> bool:
	if gradient == null:
		return false

	if gradient.unit == null:
		return false

	return true


func _is_unit_assigned(unit: Unit, assigned_units: Dictionary) -> bool:
	if unit == null:
		return false

	return assigned_units.has(unit.get_instance_id())


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


#func _write_fire_threat_for_team(influence_map: InfluenceMap, team: int) -> void:
	#var enemy_team: int = _get_enemy_team(team)
#
	#for unit: Unit in Globals.get_units():
		#if not is_instance_valid(unit):
			#continue
#
		#if not unit.alive:
			#continue
#
		#if unit.team != enemy_team:
			#continue
#
		#var threat_radius: int = 8
		#var threat_value: float = _get_unit_threat_value(unit)
#
		#influence_map.stamp_radius(
			#InfluenceMap.Layer.FIRE_POWER,
			#unit.current_hex,
			#threat_radius,
			#threat_value,
			#InfluenceMap.WriteMode.ADD,
			#true
		#)


func rebuild_los_influence_for_team(
	influence_map: InfluenceMap,
	team: int
) -> void:
	_clear_los_influence_layers(influence_map)

	#var config: InfluenceProjectionConfig = _create_los_config_for_team(team)
	# TODO build one for allies as wel
	var config: InfluenceProjectionConfig = _create_axis_defense_config()
	_project_actual_friendly_los(influence_map, config)
	#_project_actual_enemy_los(influence_map, config)
	_project_simulated_enemy_los(influence_map, config)


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


func _clear_los_influence_layers(influence_map: InfluenceMap) -> void:
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.FIRE_POWER, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.COVER_VS_ENEMY_FIRE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY_HINDRANCE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.RETURN_FIRE_PENALTY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VULNERABILITY, 0.0)


func _project_actual_friendly_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	var units: Array[Unit] = _get_config_units(config.unit_team, config.unit_group)
	var los_lookup: Dictionary = LOSHelper.los_lookup

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		var observer_hex: Vector2i = unit.current_hex

		if not los_lookup.has(observer_hex):
			continue

		var source: ProjectionSource = ProjectionSource.new(
			unit,
			observer_hex,
			_get_unit_firepower(unit),
			_get_unit_effectiveness(unit)
		)

		_project_los_from_source(
			influence_map,
			source,
			true
		)


func _project_simulated_enemy_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	var enemy_units: Array[Unit] = _get_config_units(config.enemy_team, config.enemy_group)

	var sources: Array[ProjectionSource] = _build_projected_line_sources(
		enemy_units,
		config.objective_hex,
		config.projected_line_max_cells,
		config.los_skip_front,
		config.los_count
	)

	for source: ProjectionSource in sources:
		_project_los_from_source(
			influence_map,
			source,
			false
		)


func _project_actual_enemy_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	var units: Array[Unit] = _get_config_units(config.enemy_team, config.enemy_group)
	var los_lookup: Dictionary = LOSHelper.los_lookup

	for unit: Unit in units:
		if not _is_valid_living_unit(unit):
			continue

		var observer_hex: Vector2i = unit.current_hex

		if not los_lookup.has(observer_hex):
			continue

		var source: ProjectionSource = ProjectionSource.new(
			unit,
			observer_hex,
			_get_unit_firepower(unit),
			_get_unit_effectiveness(unit)
		)

		_project_los_from_source(
			influence_map,
			source,
			false
		)


func _project_los_from_source(
	influence_map: InfluenceMap,
	source: ProjectionSource,
	project_as_friendly: bool
) -> void:
	var los_lookup: Dictionary = LOSHelper.los_lookup
	var observer_hex: Vector2i = source.observer_hex

	if not los_lookup.has(observer_hex):
		return

	var visible_targets: Dictionary = los_lookup[observer_hex]

	for target_hex: Vector2i in visible_targets.keys():
		if not influence_map.is_valid_cell(target_hex):
			continue

		var los_data: Dictionary = visible_targets[target_hex]

		if project_as_friendly:
			_project_friendly_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				source.firepower,
				source.effectiveness
			)
		else:
			_project_enemy_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				source.firepower,
				source.effectiveness
			)




#func rebuild_los_influence_for_team(
	#influence_map: InfluenceMap,
	#team: int
#) -> void:
	#influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.FIRE_POWER, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.COVER_VS_ENEMY_FIRE, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY_HINDRANCE, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.RETURN_FIRE_PENALTY, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
	#influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VULNERABILITY, 0.0)
	#
	#var enemy_team: int = _get_enemy_team(team)
	#var units: Array[Unit] = Globals.get_units_for_team(team)
	#var enemy_units: Array[Unit] = Globals.get_units_for_team(enemy_team)
	#
	#var los_lookup: Dictionary = LOSHelper.los_lookup
	#for unit: Unit in units:
		#if not is_instance_valid(unit):
			#continue
	#
		#var observer_hex: Vector2i = unit.current_hex
	#
		##var objective_hex: Vector2i = Vector2i(11, 13)
		###var objective_hex: Vector2i = Vector2i(11, 10)
		##var objective_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(objective_hex)
		###for unit in Globals.get_units_for_team(Globals.Team.ALLIES):
		##var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(objective_cube, unit.current_cube)
		##line.resize(4)
		##for cube in line:
			##var hex: Vector2i = LOSHelper.ground_layer.cube_to_map(cube)
			##if not los_lookup.has(hex):
				##continue
			##
			##var visible_targets: Dictionary = los_lookup[hex]
			##var unit_firepower: float = _get_unit_firepower(unit)
			##var unit_effectiveness: float = _get_unit_effectiveness(unit)
			##
			##for target_hex: Vector2i in visible_targets.keys():
				##if not influence_map.is_valid_cell(target_hex):
					##continue
##
				##var los_data: Dictionary = visible_targets[target_hex]
##
				##_project_friendly_los_record(
					##influence_map,
					##hex,
					##target_hex,
					##los_data,
					##unit_firepower,
					##unit_effectiveness
				##)
		#
	#
		#if not los_lookup.has(observer_hex):
			#continue
		#
		#var visible_targets: Dictionary = los_lookup[observer_hex]
		#var unit_firepower: float = _get_unit_firepower(unit)
		#var unit_effectiveness: float = _get_unit_effectiveness(unit)
#
		#for target_hex: Vector2i in visible_targets.keys():
			#if not influence_map.is_valid_cell(target_hex):
				#continue
#
			#var los_data: Dictionary = visible_targets[target_hex]
#
			#_project_friendly_los_record(
				#influence_map,
				#observer_hex,
				#target_hex,
				#los_data,
				#unit_firepower,
				#unit_effectiveness
			#)
	#
	#for unit: Unit in enemy_units:
		#if not is_instance_valid(unit):
			#continue
#
		#var observer_hex: Vector2i = unit.current_hex
		#
		##var objective_hex: Vector2i = Vector2i(11, 13)
		##var objective_hex: Vector2i = Vector2i(11, 10)
		#var objective_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(objective_hex)
		##for unit in Globals.get_units_for_team(Globals.Team.ALLIES):
		#var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(objective_cube, unit.current_cube)
		##line.resize(4)
		#line.resize(8)
		#for i in range(4):
			#line.pop_front()
		##line.pop_front()
		##print("###")
		#for cube in line:
			#var hex: Vector2i = LOSHelper.ground_layer.cube_to_map(cube)
			#if hex == objective_hex:
				#continue
				#
			#if not los_lookup.has(hex):
				#continue
			#
			#if hex == Vector2i.ZERO:
				#continue
			#
			##print(hex)
			#
			#var visible_targets: Dictionary = los_lookup[hex]
			#var unit_firepower: float = _get_unit_firepower(unit)
			#var unit_effectiveness: float = _get_unit_effectiveness(unit)
			#
			#for target_hex: Vector2i in visible_targets.keys():
				#if not influence_map.is_valid_cell(target_hex):
					#continue
#
				#var los_data: Dictionary = visible_targets[target_hex]
#
				#_project_enemy_los_record(
					#influence_map,
					#hex,
					#target_hex,
					#los_data,
					#unit_firepower,
					#unit_effectiveness
				#)
		#
		##if not los_lookup.has(observer_hex):
			##continue
		##
		##var visible_targets: Dictionary = los_lookup[observer_hex]
		##var unit_firepower: float = _get_unit_firepower(unit)
		##var unit_effectiveness: float = _get_unit_effectiveness(unit)
##
		##for target_hex: Vector2i in visible_targets.keys():
			##if not influence_map.is_valid_cell(target_hex):
				##continue
##
			##var los_data: Dictionary = visible_targets[target_hex]
##
			##_project_enemy_los_record(
				##influence_map,
				##observer_hex,
				##target_hex,
				##los_data,
				##unit_firepower,
				##unit_effectiveness
			##)


func _project_friendly_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	var target_cover: float = _read_los_float(los_data, "target_cover", 0.0)
	var shooter_cover: float = _read_los_float(los_data, "shooter_cover", 0.0)
	var hindrance: float = _read_los_float(los_data, "hindrance", 0.0)
	var target_concealment: float = _read_los_float(los_data, "target_concealment", 0.0)
	
	var distance: int = LOSHelper.get_hex_distance(observer_hex, target_hex)
	
	if shooter_cover > 4:
		observer_hex
		pass
	
	var threat: float = _calculate_los_fire_threat(
		unit_firepower,
		unit_effectiveness,
		target_cover,
		hindrance,
		distance
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY,
		target_hex,
		1.0
	)

	influence_map.add_layer_value(
		InfluenceMap.Layer.FIRE_POWER,
		target_hex,
		threat
	)
	
	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY_HINDRANCE,
		target_hex,
		hindrance
	)
	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY_HINDRANCE,
		target_hex,
		target_concealment
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.RETURN_FIRE_PENALTY,
		target_hex,
		shooter_cover
	)


func _project_enemy_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	var target_cover: float = _read_los_float(los_data, "target_cover", 0.0)
	var shooter_cover: float = _read_los_float(los_data, "shooter_cover", 0.0)
	var hindrance: float = _read_los_float(los_data, "hindrance", 0.0)
	var target_concealment: float = _read_los_float(los_data, "target_concealment", 0.0)
	
	var distance: int = LOSHelper.get_hex_distance(observer_hex, target_hex)
	
	var threat: float = _calculate_los_fire_threat(
		unit_firepower,
		unit_effectiveness,
		target_cover,
		hindrance,
		distance
	)
	
	influence_map.max_layer_value(
		InfluenceMap.Layer.COVER_VS_ENEMY_FIRE,
		target_hex,
		target_cover
	)
	
	influence_map.add_layer_value(
		InfluenceMap.Layer.THREAT,
		target_hex,
		threat
	)
	
	influence_map.max_layer_value(
		InfluenceMap.Layer.ENEMY_VISIBILITY,
		target_hex,
		1.0
	)
	
	influence_map.max_layer_value(
		InfluenceMap.Layer.ENEMY_VULNERABILITY,
		target_hex,
		#shooter_cover
		remap(shooter_cover, 0.0, 5.0, 5.0, 0.0)
	)
	





func _read_los_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback

	var value: Variant = data[key]

	if typeof(value) == TYPE_INT:
		return float(value)

	if typeof(value) == TYPE_FLOAT:
		return value

	return fallback


func _get_unit_firepower(unit: Unit) -> float:
	var firepower: float = 1.0

	#if unit.combat_stats != null:
		#firepower = unit.combat_stats.firepower

	return firepower


func _get_unit_effectiveness(unit: Unit) -> float:
	var effectiveness: float = remap(unit.stress_system.S_eff, 0.0, 100.0, 1.0, 0.0) 
	#if unit.combat_stats != null:
		#effectiveness = unit.combat_stats.combat_effectiveness

	return effectiveness


func _calculate_los_fire_threat(
	enemy_firepower: float,
	enemy_effectiveness: float,
	target_cover: float,
	hindrance: float,
	distance: int
) -> float:
	var threat: float = enemy_firepower * enemy_effectiveness

	var cover_multiplier: float = 1.0 / (1.0 + target_cover * 0.35)
	var hindrance_multiplier: float = 1.0 / (1.0 + hindrance * 0.25)
	var range_multiplier: float = _get_range_threat_multiplier(distance)
	#var range_multiplier: float = 1.0

	threat *= cover_multiplier
	threat *= hindrance_multiplier
	threat *= range_multiplier

	if threat < 0.0:
		threat = 0.0

	return threat


func _get_range_threat_multiplier(distance: int) -> float:
	if distance <= 1:
		return 2.0

	if distance <= 3:
		return 1.3

	if distance <= 6:
		return 1.0

	if distance <= 10:
		return 0.65

	return 0.35


func _write_friendly_support_for_team(influence_map: InfluenceMap, team: int) -> void:
	for unit: Unit in Globals.get_units():
		if not is_instance_valid(unit):
			continue

		if not unit.alive:
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
		
		#influence_map.stamp_radius(
			#InfluenceMap.Layer.FRIENDLY_SUPPORT,
			#unit.current_hex,
			#support_radius,
			#support_value,
			#InfluenceMap.WriteMode.ADD,
			#true
		#)


func _write_known_enemy_positions_for_team(influence_map: InfluenceMap, team: int) -> void:
	var enemy_team: int = Globals.get_enemy_team(team)

	for unit: Unit in Globals.get_units():
		if not is_instance_valid(unit):
			continue

		if not unit.alive:
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
		
		#influence_map.stamp_radius(
			#InfluenceMap.Layer.KNOWN_ENEMY_POSITION,
			#unit.current_hex,
			#2,
			#1.0,
			#InfluenceMap.WriteMode.MAX,
			#true
		#)



func _get_cover_value_for_cell(_cell: Vector2i) -> float:
	# Normalize to 0.0 .. 1.0.
	# 0.0 = no cover
	# 1.0 = excellent cover
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(_cell))
	if terrain_defence_bonus > 0:
		pass
	var terrain_defence_bonus_normalized: float = remap(terrain_defence_bonus, 0.0, 3.0, 0.0, 1.0)
	return terrain_defence_bonus_normalized


func _get_move_cost_for_cell(_cell: Vector2i) -> float:
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(_cell))
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
) -> InfluenceMap.UnitInfluenceGradient:
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
		score += center_gain * target_map.UNIT_INFLUENCE_CENTER_PULL_WEIGHT

		if score > best_score:
			best_score = score
			best_hex = neighbor_hex
			best_value = neighbor_value

	return InfluenceMap.UnitInfluenceGradient.new(
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
		if not _is_valid_living_unit(enemy):
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
) -> Array[InfluenceMap.UnitInfluenceGradient]:
	var result: Array[InfluenceMap.UnitInfluenceGradient] = []

	if not maps_by_team.has(enemy_team):
		return result

	var target_map: InfluenceMap = maps_by_team[enemy_team]
	var enemies: Array[Unit] = Globals.get_units_for_team(target_team)

	for enemy: Unit in enemies:
		if not _is_valid_living_unit(enemy):
			continue

		var gradient: InfluenceMap.UnitInfluenceGradient = _calculate_unit_gradient_to_influence_center(
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
	var sources: Array[ProjectionSource] = _build_projected_line_sources(
		enemy_units,
		config.objective_hex,
		config.projected_line_max_cells,
		config.los_skip_front,
		config.los_count
	)

	for source: ProjectionSource in sources:
		_project_los_from_source(
			influence_map,
			source,
			false
		)


func _create_axis_composite_from_enemy_units(
	source_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	axis_enemy_units: Array[Unit]
) -> PackedFloat32Array:
	var axis_map: InfluenceMap = InfluenceMap.new()
	axis_map.configure(source_map.bounds)

	var weights: PackedFloat32Array = _create_default_weights()

	axis_map.configure_composite_weights(
		weights,
		0.0,
		0.0,
		20.0
	)

	axis_map.set_layer_data_copy(
		InfluenceMap.Layer.TERRAIN_COVER,
		source_map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER)
	)

	axis_map.set_layer_data_copy(
		InfluenceMap.Layer.TERRAIN_MOVE_COST,
		source_map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_MOVE_COST)
	)

	_project_actual_friendly_los(
		axis_map,
		config
	)

	_project_simulated_enemy_los_from_units(
		axis_map,
		config,
		axis_enemy_units
	)

	axis_map.rebuild_all_composite()

	return axis_map.get_composite_data_copy()
