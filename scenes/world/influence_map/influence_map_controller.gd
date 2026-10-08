class_name InfluenceMapController
extends Node2D

signal influence_maps_updated()

const REBUILD_CELLS_PER_FRAME: int = 400
const LOS_SOURCES_PER_FRAME: int = 2

enum CompositeSource { SELF, ENEMY }
enum TacticalTask { NONE, DEFEND_OBJECTIVE, ATTACK_OBJECTIVE }
enum KnowledgePolicy { OBSERVED_AND_MEMORY, OMNISCIENT }

@export var knowledge_policy: KnowledgePolicy = KnowledgePolicy.OBSERVED_AND_MEMORY
var maps_by_team: Dictionary[int, InfluenceMap] = {}
var snapshot: InfluenceSnapshot = null
var pending_snapshot: InfluenceSnapshot = null
var objectives_by_team: Dictionary[int, Vector2i] = {}
# Compatibility for legacy debug/test-axis callers. Team mission contexts are authoritative.
var objective_hex: Vector2i = Vector2i.ZERO
var los_rebuild_jobs: Array[LosRebuildJob] = []
var rebuild_pending: bool = false
var maps_initialized: bool = false
var update_counter: float = 0.0
var update_threshold: float = 1.0
var threat_axis_composites_by_team: Dictionary[int, Array] = {}
var center_of_mass: Dictionary[Globals.Team, Vector2i] = {}
var formations: Dictionary[Globals.Team, FormationIdentification] = {}


func _process(delta: float) -> void:
	update_counter += delta
	if update_counter >= update_threshold:
		update_counter = 0.0
		create_maps(delta)
	_process_los_rebuild()
	_process_budgeted_rebuild()


func reset_for_match() -> void:
	los_rebuild_jobs.clear()
	pending_snapshot = null
	snapshot = null
	maps_by_team.clear()
	objectives_by_team.clear()
	threat_axis_composites_by_team.clear()
	rebuild_pending = false
	maps_initialized = false
	update_counter = update_threshold


func set_objective_for_team(team: int, cell: Vector2i) -> void:
	if objectives_by_team.get(team) != cell:
		objectives_by_team[team] = cell
		update_counter = update_threshold


func create_maps(_delta: float) -> void:
	if rebuild_pending or not is_instance_valid(LOSHelper.ground_layer):
		return
	var version: int = 1
	if snapshot != null:
		version = snapshot.version + 1
	pending_snapshot = InfluenceSnapshotBuilder.capture(version, objectives_by_team, knowledge_policy, create_default_weights())
	for team: int in _get_processed_teams():
		var config: InfluenceProjectionConfig = _create_los_config_for_team(team)
		config.contacts = pending_snapshot.get_contacts(team)
		LosInfluenceProjector.begin_budgeted_rebuild_for_team(self, pending_snapshot.maps[team], config)
	rebuild_pending = true


func _process_los_rebuild() -> void:
	LosInfluenceProjector.process_budgeted_rebuild(self, LOS_SOURCES_PER_FRAME)


func _process_budgeted_rebuild() -> void:
	if not rebuild_pending or pending_snapshot == null or not los_rebuild_jobs.is_empty():
		return
	var complete: bool = true
	for map: InfluenceMap in pending_snapshot.maps.values():
		if not map.rebuild_dirty_composite_budgeted(REBUILD_CELLS_PER_FRAME):
			complete = false
	if not complete:
		return
	InfluenceSnapshotBuilder.finish_routes(pending_snapshot)
	# Publish both teams together. Published map arrays are never reused for writes.
	snapshot = pending_snapshot
	pending_snapshot = null
	maps_by_team = snapshot.maps
	rebuild_pending = false
	maps_initialized = true
	_rebuild_threat_axis_composites_for_all_teams()
	influence_maps_updated.emit()


func _get_processed_teams() -> Array[int]:
	return [Globals.Team.ALLIES, Globals.Team.AXIS]


func create_default_weights() -> PackedFloat32Array:
	# Keep the legacy diagnostic composite stable. Position profiles score independently.
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(InfluenceMap.Layer.COUNT)
	weights.fill(0.0)
	weights[InfluenceMap.Layer.TERRAIN_COVER] = 0.10
	weights[InfluenceMap.Layer.COVER_VS_ENEMY_FIRE] = 0.10
	weights[InfluenceMap.Layer.THREAT] = -0.01
	weights[InfluenceMap.Layer.ENEMY_VULNERABILITY] = 0.10
	return weights


func create_axis_defense_config(team: int, objective: Vector2i) -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	config.unit_team = team
	config.enemy_team = Globals.get_enemy_team(team)
	config.task = TacticalTask.DEFEND_OBJECTIVE
	config.objective_hex = objective
	config.knowledge_policy = knowledge_policy
	if snapshot != null:
		config.contacts = snapshot.get_contacts(team)
	return config


func _create_los_config_for_team(team: int) -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = create_axis_defense_config(team, objectives_by_team.get(team, Vector2i.ZERO))
	config.has_objective = objectives_by_team.has(team)
	return config


func get_map_for_team(team: int) -> InfluenceMap:
	return maps_by_team.get(team)


func get_movement_weight(team: int, cell: Vector2i) -> float:
	var map: InfluenceMap = get_map_for_team(team)
	if map == null:
		return 1.0
	return 1.0 + 4.0 * PositionFeatureEvaluator.risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell))


