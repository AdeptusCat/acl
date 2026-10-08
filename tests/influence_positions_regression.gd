extends Node

class UnitProbe extends Unit:
	var commanded: Array[int] = []

	func _ready() -> void:
		pass

	func _make_squad() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func order(cmd: Globals.UnitCmd, _parameter: Variant) -> void:
		commanded.append(cmd)


class AudioProbe extends WeaponAudio:
	func _ready() -> void:
		pass


class ActionProbe extends SquadActionController:
	var intent: String = ""

	func give_defend_area_order(hex: Vector2i, _path: Array[Vector3i]) -> void:
		action_order_id += 1
		intent = "defend"
		action_state = SquadActionState.MOVING_TO_POSITION
		unit.movement.target_hex = hex
		unit.movement.is_moving = true

	func give_attack_hex_order(hex: Vector2i, _covered: Array[Vector3i], _exposed: Array[Vector3i]) -> void:
		action_order_id += 1
		intent = "assault"
		action_state = SquadActionState.MOVING_TO_POSITION
		unit.movement.target_hex = hex
		unit.movement.is_moving = true

	func give_hold_order() -> void:
		action_order_id += 1
		intent = "hold"
		action_state = SquadActionState.HOLDING_POSITION
		unit.movement.is_moving = false


var failures: int = 0
var checks: int = 0
var ground: HexagonTileMapLayer
var controller: InfluenceMapController
var own: UnitProbe
var enemy: UnitProbe
var other: UnitProbe


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	ground = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	ground.tile_set.add_source(atlas, 0)
	for y: int in range(7):
		for x: int in range(9):
			ground.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	add_child(ground)
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = null
	Globals.astars.clear()
	ground.astar = AStar2D.new()
	var ids: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		var id: int = ids.size()
		ids[cell] = id
		ground.astar.add_point(id, ground.map_to_local(cell))
	for cell: Vector2i in ids:
		for neighbor: Vector2i in LOSHelper.get_hex_neighbors(cell):
			if ids.has(neighbor):
				ground.astar.connect_points(ids[cell], ids[neighbor])
	Globals.astars[Globals.Team.AXIS] = ground.astar
	Globals.astars[Globals.Team.ALLIES] = ground.astar
	LOSHelper.los_lookup.clear()
	for cell: Vector2i in ids:
		var visible: Dictionary = {}
		for target: Vector2i in ids:
			if cell != target:
				visible[target] = {"target_cover": 0.0, "shooter_cover": 0.0, "hindrance": 0.0}
		LOSHelper.los_lookup[cell] = visible
	own = _unit(Globals.Team.AXIS, Vector2i(2, 3))
	enemy = _unit(Globals.Team.ALLIES, Vector2i(6, 3))
	other = _unit(Globals.Team.AXIS, Vector2i(1, 1))
	other.squad = 2
	Globals.unit_visible_enemies.clear()
	controller = InfluenceMapController.new()
	controller.set_objective_for_team(Globals.Team.AXIS, Vector2i(3, 3))
	controller.set_objective_for_team(Globals.Team.ALLIES, Vector2i(5, 3))
	_publish()
	_test_knowledge()
	_test_publication()
	_test_selection()
	_test_geography()
	_test_ownership_and_reservations()
	_test_legacy_score_parity()
	_test_profiles()
	_test_mirrored_teams()
	_test_axis_diagnostics()
	_test_execution()
	_test_route_and_context()
	_test_route_retention()
	_test_reserve_policy()
	_test_planner_activation()
	_test_position_overlay()
	controller.free()
	own.free()
	enemy.free()
	other.free()
	Globals.astars.clear()
	LOSHelper.ground_layer = null
	ground.free()
	print("Influence positions checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit(team: Globals.Team, hex: Vector2i) -> UnitProbe:
	var instance: Node = load("res://scenes/game/units/unit.tscn").instantiate()
	instance.set_script(UnitProbe)
	var unit: UnitProbe = instance as UnitProbe
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.team = team
	unit.current_hex = hex
	unit.members_alive = 10
	unit.original_size = 10
	unit.get_node("WeaponAudio").set_script(AudioProbe)
	unit.get_node("SquadActionController").free()
	var action: ActionProbe = ActionProbe.new()
	action.name = "SquadActionController"
	action.unit = unit
	unit.add_child(action)
	add_child(unit)
	unit.add_to_group("units")
	unit.movement.unit = unit
	action.movement = unit.movement
	unit.squad_fire.calc.free()
	unit.squad_fire = null
	return unit


func _publish() -> void:
	controller.create_maps(0.0)
	for index: int in range(1000):
		controller._process_los_rebuild()
		controller._process_budgeted_rebuild()
		if not controller.rebuild_pending:
			return
	_check(false, "Budgeted rebuild finishes")


func _query(mode: PositionProfile.Mode = PositionProfile.Mode.DEFEND) -> PositionQuery:
	var query: PositionQuery = PositionQuery.new()
	query.unit = own
	query.team = own.team
	query.snapshot = controller.snapshot
	query.objective_hex = Vector2i(3, 3)
	query.profile = PositionProfile.for_mode(mode)
	query.defense_radius = 3
	return query


func _test_knowledge() -> void:
	var map: InfluenceMap = controller.snapshot.maps[own.team]
	_check(controller.snapshot.get_contacts(own.team).is_empty(), "Unknown enemy produces no contacts")
	_check(is_zero_approx(map.get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex)), "Unknown enemy produces no incoming danger")
	Globals.unit_visible_enemies[own] = [enemy]
	own.remember_enemy(enemy)
	_publish()
	var old_hex: Vector2i = enemy.current_hex
	var memory_hex: Vector2i = old_hex
	enemy.current_hex = Vector2i(8, 6)
	Globals.unit_visible_enemies[own] = []
	_publish()
	var contacts: Array[InfluenceContact] = controller.snapshot.get_contacts(own.team)
	_check(contacts.size() == 1 and contacts[0].hex == memory_hex and not contacts[0].observed, "Memory uses last-known location, not hidden live position")
	own.enemy_memory[enemy as Unit]["last_seen_time"] = -100.0
	_publish()
	_check(controller.snapshot.get_contacts(own.team).is_empty(), "Expired memory contributes no contact")
	enemy.current_hex = old_hex
	Globals.unit_visible_enemies[own] = [enemy]
	_publish()
	_check(controller.snapshot.maps[own.team].get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex) > 0.0, "Actual enemy threat survives short objective projection lines")
	var observed_threat: float = controller.snapshot.maps[own.team].get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex)
	Globals.unit_visible_enemies[own] = []
	own.enemy_memory.clear()
	controller.knowledge_policy = InfluenceMapController.KnowledgePolicy.OMNISCIENT
	_publish()
	_check(is_equal_approx(observed_threat, controller.snapshot.maps[own.team].get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex)), "Explicit omniscient policy captures unobserved units")
	controller.knowledge_policy = InfluenceMapController.KnowledgePolicy.OBSERVED_AND_MEMORY
	_publish()


