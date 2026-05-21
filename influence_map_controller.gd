class_name InfluenceMapController
extends Node

signal influence_maps_updated()

const REBUILD_CELLS_PER_FRAME: int = 400

var maps_by_team: Dictionary[int, InfluenceMap] = {}

var allied_weights: PackedFloat32Array = PackedFloat32Array()
var axis_weights: PackedFloat32Array = PackedFloat32Array()

var rebuild_pending: bool = false


#func _ready() -> void:
	#create_maps()


func _process(_delta: float) -> void:
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


func create_maps() -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		return

	var bounds: Rect2i = LOSHelper.ground_layer.get_used_rect()

	var allied_map: InfluenceMap = InfluenceMap.new()
	var axis_map: InfluenceMap = InfluenceMap.new()

	allied_map.configure(bounds)
	axis_map.configure(bounds)

	allied_weights = _create_default_weights()
	axis_weights = _create_default_weights()

	allied_map.configure_composite_weights(allied_weights, 1.0, 0.05, 20.0)
	axis_map.configure_composite_weights(axis_weights, 1.0, 0.05, 20.0)

	maps_by_team[Globals.Team.ALLIES] = allied_map
	maps_by_team[Globals.Team.AXIS] = axis_map

	rebuild_pending = true


func _create_default_weights() -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(InfluenceMap.Layer.COUNT)
	weights.fill(0.0)

	# Positive values increase movement cost / danger.
	# Negative values reduce movement cost / attract movement.

	weights[InfluenceMap.Layer.TERRAIN_COVER] = -0.40
	weights[InfluenceMap.Layer.TERRAIN_MOVE_COST] = 1.00
	weights[InfluenceMap.Layer.ENEMY_VISIBILITY] = 2.00
	weights[InfluenceMap.Layer.ENEMY_FIRE_THREAT] = 3.00
	weights[InfluenceMap.Layer.FRIENDLY_SUPPORT] = -0.50
	weights[InfluenceMap.Layer.OBJECTIVE_PRESSURE] = -0.75
	weights[InfluenceMap.Layer.KNOWN_ENEMY_POSITION] = 1.50
	weights[InfluenceMap.Layer.NO_GO] = 20.00

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

		influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.ENEMY_FIRE_THREAT, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.FRIENDLY_SUPPORT, 0.0)
		influence_map.clear_layer(InfluenceMap.Layer.KNOWN_ENEMY_POSITION, 0.0)

		_write_visibility_for_team(influence_map, team)
		_write_fire_threat_for_team(influence_map, team)
		_write_friendly_support_for_team(influence_map, team)
		_write_known_enemy_positions_for_team(influence_map, team)

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
		influence_map.max_layer_value(InfluenceMap.Layer.ENEMY_VISIBILITY, cell, 1.0)


func _write_fire_threat_for_team(influence_map: InfluenceMap, team: int) -> void:
	var enemy_team: int = _get_enemy_team(team)

	for unit: Unit in Globals.get_units():
		if not is_instance_valid(unit):
			continue

		if not unit.alive:
			continue

		if unit.team != enemy_team:
			continue

		var threat_radius: int = 8
		var threat_value: float = _get_unit_threat_value(unit)

		influence_map.stamp_radius(
			InfluenceMap.Layer.ENEMY_FIRE_THREAT,
			unit.current_hex,
			threat_radius,
			threat_value,
			InfluenceMap.WriteMode.ADD,
			true
		)


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
	return 0.0


func _get_move_cost_for_cell(_cell: Vector2i) -> float:
	# 0.0 = normal movement
	# higher = worse movement
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
