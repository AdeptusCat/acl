class_name InfluenceMapController
extends Node

signal influence_maps_updated()

const REBUILD_CELLS_PER_FRAME: int = 400

var maps_by_team: Dictionary[int, InfluenceMap] = {}

var allied_weights: PackedFloat32Array = PackedFloat32Array()
var axis_weights: PackedFloat32Array = PackedFloat32Array()

var rebuild_pending: bool = false

enum CompositeSource {
	SELF,
	ENEMY
}


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
	update_counter += _delta
	if update_counter > update_threshold:
		update_counter = 0.0
		#rebuild_dynamic_tactical_layers()
		create_maps(update_threshold)
	
	if not rebuild_pending:
		return

	var all_done: bool = true

	for team: int in maps_by_team.keys():
		var influence_map: InfluenceMap = maps_by_team[team]
		var done: bool = influence_map.rebuild_dirty_composite_budgeted(REBUILD_CELLS_PER_FRAME)

		if not done:
			all_done = false

	if all_done:
		rebuild_pending = false
		influence_maps_updated.emit()


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

	allied_map.configure_composite_weights(allied_weights, 10.0, 0.00, 20.0)
	axis_map.configure_composite_weights(axis_weights, 10.0, 0.00, 20.0)

	maps_by_team[Globals.Team.ALLIES] = allied_map
	maps_by_team[Globals.Team.AXIS] = axis_map
	
	var origin_hex: Vector2i = Vector2i(11, 3)
	#var allied_map: InfluenceMap = maps_by_team[Globals.Team.ALLIES]
	if allied_map != null:
		allied_map.stamp_origin_influence(origin_hex)
	if allied_map != null:
		allied_map.update_origin_influence_decay(delta)
	if axis_map != null:
		axis_map.stamp_origin_influence(origin_hex)
	if axis_map != null:
		axis_map.update_origin_influence_decay(delta)
	
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

	# Positive values increase movement cost / danger.
	# Negative values reduce movement cost / attract movement.
	
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
	
	# this works quite well for attacker
	weights[InfluenceMap.Layer.TERRAIN_COVER] = -1.00
	weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = -0.50
	weights[InfluenceMap.Layer.THREAT] = 1.0 # this only makes good close hexes undesirable
	##weights[InfluenceMap.Layer.ENEMY_VISIBILITY] = -1.0
	weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = -1.00
	#weights[InfluenceMap.Layer.ORIGIN_INFLUENCE] = -2.00
	
	# this works good for the attacker
	# might also work for defender
	#weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = -0.50
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = -0.50
	
	# this works for defender quite well since it look for strong points to defend
	# attacker is attracted to move back because its safer
	#weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = -0.90
	#weights[InfluenceMap.Layer.THREAT] = 1.5
	#weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = -0.50
	
	
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

		_write_visibility_for_team(influence_map, team)
		rebuild_los_influence_for_team(influence_map, team)
		#_write_friendly_support_for_team(influence_map, team)
		#_write_known_enemy_positions_for_team(influence_map, team)

	rebuild_pending = true


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
	var enemy_team: int = _get_enemy_team(team)
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
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.FIRE_POWER, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.COVER_VS_ENEMY_FIRE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY_HINDRANCE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.RETURN_FIRE_PENALTY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VULNERABILITY, 0.0)
	
	var enemy_team: int = _get_enemy_team(team)
	var units: Array[Unit] = Globals.get_units_for_team(team)
	var enemy_units: Array[Unit] = Globals.get_units_for_team(enemy_team)
	
	var los_lookup: Dictionary = LOSHelper.los_lookup
	for unit: Unit in units:
		if not is_instance_valid(unit):
			continue

		var observer_hex: Vector2i = unit.current_hex

		if not los_lookup.has(observer_hex):
			continue
		
		var visible_targets: Dictionary = los_lookup[observer_hex]
		var unit_firepower: float = _get_unit_firepower(unit)
		var unit_effectiveness: float = _get_unit_effectiveness(unit)

		for target_hex: Vector2i in visible_targets.keys():
			if not influence_map.is_valid_cell(target_hex):
				continue

			var los_data: Dictionary = visible_targets[target_hex]

			_project_friendly_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				unit_firepower,
				unit_effectiveness
			)
	
	for unit: Unit in enemy_units:
		if not is_instance_valid(unit):
			continue

		var observer_hex: Vector2i = unit.current_hex

		if not los_lookup.has(observer_hex):
			continue
		
		var visible_targets: Dictionary = los_lookup[observer_hex]
		var unit_firepower: float = _get_unit_firepower(unit)
		var unit_effectiveness: float = _get_unit_effectiveness(unit)

		for target_hex: Vector2i in visible_targets.keys():
			if not influence_map.is_valid_cell(target_hex):
				continue

			var los_data: Dictionary = visible_targets[target_hex]

			_project_enemy_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				unit_firepower,
				unit_effectiveness
			)


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
	
	var distance: int = _hex_distance(observer_hex, target_hex)
	
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
	
	var distance: int = _hex_distance(observer_hex, target_hex)
	
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
	var effectiveness: float = 1.0

	#if unit.combat_stats != null:
		#effectiveness = unit.combat_stats.combat_effectiveness

	return effectiveness


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var ds: int = -a.x - a.y - (-b.x - b.y)

	var distance: int = (abs(dq) + abs(dr) + abs(ds)) / 2
	return distance


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
			true
		)


func _write_known_enemy_positions_for_team(influence_map: InfluenceMap, team: int) -> void:
	var enemy_team: int = _get_enemy_team(team)

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
			true
		)


func _get_enemy_team(team: int) -> int:
	if team == Globals.Team.ALLIES:
		return Globals.Team.AXIS

	return Globals.Team.ALLIES


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