func _test_publication() -> void:
	var previous: InfluenceSnapshot = controller.snapshot
	var previous_map: InfluenceMap = previous.maps[own.team]
	var old_values: PackedFloat32Array = previous_map.get_composite_data_copy()
	controller.set_objective_for_team(own.team, Vector2i.ZERO)
	controller.create_maps(0.0)
	controller._process_los_rebuild()
	_check(controller.snapshot == previous and controller.get_map_for_team(own.team) == previous_map, "Readers retain completed snapshot during rebuild")
	_check(previous_map.get_composite_data_copy() == old_values, "Published arrays are not reused for writes")
	_publish()
	_check(controller.snapshot.version == previous.version + 1, "Both teams publish one new generation")
	_check(controller.snapshot.objectives[own.team] == Vector2i.ZERO and controller.snapshot.objectives[enemy.team] == Vector2i(5, 3), "Origin objective and independent team contexts are retained")
	controller.set_objective_for_team(own.team, Vector2i(3, 3))
	_publish()


func _test_selection() -> void:
	var query: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var scores: PackedFloat32Array = PackedFloat32Array()
	scores.resize(map.cell_count)
	var invalid: DefensePositionResult = DefensePositionAnalyzer.create_result_from_score_map(map, own, null, "test", scores, 0.8)
	_check(not invalid.is_valid(), "All-zero legacy map returns no candidate")
	scores[0] = 1.0
	var origin: DefensePositionResult = DefensePositionAnalyzer.create_result_from_score_map(map, own, null, "test", scores, 0.8)
	_check(origin.is_valid() and origin.target_hex == Vector2i.ZERO and origin.should_move, "First destination at index zero compares against actual unit position")
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [own.current_hex]
	var feasible_zero: PositionResult = PositionQueryService.query_positions(query)
	_check(feasible_zero.is_valid() and is_zero_approx(feasible_zero.score), "Eligible zero utility is distinct from exclusion")
	_check(feasible_zero.eligibility[feasible_zero.target_index] == 1 and feasible_zero.rejections.has("geography"), "Diagnostics distinguish feasible zero scores from rejected cells")
	query.sector_cells = [Vector2i(-1, 2)]
	_check(not PositionQueryService.query_positions(query).is_valid(), "Absent authored cell is excluded")
	var disabled: Vector2i = Vector2i(3, 3)
	var id: int = query.snapshot.point_ids[own.team][disabled]
	query.snapshot.routes[own.team].set_point_disabled(id, true)
	query.sector_cells = [disabled]
	_check(not PositionQueryService.query_positions(query).is_valid(), "Disabled destination is rejected")
	query.snapshot.routes[own.team].set_point_disabled(id, false)
	var disconnected: Vector2i = Vector2i(8, 6)
	var graph: AStar2D = query.snapshot.routes[own.team]
	id = query.snapshot.point_ids[own.team][disconnected]
	var neighbors: PackedInt64Array = graph.get_point_connections(id)
	for neighbor: int in neighbors:
		graph.disconnect_points(id, neighbor)
	query.sector_cells = [disconnected]
	_check(not PositionQueryService.query_positions(query).is_valid(), "Disconnected destination is rejected")
	for neighbor: int in neighbors:
		graph.connect_points(id, neighbor)
	query.sector_cells = [own.current_hex, Vector2i(3, 3)]
	query.profile.improvement_absolute = 100.0
	query.has_accepted_target = true
	query.accepted_target = own.current_hex
	query.accepted_context = query.context_key()
	var retained: PositionResult = PositionQueryService.query_positions(query)
	_check(retained.target_hex == own.current_hex and retained.status == PositionResult.Status.RETAINED, "Reservation target is the retained destination")
	query.accepted_target = Vector2i(8, 6)
	query.accepted_context = "old objective"
	_check(PositionQueryService.query_positions(query).target_hex != query.accepted_target, "Stale accepted context does not bind a new objective")