func query_positions(query: PositionQuery) -> PositionResult:
	query.snapshot = snapshot
	return PositionQueryService.query_positions(query)


func analyze_defense_positions_for_threat_axis(team: int, objective: Vector2i, axis: ThreatAxis, units: Array[Unit], reservations: Dictionary, mission: MissionOrder = null, accepted: Dictionary = {}) -> Array[DefensePositionResult]:
	if axis == null or units.is_empty():
		return []
	var config: InfluenceProjectionConfig = _mission_config(team, objective, mission, accepted)
	config.threat_axis = axis
	return DefensePositionAnalyzer.analyze_best_positions_for_threat_axis(self, config, units, axis.enemy_units, reservations)


func analyze_objective_defense_positions(team: int, objective: Vector2i, units: Array[Unit], reservations: Dictionary, mission: MissionOrder = null, accepted: Dictionary = {}) -> Array[DefensePositionResult]:
	return DefensePositionAnalyzer.analyze_objective_defense_positions(self, _mission_config(team, objective, mission, accepted), units, reservations)


func _mission_config(team: int, objective: Vector2i, mission: MissionOrder, accepted: Dictionary) -> InfluenceProjectionConfig:
	var config: InfluenceProjectionConfig = create_axis_defense_config(team, objective)
	config.accepted_positions = accepted
	if mission != null:
		config.sector_cells = mission.sector_cells
		config.fallback_hexes = mission.fallback_hexes
		config.defense_radius = mission.defense_radius
		config.geography = mission.geography
		config.profile = PositionProfile.for_mode(mission.position_mode)
	return config


func get_sorted_threat_axes_for_team(team: int, objective: Vector2i) -> Array[ThreatAxis]:
	var result: Array[ThreatAxis] = []
	if snapshot == null:
		return result
	var groups: Array[Array] = []
	for contact: InfluenceContact in snapshot.get_contacts(team):
		var selected: int = -1
		for index: int in range(groups.size()):
			var seed_contact: InfluenceContact = groups[index][0]
			if LOSHelper.get_hex_distance(seed_contact.hex, contact.hex) <= 3:
				selected = index
				break
		if selected < 0:
			groups.append([contact])
		else:
			groups[selected].append(contact)
	for group: Array in groups:
		var axis: ThreatAxis = ThreatAxis.new()
		var first: InfluenceContact = group[0]
		axis.source_hex = first.hex
		axis.target_hex = objective
		axis.axis_name = "contact_%s" % first.hex
		if is_instance_valid(first.unit):
			axis.axis_name = "contact_%d" % first.unit.get_instance_id()
		axis.axis_type = ThreatAxis.AxisType.SUSPECTED
		axis.confidence = 0.0
		for contact: InfluenceContact in group:
			axis.estimated_enemy_count += 1
			axis.estimated_firepower += contact.firepower * contact.effectiveness
			axis.confidence += contact.confidence
			if is_instance_valid(contact.unit):
				axis.enemy_units.append(contact.unit)
		axis.confidence /= float(group.size())
		axis.proximity_to_objective = 1.0 / (1.0 + float(LOSHelper.get_hex_distance(axis.source_hex, objective)))
		axis.recompute_score()
		result.append(axis)
	result.sort_custom(_sort_threat_axis_by_score_descending)
	return result


func _sort_threat_axis_by_score_descending(a: ThreatAxis, b: ThreatAxis) -> bool:
	if not is_equal_approx(a.score, b.score):
		return a.score > b.score
	return a.axis_name < b.axis_name


func _rebuild_threat_axis_composites_for_all_teams() -> void:
	threat_axis_composites_by_team.clear()
	for team: int in _get_processed_teams():
		var results: Array[ThreatAxisComposite] = []
		if snapshot.objectives.has(team):
			var config: InfluenceProjectionConfig = create_axis_defense_config(team, snapshot.objectives[team])
			for axis: ThreatAxis in get_sorted_threat_axes_for_team(team, snapshot.objectives[team]):
				var result: ThreatAxisComposite = ThreatAxisComposite.new()
				var composite: PackedFloat32Array = LosInfluenceProjector.create_axis_composite_from_enemy_units(maps_by_team[team], config, axis.enemy_units, create_default_weights())
				result.configure(axis, composite)
				results.append(result)
		threat_axis_composites_by_team[team] = results


func get_threat_axis_composites_for_team(team: int) -> Array[ThreatAxisComposite]:
	var result: Array[ThreatAxisComposite] = []
	for item: ThreatAxisComposite in threat_axis_composites_by_team.get(team, []):
		result.append(item)
	return result


func get_threat_axis_composite_for_team(team: int, index: int) -> PackedFloat32Array:
	var results: Array[ThreatAxisComposite] = get_threat_axis_composites_for_team(team)
	if index < 0 or index >= results.size():
		return PackedFloat32Array()
	return results[index].composite


func rebuild_static_terrain_layers() -> void:
	create_maps(0.0)


func rebuild_dynamic_tactical_layers() -> void:
	create_maps(0.0)


func debug_print_layer_state(team: int, layer: int) -> void:
	var map: InfluenceMap = get_map_for_team(team)
	if map != null:
		print("Influence snapshot ", snapshot.version, " team=", team, " layer=", layer, " values=", map.get_layer_data_copy(layer))