func _test_geography() -> void:
	var query: PositionQuery = _query()
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [Vector2i(6, 4)]
	query.defense_radius = 1
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.target_hex == Vector2i(6, 4), "Explicit sector survives outside objective bounding rectangle")
	query.sector_cells = [Vector2i(-2, 0)]
	query.fallback_hexes = [Vector2i(2, 4)]
	_check(PositionQueryService.query_positions(query).target_hex == Vector2i(2, 4), "Fallback geography is queried only when primary has no candidates")
	query.fallback_hexes.clear()
	query.geography = PositionQuery.Geography.OBJECTIVE_RADIUS
	query.objective_hex = Vector2i.ZERO
	query.defense_radius = 0
	_check(PositionQueryService.query_positions(query).target_hex == Vector2i.ZERO, "Objective origin is a valid authored destination")
	var legacy: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
	legacy.geography = PositionQuery.Geography.SECTOR_ONLY
	legacy.sector_cells = [Vector2i(3, 3)]
	legacy.snapshot.maps[own.team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(3, 3), 0.6)
	legacy.snapshot.maps[own.team].rebuild_all_composite()
	var comparison: PositionResult = PositionQueryService.query_positions(legacy)
	_check(is_equal_approx(comparison.score, legacy.snapshot.maps[own.team].get_composite_value(comparison.target_hex)), "Legacy profile matches original objective-center composite before calibration")


func _test_ownership_and_reservations() -> void:
	var config: InfluenceProjectionConfig = controller.create_axis_defense_config(own.team, Vector2i(3, 3))
	var empty: Array[Unit] = []
	var enemies: Array[Unit] = [enemy]
	_check(DefensePositionAnalyzer.analyze_best_positions_for_threat_axis(controller, config, empty, enemies, {}).is_empty(), "Empty explicit axis cannot recruit the whole team")
	var wrong_team: Array[Unit] = [enemy]
	_check(DefensePositionAnalyzer.analyze_objective_defense_positions(controller, config, wrong_team, {}).is_empty(), "Adapter rejects units from another team")
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.set_squads([own])
	var rogue: DefensePositionResult = DefensePositionResult.new()
	rogue.unit = other
	platoon._apply_position_results([rogue], "test", null)
	_check(platoon.squad_assignments.is_empty(), "Platoon rejects advice for a unit it does not own")
	var query: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [Vector2i.ZERO]
	query.reservations[other] = Vector2i.ZERO
	_check(not PositionQueryService.query_positions(query).is_valid(), "Reserved cells are excluded even when their utility is highest")
	query.reservations.clear()
	query.sector_cells = [other.current_hex]
	_check(not PositionQueryService.query_positions(query).is_valid(), "Occupied cells have hard destination capacity")
	var map: InfluenceMap = controller.snapshot.maps[own.team]
	_check(is_zero_approx(map.create_reserved_stamp([Vector2i.ZERO])[0]), "Legacy reservation stamp also enforces capacity")
	platoon.bind_active_squads([own, other, enemy])
	_check(platoon.squads == [own], "Active scenario binding preserves the configured ownership slots")
	platoon.influence_map_controller = controller
	platoon.current_order = MissionOrder.new()
	platoon.current_order.objective_hex = Vector2i(3, 3)
	for index: int in range(4):
		var axis: ThreatAxis = ThreatAxis.new()
		axis.source_hex = enemy.current_hex
		axis.target_hex = platoon.current_order.objective_hex
		axis.axis_name = str(index)
		platoon.current_order.threat_axes.append(axis)
	var other_order: int = other.action_controller.action_order_id
	platoon.reconsider_assignments()
	_check(platoon.squad_assignments.size() == 1 and platoon.squad_assignments.has(own) and other.action_controller.action_order_id == other_order, "More axes than squads cannot overwrite ownership through empty assignments")
	platoon.current_order.position_mode = PositionProfile.Mode.LEGACY_DEFENSE
	platoon.current_order.geography = PositionQuery.Geography.SECTOR_ONLY
	platoon.current_order.sector_cells = [own.current_hex]
	platoon.reconsider_assignments()
	_check(platoon.squad_assignments[own]["target_hex"] == own.current_hex, "Legacy comparison profile keeps defense mission geography through its adapter")
	platoon.executor.cancel_all()
	own.movement.is_moving = false
	platoon.free()


func _test_profiles() -> void:
	var query: PositionQuery = _query()
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	var exposed: Vector2i = Vector2i(3, 3)
	var protected: Vector2i = Vector2i(3, 4)
	query.sector_cells = [exposed, protected]
	var map: InfluenceMap = query.snapshot.maps[own.team]
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, exposed, 0.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, protected, 1.0)
	map.set_layer_value(InfluenceMap.Layer.THREAT, exposed, 2.0)
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.target_hex == protected, "Calibrated defense prefers protection over exposed vulnerability")
	query.has_accepted_target = true
	query.accepted_target = result.target_hex
	query.accepted_context = result.context
	var again: PositionResult = PositionQueryService.query_positions(query)
	_check(again.target_hex == result.target_hex and again.status == PositionResult.Status.RETAINED, "Stable inputs retain the accepted position")
	_check(again.features.has("firing") and again.features.has("route_exposure") and not again.alternatives.is_empty(), "Advice exposes firing, route risk and alternatives")
	map.set_layer_value(InfluenceMap.Layer.THREAT, exposed, 0.0)
	var features: Dictionary = {"cover": 0.0, "incoming": 0.2, "forecast": 0.0, "firing": 0.8, "objective_coverage": 0.5, "support": 0.0, "travel": 0.0, "route_exposure": 0.0, "progress": 0.0}
	own.squad_type = Globals.SquadType.Rifle
	var rifle_score: float = query.profile.score(features, own)
	own.squad_type = Globals.SquadType.MG
	_check(query.profile.score(features, own) > rifle_score, "MG profile values firing lanes more than rifle profile")
	own.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	_check(query.profile.score(features, own) < rifle_score, "HQ profile emphasizes safety instead of firing utility")
	own.squad_type = Globals.SquadType.Rifle
	var offense: PositionQuery = _query(PositionProfile.Mode.SUPPORT_BY_FIRE)
	offense.objective_hex = Vector2i(6, 3)
	var advice: PositionResult = PositionQueryService.query_positions(offense)
	_check(advice.is_valid() and advice.features["firing"] > 0.0, "Support-by-fire finds a reachable firing position")
	offense.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	var advance: PositionResult = PositionQueryService.query_positions(offense)
	_check(advance.is_valid() and advance.features["progress"] > 0.0, "Advance makes positive objective progress")
	offense.profile = PositionProfile.for_mode(PositionProfile.Mode.ASSAULT)
	var assault: PositionResult = PositionQueryService.query_positions(offense)
	_check(assault.is_valid() and LOSHelper.get_hex_distance(assault.target_hex, offense.objective_hex) <= 1, "Assault chooses a position next to the objective")
	own.stress_system.state = STATES.MoraleState.PINNED
	_check(not PositionQueryService.query_positions(offense).is_valid(), "Pinned unit is ineligible for assault")
	own.stress_system.state = STATES.MoraleState.NORMAL
	var fire: SquadFireController = SquadFireController.new()
	own.squad_fire = fire
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.range_hexes = 2
	weapon.ammunition = 0
	var soldier: Soldier = Soldier.new(0, "test", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, own, own.team)
	fire.soldiers = [soldier]
	_check(is_zero_approx(InfluenceUnitQuery.get_unit_firepower(own)), "Empty ammunition contributes no firepower")
	weapon.ammunition = 20
	_check(InfluenceUnitQuery.get_firepower_at_range(own, 3) == 0.0, "Weapon range limits outgoing utility")
	var ammunition: int = weapon.ammunition
	InfluenceUnitQuery.get_unit_firepower(own)
	_check(weapon.ammunition == ammunition, "Capability queries never consume ammunition")
	fire.free()
	own.squad_fire = null


func _test_mirrored_teams() -> void:
	var axis: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
	axis.geography = PositionQuery.Geography.SECTOR_ONLY
	axis.sector_cells = [Vector2i(3, 3)]
	var allies: PositionQuery = PositionQuery.new()
	allies.unit = enemy
	allies.team = enemy.team
	allies.snapshot = controller.snapshot
	allies.objective_hex = Vector2i(5, 3)
	allies.geography = PositionQuery.Geography.SECTOR_ONLY
	allies.sector_cells = [Vector2i(5, 3)]
	allies.profile = PositionProfile.for_mode(PositionProfile.Mode.LEGACY_DEFENSE)
	controller.snapshot.maps[own.team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(3, 3), 0.6)
	controller.snapshot.maps[enemy.team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(5, 3), 0.6)
	for map: InfluenceMap in controller.snapshot.maps.values():
		map.rebuild_all_composite()
	var first: PositionResult = PositionQueryService.query_positions(axis)
	var second: PositionResult = PositionQueryService.query_positions(allies)
	_check(first.is_valid() and second.is_valid() and is_equal_approx(first.score, second.score), "Mirrored teams have matching scores and ownership")


func _test_execution() -> void:
	var query: PositionQuery = _query(PositionProfile.Mode.SUPPORT_BY_FIRE)
	query.objective_hex = Vector2i(6, 3)
	var result: PositionResult = PositionQueryService.query_positions(query)
	var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
	var old_hex: Vector2i = own.current_hex
	if result.target_hex == own.current_hex:
		result.should_move = true
		result.target_hex = Vector2i(3, 3)
		result.path = query.snapshot.get_path(own.team, own.current_hex, result.target_hex)
	_check(executor.execute(result), "Executor accepts a validated route")
	_check(own.action_controller.get("intent") == "defend", "Support fire uses move-and-hold execution")
	own.unit_arrived_at_hex.emit(own.current_hex)
	_check(own.commanded.is_empty(), "Arrival at a stopped waypoint cannot trigger the destination's support intent")
	executor.execute(result)
	own.current_hex = result.target_hex
	own.movement.is_moving = false
	own.unit_arrived_at_hex.emit(own.current_hex)
	_check(own.commanded.has(Globals.UnitCmd.FIRE_AT_HEX), "Support intent begins firing after arrival")
	result.should_move = false
	var order_id: int = own.action_controller.action_order_id
	var commands: int = own.commanded.size()
	executor.execute(result)
	_check(own.action_controller.action_order_id == order_id and own.commanded.size() == commands, "Retained advice does not repeat completed tactical intent")
	result.should_move = true
	own.current_hex = old_hex
	result.path = [own.current_hex, Vector2i(-20, 0)]
	_check(not executor.execute(result), "Executor rejects stale or absent route endpoints")
	result.profile_mode = PositionProfile.Mode.ASSAULT
	result.path = query.snapshot.get_path(own.team, own.current_hex, result.target_hex)
	result.should_move = true
	_check(executor.execute(result) and own.action_controller.get("intent") == "assault", "Assault advice uses the existing attack action")
	executor.cancel_all()
	result.profile_mode = PositionProfile.Mode.ASSAULT
	_check(executor.execute(result, TacticalPositionExecutor.Intent.HOLD) and own.action_controller.get("intent") == "defend", "Execution intent can hold a position supplied by an offensive profile")
	executor.cancel_all()
	own.movement.is_moving = false
	own.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	result.target_hex = own.current_hex
	result.should_move = false
	order_id = own.action_controller.action_order_id
	executor.execute(result, TacticalPositionExecutor.Intent.HOLD)
	_check(own.action_controller.action_order_id == order_id, "Retained defense preserves the existing position-establishment timer")
	executor.cancel_all()
	own.action_controller.action_state = SquadActionController.SquadActionState.NO_ORDER


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _test_route_and_context() -> void:
	var query: PositionQuery = _query()
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [Vector2i(4, 3)]
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var path: Array[Vector2i] = query.snapshot.get_path(own.team, own.current_hex, query.sector_cells[0])
	var dangerous: Vector2i = path[1]
	map.set_layer_value(InfluenceMap.Layer.THREAT, dangerous, 100.0)
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(not advice.is_valid() and advice.rejections.has("risk"), "A dangerous route step is rejected even when the destination is safe")
	map.set_layer_value(InfluenceMap.Layer.THREAT, dangerous, 0.0)
	map.set_layer_value(InfluenceMap.Layer.FORECAST_THREAT, query.sector_cells[0], 100.0)
	query.objective_hex = Vector2i(4, 3)
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and is_zero_approx(advice.features["forecast"]), "Objective changes do not reuse the previous mission forecast")
	map.set_layer_value(InfluenceMap.Layer.FORECAST_THREAT, query.sector_cells[0], 0.0)
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.SUPPORT_BY_FIRE)
	query.objective_hex = Vector2i(6, 3)
	query.movement_radius = 0
	var records: Dictionary = query.snapshot.los[own.current_hex]
	var target_record: Dictionary = records[query.objective_hex]
	records.erase(query.objective_hex)
	advice = PositionQueryService.query_positions(query)
	_check(not advice.is_valid(), "Support-by-fire must see the mission target rather than another contact")
	records[query.objective_hex] = target_record
	own.surrendered = true
	_check(not PositionQueryService.query_positions(query).is_valid(), "Surrendered units receive no position orders")
	own.surrendered = false
	own.stress_system.state = STATES.MoraleState.PANIC
	_check(not PositionQueryService.query_positions(query).is_valid(), "Routing units cannot be redirected by position advice")
	own.stress_system.state = STATES.MoraleState.NORMAL
	var rejected: DefensePositionResult = DefensePositionResult.new()
	rejected.unit = own
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.influence_map_controller = controller
	platoon.set_squads([own])
	platoon._apply_position_results([rejected], "defend", null)
	var order_id: int = own.action_controller.action_order_id
	platoon._issue_orders()
	_check(own.action_controller.action_order_id == order_id, "No-candidate advice never falls back to an unchecked objective order")
	var valid: PositionResult = PositionQueryService.query_positions(_query(PositionProfile.Mode.ADVANCE))
	valid.should_move = true
	_check(platoon.executor.execute(valid), "Planner owns a pending movement action")
	platoon._issue_orders()
	_check(not own.movement.is_moving and platoon.executor.pending.is_empty(), "Losing all candidates stops the planner's pending movement")
	platoon.executor.cancel_all()
	platoon.free()


func _test_legacy_score_parity() -> void:
	var query: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, float((cell.x + cell.y) % 4) / 3.0)
	map.rebuild_all_composite()
	var stamp: InfluenceStamp = map.create_radius_stamp(query.objective_hex, query.defense_radius, 1.0, InfluenceMap.FalloffMode.SQUARE_ROOT)
	var previous_scores: PackedFloat32Array = map.write_stamp_to_layer_with_return(map.get_composite_data_copy(), stamp, InfluenceMap.WriteMode.MULTIPLY, true)
	var result: PositionResult = PositionQueryService.query_positions(query)
	var compared: int = 0
	var max_error: float = 0.0
	for index: int in range(map.cell_count):
		if result.eligibility[index] == 1 and stamp.contains_cell(map.index_to_cell(index)):
			compared += 1
			max_error = maxf(max_error, absf(result.score_map[index] - previous_scores[index]))
	_check(compared >= 10 and max_error < 0.000001, "Shared legacy objective scores match the original stamp pipeline across candidates")
	var draw: InfluenceMapDebugDraw = InfluenceMapDebugDraw.new()
	draw.selected_unit = own
	draw.team = own.team
	own.influence_map = result.score_map
	draw.position_advice = result
	draw.debug_view = InfluenceMapDebugDraw.DebugView.POSITION_SCORE
	_check(is_equal_approx(draw._get_debug_value(map, result.target_hex), result.score), "Position diagnostic displays query utility")
	draw.debug_view = InfluenceMapDebugDraw.DebugView.THREAT
	_check(is_equal_approx(draw._get_debug_value(map, result.target_hex), map.get_layer_value(InfluenceMap.Layer.THREAT, result.target_hex)), "Selecting a unit cannot hide the current-threat diagnostic")
	draw.free()


func _test_axis_diagnostics() -> void:
	var second_enemy: UnitProbe = _unit(Globals.Team.ALLIES, Vector2i(0, 6))
	Globals.unit_visible_enemies[own] = [enemy, second_enemy]
	_publish()
	var composites: Array[ThreatAxisComposite] = controller.get_threat_axis_composites_for_team(own.team)
	_check(composites.size() == 2 and composites[0].composite != composites[1].composite, "Axis diagnostics preserve distinct captured enemy contributions")
	var published: PackedFloat32Array = controller.snapshot.maps[own.team].get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT)
	var alternate: PackedFloat32Array = controller.snapshot.get_forecast_data(own.team, Vector2i.ZERO)
	_check(alternate != published and controller.snapshot.maps[own.team].get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT) == published, "Concurrent objectives receive distinct forecasts without changing published layers")
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	config.unit_team = own.team
	config.knowledge_policy = InfluenceMapController.KnowledgePolicy.OMNISCIENT
	var empty_map: InfluenceMap = InfluenceMap.new()
	empty_map.configure(ground.get_used_rect())
	LosInfluenceProjector.project_actual_enemy_los(empty_map, config)
	_check(is_zero_approx(empty_map.get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex)), "An explicitly empty contact capture cannot resample live enemies")
	Globals.unit_visible_enemies[own] = []
	second_enemy.free()
	_publish()


func _test_route_retention() -> void:
	var query: PositionQuery = _query(PositionProfile.Mode.ADVANCE)
	query.objective_hex = Vector2i(7, 3)
	var advice: PositionResult = PositionQueryService.query_positions(query)
	query.has_accepted_target = true
	query.accepted_target = advice.target_hex
	query.accepted_context = advice.context
	own.movement.path_hexes = advice.path.duplicate()
	own.movement.path_index = 1
	own.movement.target_hex = advice.target_hex
	own.movement.is_moving = true
	var retained: PositionResult = PositionQueryService.query_positions(query)
	_check(not retained.should_move, "An unchanged accepted route continues without restarting movement")
	own.movement.path_hexes = [own.current_hex, Vector2i(0, 6), advice.target_hex]
	retained = PositionQueryService.query_positions(query)
	_check(retained.should_move, "A different accepted route must be replaced with the evaluated route")
	own.movement.is_moving = false
	own.movement.path_hexes.clear()


func _test_reserve_policy() -> void:
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.current_order = MissionOrder.new()
	var own_effectiveness: float = own.combat_stats.combat_effectiveness
	var other_effectiveness: float = other.combat_stats.combat_effectiveness
	own.combat_stats.combat_effectiveness = 0.4
	other.combat_stats.combat_effectiveness = 0.8
	var other_role: Globals.SquadType = other.squad_type
	other.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	var available: Array[Unit] = [own, other]
	_check(platoon._select_reserve_squad(available) == own, "Reserve selection retains the least-effective-squad policy")
	platoon.current_order.reserve_policy = MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE
	_check(platoon._select_reserve_squad(available) == other, "Explicit HQ reserve policy keeps the headquarters near the objective")
	own.combat_stats.combat_effectiveness = own_effectiveness
	other.combat_stats.combat_effectiveness = other_effectiveness
	other.squad_type = other_role
	platoon.free()


func _test_planner_activation() -> void:
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.influence_map_controller = controller
	platoon.set_squads([own])
	platoon.current_order = MissionOrder.new()
	var query: PositionQuery = _query(PositionProfile.Mode.ADVANCE)
	query.objective_hex = Vector2i(4, 3)
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [query.objective_hex]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(platoon.executor.execute(advice) and own.movement.is_moving, "Active planner owns movement before player handoff")
	platoon._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "test")], "test", null)
	platoon.accepted_positions[own] = {"hex": advice.target_hex, "context": advice.context}
	platoon.set_active(false)
	_check(not platoon.active and platoon.current_order == null and platoon.squad_assignments.is_empty() and platoon.accepted_positions.is_empty() and platoon.reserved_hexes_by_squad.is_empty(), "Player handoff clears automatic mission and allocation state")
	_check(not own.movement.is_moving and platoon.executor.pending.is_empty() and platoon.executor.completed.is_empty(), "Player handoff stops owned movement and releases arrival callbacks")
	own.give_hold_order()
	var manual_order_id: int = own.action_controller.action_order_id
	var order: MissionOrder = MissionOrder.new()
	order.objective_hex = own.current_hex
	order.geography = PositionQuery.Geography.SECTOR_ONLY
	order.sector_cells = [own.current_hex]
	platoon.receive_mission_order(order)
	platoon.reconsider_assignments()
	platoon._process(2.0)
	_check(platoon.current_order == null and own.action_controller.action_order_id == manual_order_id, "Disabled planner preserves manual orders through direct updates and ticks")
	platoon.set_active(true)
	platoon.receive_mission_order(order)
	_check(platoon.active and platoon.current_order == order and platoon.squad_assignments.has(own), "Automatic control can resume for a new enemy-side mission")
	_check(platoon.executor.execute(advice), "Reactivated planner can own a new movement")
	own.give_hold_order()
	manual_order_id = own.action_controller.action_order_id
	platoon.set_active(false)
	_check(own.action_controller.action_order_id == manual_order_id and platoon.executor.pending.is_empty(), "Player handoff preserves a manual command replacing an automatic action")
	platoon.free()


func _test_position_overlay() -> void:
	var map: InfluenceMap = controller.snapshot.maps[own.team]
	var advice: PositionResult = PositionResult.new()
	advice.unit = own
	advice.status = PositionResult.Status.ACCEPTED
	advice.score_map.resize(map.cell_count)
	advice.eligibility.resize(map.cell_count)
	var zero_cell: Vector2i = Vector2i(3, 3)
	var negative_cell: Vector2i = Vector2i(4, 3)
	var excluded_cell: Vector2i = Vector2i(5, 3)
	advice.target_hex = zero_cell
	advice.target_index = map.cell_to_index(zero_cell)
	advice.eligibility[map.cell_to_index(zero_cell)] = 1
	advice.eligibility[map.cell_to_index(negative_cell)] = 1
	advice.score_map[map.cell_to_index(negative_cell)] = -2.0
	advice.score_map[map.cell_to_index(excluded_cell)] = 100.0
	var responses: Array[PositionResult] = [advice]
	var draw: InfluenceMapDebugDraw = InfluenceMapDebugDraw.new()
	draw.influence_controller = controller
	draw.tile_map_layer = ground
	draw.team = enemy.team
	draw.debug_view = InfluenceMapDebugDraw.DebugView.THREAT
	draw.position_advice_provider = func(_unit: Unit) -> PositionResult:
		return responses[0]
	draw.refresh_cells()
	var order_id: int = own.action_controller.action_order_id
	var tactical_advice: PositionResult = own.position_advice
	draw.set_selected_unit(own)
	_check(draw.debug_view == InfluenceMapDebugDraw.DebugView.POSITION_SCORE and draw.team == own.team and draw.position_advice == advice, "Selection automatically displays the unit's team and read-only position advice")
	_check(own.action_controller.action_order_id == order_id and own.position_advice == tactical_advice, "Inspection preserves tactical orders and planner-owned advice")
	_check(draw._should_draw_cell(map, zero_cell) and draw._should_draw_cell(map, negative_cell), "Eligible zero and negative scores remain visible candidates")
	_check(not draw._should_draw_cell(map, excluded_cell), "Excluded cells cannot appear as candidates even with positive scores")
	draw._recalculate_value_range(map)
	_check(draw._cached_min_value == -2.0 and draw._cached_max_value == 0.0, "Heatmap scaling uses only eligible candidates")
	var empty: PositionResult = PositionResult.new()
	empty.unit = own
	empty.status = PositionResult.Status.NO_CANDIDATE
	empty.eligibility.resize(map.cell_count)
	empty.reason = "No feasible candidate"
	responses[0] = empty
	draw._on_influence_maps_updated()
	_check(draw.position_advice == empty and not draw._should_draw_cell(map, zero_cell) and draw._layer_access_text.contains("0 candidates"), "Snapshot refresh clears obsolete candidates and explains no-candidate advice")
	responses[0] = advice
	draw._process(1.1)
	_check(draw.position_advice == advice, "Periodic inspection refresh picks up updated planning diagnostics")
	draw.set_debug_view(InfluenceMapDebugDraw.DebugView.THREAT)
	_check(is_equal_approx(draw._get_debug_value(map, own.current_hex), map.get_layer_value(InfluenceMap.Layer.THREAT, own.current_hex)), "Layer shortcuts remain usable while a unit is selected")
	draw.set_debug_view(InfluenceMapDebugDraw.DebugView.POSITION_SCORE)
	draw.set_selected_unit(null)
	_check(draw.selected_unit == null and draw.position_advice == null and draw.debug_view == InfluenceMapDebugDraw.DebugView.THREAT and draw.team == enemy.team, "Deselection restores the previous team layer and clears position advice")
	draw.free()
