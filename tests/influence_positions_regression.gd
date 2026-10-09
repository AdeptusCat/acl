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
	controller.defensive_memory.clear()
	_test_publication()
	_test_selection()
	_test_geography()
	_test_ownership_and_reservations()
	_test_automatic_registration()
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
	_test_defensive_posture()
	_test_defensive_commitment()
	_test_defensive_responsibility()
	_test_crossing_budget()
	_test_defensive_withdrawal()
	_test_defense_mission_context()
	_test_defensive_memory()
	_test_budgeted_position_queries()
	_test_defense_area()
	_test_corridor_evidence()
	_test_objective_connected_defense()
	_test_local_interception()
	_test_complementary_defense()
	_test_loadout_stationary_roles()
	_test_branch_defense()
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
	# These policy probes have no weapon roster; equipment tests attach one explicitly.
	unit.squad_loadout = null
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
	# Low-level policy regressions isolate the original explicit approach contract.
	query.use_defense_area = false
	query.unit = own
	query.team = own.team
	query.snapshot = controller.snapshot
	query.objective_hex = Vector2i(3, 3)
	query.profile = PositionProfile.for_mode(mode)
	# This geometry/acceptance fixture has no buildings. Posture tests use production limits.
	query.profile.minimum_cover = 0.0
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
	# Legacy queries isolate geography; calibrated defense also requires mission responsibility.
	var query: PositionQuery = _query(PositionProfile.Mode.LEGACY_DEFENSE)
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
	_check(platoon.squads == [own, other], "Active scenario binding includes every living squad on the planner's team")
	# Explicit subset ownership remains available to low-level allocation callers.
	platoon.set_squads([own])
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


func _test_automatic_registration() -> void:
	var added: UnitProbe = _unit(own.team, Vector2i(3, 5))
	added.company = Unit.Company.B
	added.platoon = 4
	added.squad = 17
	added.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	var dormant: UnitProbe = _unit(own.team, Vector2i(4, 5))
	var dead: UnitProbe = _unit(own.team, Vector2i(5, 5))
	dead.alive = false
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.current_order = MissionOrder.new()
	planner.set_squads([dormant])
	planner.accepted_positions[dormant] = {"hex": dormant.current_hex, "context": "previous scenario"}
	planner.reserved_hexes_by_squad[dormant] = dormant.current_hex
	var active_units: Array[Unit] = [own, other, added, enemy, own, null, dead]
	planner.bind_active_squads(active_units)
	_check(planner.squads == [own, other, added], "Automatic registration includes extra squads and headquarters regardless of company, platoon or squad slot")
	_check(not planner.squads.has(dormant) and not planner.squads.has(enemy) and not planner.squads.has(dead), "Binding excludes another scenario, the other team, dead units and duplicate references")
	_check(planner.accepted_positions.is_empty() and planner.reserved_hexes_by_squad.is_empty() and not dormant.squad_ai_controller.defensive_mission_controlled, "Replacing a roster releases previous scenario reservations and defensive ownership")
	_check(own.squad_ai_controller.defensive_mission_controlled and added.squad_ai_controller.defensive_mission_controlled, "Every newly registered enemy squad receives defensive movement ownership")
	var query: PositionQuery = _defense_fixture()
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	query.objective_hex = Vector2i(4, 3)
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [query.objective_hex]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(planner.executor.execute(advice) and own.movement.is_moving, "The previous roster owns a movement before rebinding")
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "test")], "test", null)
	planner.bind_active_squads([added, enemy])
	_check(planner.squads == [added] and planner.squad_assignments.is_empty() and planner.executor.pending.is_empty() and not own.movement.is_moving, "Rebinding cancels obsolete squad orders and assignments before publishing the new roster")
	_check(not own.squad_ai_controller.defensive_mission_controlled and not other.squad_ai_controller.defensive_mission_controlled, "Units removed from the active roster no longer belong to defensive planning")
	var player_planner: PlatoonAI = PlatoonAI.new()
	player_planner.team = enemy.team
	player_planner.set_active(false)
	enemy.give_hold_order()
	var player_order: int = enemy.action_controller.action_order_id
	player_planner.bind_active_squads(active_units)
	player_planner.receive_mission_order(MissionOrder.new())
	_check(player_planner.squads == [enemy] and player_planner.current_order == null and not enemy.squad_ai_controller.defensive_mission_controlled and enemy.action_controller.action_order_id == player_order, "Automatic player-team registration preserves manual orders and never enables an AI mission")
	planner.bind_active_squads([])
	_check(planner.squads.is_empty() and not added.squad_ai_controller.defensive_mission_controlled, "A scenario with no matching team units clears the previous roster")
	planner.free()
	player_planner.free()
	added.free()
	dormant.free()
	dead.free()
	_publish()


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


func _equip(unit: Unit, weapons: Array[WeaponSpec]) -> void:
	var fire: SquadFireController = SquadFireController.new()
	unit.squad_fire = fire
	unit.squad_loadout = SquadLoadoutSpec.new()
	for index: int in range(weapons.size()):
		var definition: SoldierLoadout = SoldierLoadout.new()
		definition.weapon = weapons[index]
		unit.squad_loadout.soldiers.append(definition)
		fire.soldiers.append(Soldier.new(index, "Equipment probe", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapons[index].create_runtime(), unit, unit.team))


func _planned_role(planner: PlatoonAI, unit: Unit) -> String:
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == unit:
			return request["role"]
	return ""


func _test_loadout_stationary_roles() -> void:
	var fixture: PositionQuery = _defense_fixture()
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		var tripod_weapon: WeaponSpec = load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec
		var bipod_weapon: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
		var rifle_weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
		if team == Globals.Team.ALLIES:
			tripod_weapon = load("res://resources/weapons/m1919a4.tres") as WeaponSpec
			bipod_weapon = load("res://resources/weapons/m1918a1_bar.tres") as WeaponSpec
			rifle_weapon = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
		var rifle: UnitProbe = _unit(team, Vector2i(4, 2))
		var bipod: UnitProbe = _unit(team, Vector2i(4, 4))
		var tripod: UnitProbe = _unit(team, Vector2i(5, 2))
		var spare: UnitProbe = _unit(team, Vector2i(5, 4))
		_equip(rifle, [rifle_weapon, rifle_weapon])
		_equip(bipod, [bipod_weapon, rifle_weapon])
		_equip(tripod, [tripod_weapon, rifle_weapon])
		_equip(spare, [tripod_weapon, rifle_weapon])
		# Misleading squad labels cannot outweigh the weapons actually carried.
		rifle.squad_type = Globals.SquadType.MG
		tripod.squad_type = Globals.SquadType.Rifle
		_check(InfluenceUnitQuery.get_defensive_mount(tripod) == WeaponSpec.Mount.TRIPOD and InfluenceUnitQuery.get_defensive_mount(bipod) == WeaponSpec.Mount.BIPOD and InfluenceUnitQuery.get_defensive_mount(rifle) == WeaponSpec.Mount.NONE, "Runtime loadouts distinguish tripod, bipod and rifle-only squads for either team")
		_check(tripod.squad_fire.soldiers[0].weapon.mount == tripod_weapon.mount, "Weapon runtime copies retain their authored mount")
		_check(DefenseSectorAllocator.select_guard([rifle, bipod, tripod]) == tripod and DefenseSectorAllocator.select_guard([tripod, bipod, rifle]) == tripod, "A tripod MG anchors objective defense independently of squad labels or list order")
		_check(DefenseSectorAllocator.select_guard([rifle, bipod]) == bipod, "A mixed rifle squad carrying a bipod MG is more stationary than rifle-only infantry")
		tripod.squad_fire.soldiers[0].jammed = true
		tripod.squad_fire.soldiers[0].rounds_in_mag = 0
		_check(DefenseSectorAllocator.select_guard([rifle, tripod]) == tripod, "A temporary jam or reload does not exchange the objective guard and flanking squad")
		tripod.squad_fire.soldiers[0].jammed = false
		tripod.combat_stats.combat_effectiveness = 0.3
		_check(DefenseSectorAllocator.select_guard([rifle, tripod]) == rifle, "An ineffective MG does not monopolize the guard role over healthy infantry")
		tripod.combat_stats.combat_effectiveness = rifle.combat_stats.combat_effectiveness
		var area: DefenseAreaAssessment = DefenseAreaAssessment.new()
		area.objective_hex = Vector2i(3, 3)
		area.max_priority = 1.0
		var response: Dictionary = {}
		for unit: Unit in [rifle, bipod, tripod, spare]:
			response[unit.current_hex] = 0.0
		area.approaches = [{"id": 0, "priority": 1.0, "response_distances": response}]
		var planner: PlatoonAI = PlatoonAI.new()
		planner.team = team
		planner.influence_map_controller = controller
		planner.current_order = MissionOrder.new()
		planner.current_order.objective_hex = area.objective_hex
		planner.defense_area = area
		planner._planning_snapshot = fixture.snapshot
		planner._build_sector_requests([rifle, tripod])
		_check(_planned_role(planner, tripod) == "guard_objective" and _planned_role(planner, rifle) == "defend_sector", "One rifle and one tripod MG keep the MG guarding and the rifle covering the approach")
		_check(planner._planning_requests[0]["query"].defense_responsibility == PositionQuery.Responsibility.GUARD and planner._planning_requests[1]["query"].defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH, "Loadout-based roles become explicit guard and approach responsibilities")
		planner._planning_requests.clear()
		planner._build_sector_requests([rifle, tripod, spare])
		_check(_planned_role(planner, tripod) == "guard_objective" and _planned_role(planner, spare) == "defend_sector" and _planned_role(planner, rifle) == "reserve", "A spare tripod MG can defend forward after the stationary anchor is retained")
		planner._planning_requests.clear()
		planner._build_sector_requests([tripod, rifle, bipod])
		_check(_planned_role(planner, tripod) == "guard_objective" and _planned_role(planner, rifle) == "reserve" and _planned_role(planner, bipod) == "defend_sector", "Reserve selection cannot consume the only tripod MG and prefers mobile infantry at equal effectiveness")
		planner.current_order.reserve_policy = MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE
		tripod.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
		planner._planning_requests.clear()
		planner._build_sector_requests([tripod, rifle, bipod])
		_check(_planned_role(planner, tripod) == "reserve" and _planned_role(planner, bipod) == "guard_objective", "An explicit HQ reserve instruction overrides automatic equipment-based guard selection")
		tripod.squad_type = Globals.SquadType.Rifle
		planner.current_order.reserve_policy = MissionOrder.ReservePolicy.KEEP_ONE_SQUAD_IF_POSSIBLE
		area.approaches.append({"id": 3, "priority": 1.0, "response_distances": response})
		planner._planning_requests.clear()
		planner._build_sector_requests([rifle, tripod, spare])
		_check(_planned_role(planner, tripod) == "guard_objective" and _planned_role(planner, rifle) == "defend_sector" and _planned_role(planner, spare) == "defend_sector", "A second significant front deploys the mobile reserve without moving the MG anchor into that role")
		area.approaches[1]["priority"] = 1.4
		var assignments: Dictionary[Unit, int] = DefenseSectorAllocator.assign(area, [spare], {spare: {"sector": 0}})
		_check(assignments[spare as Unit] == 0, "An established spare tripod team retains its firing sector through a moderate priority fluctuation")
		area.approaches[1]["priority"] = 2.0
		assignments = DefenseSectorAllocator.assign(area, [spare], {spare: {"sector": 0}})
		_check(assignments[spare as Unit] == 3, "A substantially stronger flank can still retask a spare stationary MG")
		planner.defense_area = null
		planner.current_order.reserve_policy = MissionOrder.ReservePolicy.NONE
		planner._planning_requests.clear()
		planner._build_planning_requests([rifle, tripod])
		_check(_planned_role(planner, tripod) == "guard_objective", "The defense adapter without an area assessment uses the same loadout guard allocation")
		var base: PositionProfile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
		var rifle_profile: PositionProfile = PositionProfile.for_unit(base, rifle)
		var bipod_profile: PositionProfile = PositionProfile.for_unit(base, bipod)
		var tripod_profile: PositionProfile = PositionProfile.for_unit(base, tripod)
		_check(rifle_profile.commitment_seconds == 8.0 and bipod_profile.commitment_seconds == 12.0 and tripod_profile.commitment_seconds == 16.0, "Position commitment increases from rifle to bipod to tripod loadouts")
		_check(rifle_profile.travel_weight < bipod_profile.travel_weight and bipod_profile.travel_weight < tripod_profile.travel_weight and bipod_profile.improvement_absolute < tripod_profile.improvement_absolute, "Stationary weapons require greater relocation benefit and pay a greater travel cost")
		_check(base.commitment_seconds == 8.0 and base.travel_weight == rifle_profile.travel_weight, "Per-squad defensive profiles do not mutate a shared mission profile")
		_check(PositionProfile.for_unit(tripod_profile, tripod).commitment_seconds == tripod_profile.commitment_seconds and PositionProfile.for_unit(tripod_profile, rifle).commitment_seconds == rifle_profile.commitment_seconds, "Reusing a calibrated profile neither compounds stationarity nor transfers it to rifle-only infantry")
		_check(tripod_profile.max_exposure_seconds == base.max_exposure_seconds and tripod_profile.max_open_exposure_seconds == base.max_open_exposure_seconds, "Stationary roles preserve the existing safe crossing budgets")
		var offense: PositionProfile = PositionProfile.for_mode(PositionProfile.Mode.SUPPORT_BY_FIRE)
		_check(PositionProfile.for_unit(offense, tripod) == offense, "Defensive stationarity does not alter an offensive profile")
		_test_mount_commitment([rifle, bipod, tripod], fixture.snapshot)
		var equipment_config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
		var armed_query: PositionQuery = DefensePositionAnalyzer.make_query(equipment_config, tripod, {})
		tripod.squad_fire.soldiers[0].is_alive = false
		_check(InfluenceUnitQuery.get_defensive_mount(tripod) == WeaponSpec.Mount.NONE and DefenseSectorAllocator.select_guard([tripod, bipod]) == bipod, "A lost runtime tripod weapon releases its stationary role despite the original loadout")
		var depleted_query: PositionQuery = DefensePositionAnalyzer.make_query(equipment_config, tripod, {})
		_check(armed_query.context_key() != depleted_query.context_key(), "Losing a stationary weapon invalidates accepted-position and inspection context")
		tripod.squad_fire.soldiers[1].weapon = tripod_weapon.create_runtime()
		_check(InfluenceUnitQuery.get_defensive_mount(tripod) == WeaponSpec.Mount.TRIPOD, "A support weapon transferred to a living soldier retains its stationary role")
		var runtime: SquadFireController = tripod.squad_fire
		tripod.squad_fire = null
		_check(InfluenceUnitQuery.get_defensive_mount(tripod) == WeaponSpec.Mount.TRIPOD, "A squad without a runtime roster can classify its authored loadout")
		tripod.squad_fire = runtime
		planner.free()
		for unit: Unit in [rifle, bipod, tripod, spare]:
			unit.squad_fire.free()
			unit.squad_fire = null
			unit.free()


func _test_mount_commitment(units: Array[Unit], snapshot: InfluenceSnapshot) -> void:
	var map: InfluenceMap = snapshot.maps[units[0].team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
		map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
	snapshot.defensive_contacts[units[0].team] = []
	var initial_time: float = snapshot.captured_at
	for unit: Unit in units:
		var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
		config.unit_team = unit.team
		config.objective_hex = unit.current_hex
		config.geography = PositionQuery.Geography.SECTOR_ONLY
		var better: Vector2i = unit.current_hex + Vector2i(1, 0)
		config.sector_cells = [unit.current_hex, better]
		config.profile.cover_weight = 4.0
		var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, {})
		query.snapshot = snapshot
		query.use_defense_area = false
		query.has_accepted_target = true
		query.accepted_target = unit.current_hex
		query.accepted_context = query.context_key()
		query.accepted_at = initial_time
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, unit.current_hex, 1.0 / 3.0)
		snapshot.captured_at = initial_time + 9.0
		var advice: PositionResult = PositionQueryService.query_positions(query)
		if InfluenceUnitQuery.get_defensive_mount(unit) == WeaponSpec.Mount.NONE:
			_check(advice.is_valid() and advice.target_hex == better, "A rifle-only squad can redeploy after its shorter commitment")
		else:
			_check(advice.is_valid() and advice.target_hex == unit.current_hex, "An MG retains its safe accepted firing position after the rifle commitment expires")
		snapshot.captured_at = initial_time + query.profile.commitment_seconds + 1.0
		_check(PositionQueryService.query_positions(query).target_hex == better, "An MG can still relocate for a material improvement after its loadout commitment")
		snapshot.captured_at = initial_time + 1.0
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, unit.current_hex, 0.0)
		_check(PositionQueryService.query_positions(query).target_hex == better, "Losing required defensive cover overrides even a stationary weapon's commitment")
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, unit.current_hex, 1.0)
	snapshot.captured_at = initial_time


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
	own.in_close_combat = true
	var locked_order_id: int = own.action_controller.action_order_id
	_check(not PositionQueryService.query_positions(query).is_valid(), "Engaged squad cannot receive a new position recommendation")
	_check(not executor.execute(result) and own.action_controller.action_order_id == locked_order_id, "Combat entry invalidates cached movement advice before execution")
	own.in_close_combat = false
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
	_check(not advice.is_valid() or not advice.path.has(dangerous), "A dangerous route step is avoided even when the destination is safe")
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
	controller.defensive_memory.clear()
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


func _test_defensive_posture() -> void:
	Globals.unit_visible_enemies[own] = []
	own.enemy_memory.clear()
	_publish()
	var map: InfluenceMap = controller.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
	var query: PositionQuery = _query()
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = [Vector2i(3, 3)]
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, query.sector_cells[0], 0.0)
	_check(not PositionQueryService.query_positions(query).is_valid(), "An open objective hex is not an eligible defensive position even without known enemies")
	query.sector_cells = [Vector2i(4, 3)]
	var path: Array[Vector2i] = query.snapshot.get_path(own.team, own.current_hex, query.sector_cells[0])
	var open_step: Vector2i = path[1]
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, open_step, 0.0)
	map.set_layer_value(InfluenceMap.Layer.THREAT, open_step, 100.0)
	var graph: AStar2D = query.snapshot.routes[own.team]
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, not path.has(ground.local_to_map(graph.get_point_position(id))))
	_check(not PositionQueryService.query_positions(query).is_valid(), "Catastrophic transit danger remains excluded even toward a strong destination")
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, false)
	var safer: PositionResult = PositionQueryService.query_positions(query)
	_check(safer.is_valid() and not safer.path.has(open_step), "Defense finds a covered detour when the shortest route is exposed")
	map.set_layer_value(InfluenceMap.Layer.THREAT, open_step, 0.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, open_step, 1.0)
	var axis: ThreatAxis = ThreatAxis.new()
	axis.axis_name = "visible_contact"
	query.axis = axis
	var context: String = query.context_key()
	query.axis = null
	_check(query.context_key() == context, "Losing an approach axis does not discard defensive position commitment")
	query.has_accepted_target = true
	query.accepted_target = query.sector_cells[0]
	query.accepted_context = query.context_key()
	var step_id: int = query.snapshot.point_ids[own.team][path[1]]
	graph.set_point_disabled(step_id, true)
	var detour: Array[Vector2i] = query.snapshot.get_path(own.team, own.current_hex, query.accepted_target)
	graph.set_point_disabled(step_id, false)
	own.movement.path_hexes = detour
	own.movement.path_index = 1
	own.movement.target_hex = query.accepted_target
	own.movement.is_moving = true
	var retained: PositionResult = PositionQueryService.query_positions(query)
	_check(not detour.is_empty() and not retained.should_move and retained.path == detour, "An existing safe route survives a cheaper alternate route becoming available")
	own.movement.is_moving = false
	own.movement.path_hexes.clear()
	query.has_accepted_target = false
	var enemy_power: float = enemy.firepower
	var enemy_hex: Vector2i = enemy.current_hex
	enemy.firepower = 1.0
	Globals.unit_visible_enemies[own] = [enemy]
	own.remember_enemy(enemy)
	_publish()
	query.snapshot = controller.snapshot
	map = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
	query.sector_cells = [Vector2i(5, 3)]
	var adjacent: PositionResult = PositionQueryService.query_positions(query)
	_check(adjacent.is_valid() and adjacent.features["contact_distance"] == 1, "A covered defensive position adjacent to a known enemy is eligible")
	_check(adjacent.features.get("contact_pressure", 0.0) > 0.0, "Enemy proximity contributes contextual pressure rather than exclusion")
	Globals.unit_visible_enemies[own] = []
	own.enemy_memory.clear()
	enemy.current_hex = Vector2i(8, 6)
	_publish()
	query.snapshot = controller.snapshot
	map = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
	var remembered: PositionResult = PositionQueryService.query_positions(query)
	_check(remembered.is_valid() and remembered.target_hex == adjacent.target_hex and remembered.features["contact_distance"] == 1, "Losing sight preserves captured danger without an artificial adjacent-hex ban")
	enemy.firepower = enemy_power
	enemy.current_hex = enemy_hex


func _test_defensive_commitment() -> void:
	controller.defensive_memory.clear()
	_publish()
	var query: PositionQuery = _query()
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	query.profile.cover_weight = 4.0
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.objective_hex = own.current_hex
	var better: Vector2i = Vector2i(3, 4)
	query.sector_cells = [own.current_hex, better]
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, own.current_hex, 1.0 / 3.0)
	query.has_accepted_target = true
	query.accepted_target = own.current_hex
	query.accepted_context = query.context_key()
	query.accepted_at = query.snapshot.captured_at
	var initial_time: float = query.snapshot.captured_at
	_check(PositionQueryService.query_positions(query).target_hex == own.current_hex, "A safe accepted position ignores score fluctuations during its commitment interval")
	query.snapshot.captured_at += 9.0
	_check(PositionQueryService.query_positions(query).target_hex == better, "A materially better covered position is available after commitment expires")
	query.snapshot.captured_at = initial_time
	map.set_layer_value(InfluenceMap.Layer.THREAT, own.current_hex, 100.0)
	var under_fire: PositionResult = PositionQueryService.query_positions(query)
	_check(under_fire.target_hex == own.current_hex and under_fire.decision == PositionResult.Decision.HOLD_DEFENSE, "A healthy covered defender holds its responsibility under pressure")
	var effectiveness: float = own.combat_stats.combat_effectiveness
	own.combat_stats.combat_effectiveness = 0.3
	_check(PositionQueryService.query_positions(query).target_hex == better, "A weakened defender can withdraw to a covered mission position during commitment")
	own.combat_stats.combat_effectiveness = effectiveness
	map.set_layer_value(InfluenceMap.Layer.THREAT, own.current_hex, 0.0)
	query.objective_hex = better
	_check(PositionQueryService.query_positions(query).target_hex == better, "A changed objective invalidates the old defensive commitment")
	query.objective_hex = own.current_hex
	query.accepted_at = -INF
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, own.current_hex, 1.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, better, 1.0)
	query.objective_hex = better
	query.accepted_context = query.context_key()
	query.defense_radius = 10
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	query.accepted_context = query.context_key()
	_check(PositionQueryService.query_positions(query).target_hex == own.current_hex, "A small coverage improvement cannot trigger repeated defensive shuffling")


func _defense_fixture() -> PositionQuery:
	Globals.unit_visible_enemies[own] = []
	own.enemy_memory.clear()
	controller.defensive_memory.clear()
	_publish()
	var query: PositionQuery = _query()
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
		map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
	own.position = ground.map_to_local(own.current_hex)
	return query


func _add_defense_contact(query: PositionQuery) -> void:
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = Vector2i(6, 3)
	contact.firepower = 0.15
	contact.weapon_range = 6
	contact.observed = true
	query.snapshot.defensive_contacts[own.team] = [contact]


func _test_defensive_responsibility() -> void:
	var query: PositionQuery = _defense_fixture()
	_add_defense_contact(query)
	query.objective_hex = own.current_hex
	var front: Vector2i = Vector2i(4, 3)
	var rear: Vector2i = Vector2i(0, 3)
	query.sector_cells = [front, rear]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == front and advice.features["interposition"] > 0.0 and advice.features["blocking"] >= 0.5, "Defense prefers a covered interception position between enemy and objective")
	var rear_los: Dictionary = query.snapshot.los[rear].duplicate()
	query.snapshot.los[rear] = {Vector2i(0, 4): {"target_cover": 1.0, "hindrance": 0.0}}
	query.sector_cells = [rear]
	advice = PositionQueryService.query_positions(query)
	_check(not advice.is_valid() and advice.rejections.has("responsibility"), "Safe rear cover that cannot protect the objective or approach is excluded")
	query.snapshot.los[rear] = rear_los
	query.sector_cells = [front, query.objective_hex]
	query.defense_responsibility = PositionQuery.Responsibility.OCCUPY
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == query.objective_hex and advice.features["responsibility"] == "occupy", "An explicit occupation responsibility cannot be traded for a nearby firing position")
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.sector_cells = [front]
	_check(PositionQueryService.query_positions(query).features.get("responsibility") == "cover_approach", "An approach-cover responsibility uses usable fire over the incoming route")
	var blocked: Vector2i = Vector2i(5, 3)
	var contact_los: Dictionary = query.snapshot.los[Vector2i(6, 3)].duplicate()
	query.sector_cells = [blocked]
	advice = PositionQueryService.query_positions(query)
	query.snapshot.los[Vector2i(6, 3)].erase(blocked)
	var through_wall: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and through_wall.is_valid() and advice.features["contact_pressure"] > through_wall.features["contact_pressure"], "A wall removes contact pressure without imposing a proximity exclusion")
	query.snapshot.los[Vector2i(6, 3)] = contact_los
	query.defense_responsibility = PositionQuery.Responsibility.AUTO
	query.sector_cells = [own.current_hex, rear]
	advice = PositionQueryService.query_positions(query)
	_check(advice.target_hex == own.current_hex and advice.decision == PositionResult.Decision.HOLD_DEFENSE, "A healthy covered objective defender does not retreat merely because an enemy is visible")
	var origin: Vector2i = own.current_hex
	own.current_hex = front
	own.position = ground.map_to_local(front)
	query.snapshot.positions[own as Unit] = front
	query.snapshot.defensive_contacts[own.team][0].hex = Vector2i(3, 3)
	query.sector_cells = [front, query.objective_hex]
	query.has_accepted_target = true
	query.accepted_target = front
	query.accepted_context = query.context_key()
	var intercept: PositionResult = PositionQueryService.query_positions(query)
	_check(intercept.is_valid() and intercept.target_hex == query.objective_hex, "A passed screen can reposition to intercept between the enemy and objective despite pressure")
	own.current_hex = origin
	own.position = ground.map_to_local(origin)
	query.snapshot.positions[own as Unit] = origin


func _test_crossing_budget() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(4, 3)
	query.sector_cells = [query.objective_hex]
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var open: Vector2i = Vector2i(3, 3)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, open, 0.0)
	map.set_layer_value(InfluenceMap.Layer.THREAT, open, 1.0)
	var graph: AStar2D = query.snapshot.routes[own.team]
	var path: Array[Vector2i] = [own.current_hex, open, query.objective_hex]
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, not path.has(ground.local_to_map(graph.get_point_position(id))))
	var speed: float = own.movement.move_speed
	own.movement.move_speed = 30.0
	var short_crossing: PositionResult = PositionQueryService.query_positions(query)
	_check(short_crossing.is_valid() and short_crossing.features["open_fire"] > 0.15 and short_crossing.features["open_exposure_seconds"] <= query.profile.max_open_exposure_seconds, "A short necessary exposed crossing fits the mission exposure budget")
	query.snapshot.los[own.current_hex][open]["wall_cover"] = 1.0
	_check(not PositionQueryService.query_positions(query).is_valid(), "A wall delays the same exposed crossing enough to exceed its mission budget")
	query.snapshot.los[own.current_hex][open].erase("wall_cover")
	own.movement.move_speed = 10.0
	_check(not PositionQueryService.query_positions(query).is_valid(), "The same route is rejected when slow movement exceeds its exposure budget")
	own.movement.move_speed = 30.0
	query.objective_hex = Vector2i(5, 3)
	query.sector_cells = [query.objective_hex]
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(4, 3), 0.0)
	map.set_layer_value(InfluenceMap.Layer.THREAT, Vector2i(4, 3), 1.0)
	path = [own.current_hex, open, Vector2i(4, 3), query.objective_hex]
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, not path.has(ground.local_to_map(graph.get_point_position(id))))
	_check(not PositionQueryService.query_positions(query).is_valid(), "Exposure accumulates across multiple individually acceptable open steps")
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, false)
	var detour: PositionResult = PositionQueryService.query_positions(query)
	_check(detour.is_valid() and detour.features["open_exposure_seconds"] <= query.profile.max_open_exposure_seconds and detour.path != path, "Weighted flood retains a feasible detour when the direct crossing exhausts its budget")
	query.objective_hex = Vector2i(6, 3)
	query.sector_cells = [query.objective_hex]
	path = [own.current_hex, open, Vector2i(4, 3), Vector2i(5, 3), query.objective_hex]
	for cell: Vector2i in path:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
		if cell != own.current_hex and cell != query.objective_hex:
			map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 20.0)
	for id: int in graph.get_point_ids():
		graph.set_point_disabled(id, not path.has(ground.local_to_map(graph.get_point_position(id))))
	_check(not PositionQueryService.query_positions(query).is_valid(), "Long covered transit is also rejected when accumulated fire exposure exceeds the budget")
	own.movement.move_speed = speed


func _test_defensive_withdrawal() -> void:
	var query: PositionQuery = _defense_fixture()
	_add_defense_contact(query)
	query.objective_hex = own.current_hex
	var retreat: Vector2i = Vector2i(2, 4)
	query.sector_cells = [retreat]
	var retreat_los: Dictionary = query.snapshot.los[retreat].duplicate()
	query.snapshot.los[retreat] = {query.objective_hex: {"target_cover": 1.0, "hindrance": 0.0}}
	var effectiveness: float = own.combat_stats.combat_effectiveness
	var other_effectiveness: float = other.combat_stats.combat_effectiveness
	own.combat_stats.combat_effectiveness = 0.3
	other.combat_stats.combat_effectiveness = 0.2
	var gap: PositionResult = PositionQueryService.query_positions(query)
	_check(not gap.is_valid() and gap.rejections.has("screen_gap"), "The sole established defender cannot withdraw and leave its approach uncovered")
	other.combat_stats.combat_effectiveness = 0.8
	var covered: PositionResult = PositionQueryService.query_positions(query)
	_check(covered.is_valid() and covered.decision == PositionResult.Decision.WITHDRAW and covered.features["preserves_screen"], "A weakened defender can withdraw after another established squad covers its approach")
	var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
	_check(executor.execute(covered) and executor.pending[own as Unit]["intent"] == TacticalPositionExecutor.Intent.WITHDRAW, "Explicit withdrawal advice dispatches through existing order execution")
	executor.cancel_all(true)
	var other_action: int = other.action_controller.action_state
	other.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	_check(not PositionQueryService.query_positions(query).is_valid(), "A squad still establishing its position cannot provide a completed covering handoff")
	other.action_controller.action_state = other_action
	query.reservations[other] = other.current_hex + Vector2i(1, 0)
	_check(not PositionQueryService.query_positions(query).is_valid(), "Another squad's planned departure cannot provide a covering handoff in the same allocation")
	other.movement.is_moving = true
	query.reservations[other] = other.current_hex
	_check(not PositionQueryService.query_positions(query).is_valid(), "A moving squad or future reservation cannot serve as a completed covering handoff")
	other.movement.is_moving = false
	query.snapshot.los[retreat] = retreat_los
	var same_screen: PositionResult = PositionQueryService.query_positions(query)
	_check(same_screen.is_valid() and same_screen.decision == PositionResult.Decision.WITHDRAW, "Retreat is permitted when the withdrawing squad still covers the incoming route")
	query.sector_cells = [own.current_hex, retreat]
	query.snapshot.maps[own.team].set_layer_value(InfluenceMap.Layer.THREAT, own.current_hex, 4.0)
	var safer: PositionResult = PositionQueryService.query_positions(query)
	_check(safer.is_valid() and safer.target_hex == retreat and safer.decision == PositionResult.Decision.WITHDRAW, "A weakened defender chooses a safer covered withdrawal over its exposed current position")
	own.combat_stats.combat_effectiveness = effectiveness
	query.withdrawal_requested = true
	var requested: PositionResult = PositionQueryService.query_positions(query)
	_check(requested.is_valid() and requested.target_hex == retreat and requested.decision == PositionResult.Decision.WITHDRAW, "An explicitly requested withdrawal can move a healthy unit while retaining objective protection")
	query.withdrawal_requested = false
	own.combat_stats.combat_effectiveness = 0.3
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.influence_map_controller = controller
	platoon.set_squads([own])
	var mission: MissionOrder = MissionOrder.new()
	mission.objective_hex = query.objective_hex
	platoon.receive_mission_order(mission)
	var action_order: int = own.action_controller.action_order_id
	var commands: int = own.commanded.size()
	own.squad_ai_controller._decision_tick()
	_check(own.squad_ai_controller.defensive_mission_controlled and own.action_controller.action_order_id == action_order and own.commanded.size() == commands, "Local squad AI cannot override mission-controlled withdrawal with an unconstrained retreat")
	platoon.set_active(false)
	_check(not own.squad_ai_controller.defensive_mission_controlled, "Player handoff releases defensive mission control")
	platoon.free()
	own.combat_stats.combat_effectiveness = effectiveness
	other.combat_stats.combat_effectiveness = other_effectiveness


func _test_defense_mission_context() -> void:
	var query: PositionQuery = _defense_fixture()
	query.sector_cells = [own.current_hex]
	var old_context: String = query.context_key()
	query.defense_responsibility = PositionQuery.Responsibility.OCCUPY
	_check(query.context_key() != old_context, "Changing defensive responsibility invalidates the old position commitment")
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.influence_map_controller = controller
	platoon.set_squads([own])
	var director: DefenseDirector = DefenseDirector.new()
	director.platoon_ai = platoon
	director.objective_source = DefenseDirector.ObjectiveSource.OPPONENT_CAPTURE_TARGET
	var previous: Dictionary[Globals.Team, ObjectivesCollection] = Globals.objectives.duplicate()
	var targets: ObjectivesCollection = ObjectivesCollection.new()
	var objective: ObjectiveDefinition = ObjectiveDefinition.new()
	objective.objective_id = 1
	objective.hex = Vector2i(4, 3)
	targets.objectives.append(objective)
	Globals.objectives[enemy.team] = targets
	director.configure_for_match([own])
	_check(director.objective_hex == objective.hex, "Defender resolves the opponent's actual capture marker rather than its starting anchor")
	director.exposure_budget_seconds = 3.0
	director.open_crossing_budget_seconds = 0.75
	director.defense_responsibility = PositionQuery.Responsibility.GUARD
	var mission: MissionOrder = director.create_initial_order()
	var config: InfluenceProjectionConfig = controller._mission_config(own.team, objective.hex, mission, {})
	_check(config.defense_responsibility == PositionQuery.Responsibility.GUARD and config.profile.max_exposure_seconds == 3.0 and config.profile.max_open_exposure_seconds == 0.75, "Explicit mission responsibility and exposure budgets reach the position pipeline")
	mission.execution_intent = TacticalPositionExecutor.Intent.WITHDRAW
	_check(controller._mission_config(own.team, objective.hex, mission, {}).withdrawal_requested, "Explicit withdrawal intent reaches position advice separately from execution")
	Globals.objectives.erase(enemy.team)
	director.configure_for_match([own])
	_check(director.objective_hex == own.current_hex, "A side without an opponent capture target retains an explicit platoon-anchor fallback")
	Globals.objectives = previous
	controller.set_objective_for_team(own.team, Vector2i(3, 3))
	director.free()
	platoon.free()


func _test_budgeted_position_queries() -> void:
	var query: PositionQuery = _defense_fixture()
	_add_defense_contact(query)
	query.sector_cells = [own.current_hex, Vector2i(4, 3), Vector2i(5, 3)]
	var expected: PositionResult = PositionQueryService.query_positions(query)
	var job: PositionQueryJob = PositionQueryJob.new()
	job.query = query
	job.advance(Time.get_ticks_usec() - 1)
	_check(not job.completed and job.phase == PositionQueryJob.Phase.AREA, "An exhausted frame budget does not begin expensive query work")
	var slices: int = 0
	while not job.completed and slices < 10000:
		job.advance(Time.get_ticks_usec() + 100)
		slices += 1
	_check(job.completed and slices > 1 and job.result.target_hex == expected.target_hex and job.result.path == expected.path and job.result.eligibility == expected.eligibility and job.result.score_map == expected.score_map, "Incremental queries preserve synchronous positions, paths, scores and eligibility")
	_check(query.route_field._query == null, "Completed fields release their query reference instead of retaining a reference cycle")
	var field: PositionRouteField = PositionRouteField.new()
	field.start(query, [own.current_hex])
	field.advance(-1)
	_check(field.completed and field.expanded_labels == 0 and field.path_to(own.current_hex) == [own.current_hex], "A flood stops as soon as its requested destinations settle")
	field.release_query()
	query.profile.max_exposure_seconds = 0.0
	field.start(query, [own.current_hex, Vector2i(4, 3)])
	field.expanded_labels = 256
	field.advance(-1)
	_check(field.completed and field._bounds_prepared and field.path_to(own.current_hex) == [own.current_hex] and field.path_to(Vector2i(4, 3)).is_empty(), "Minimum-exposure pruning excludes impossible destinations while retaining a valid hold")
	field.release_query()
	field.start(query, [Vector2i(4, 3)])
	field.expanded_labels = 256
	field.advance(-1)
	_check(field.completed and field.path_to(Vector2i(4, 3)).is_empty(), "A search completes safely when every requested destination exceeds the exposure lower bound")
	field.release_query()
	var canceled: PositionQueryJob = controller.enqueue_position_query(_defense_fixture())
	controller.cancel_position_query(canceled)
	_check(canceled.canceled and not controller.position_jobs.has(canceled), "Canceled advice is removed from the scheduler")
	var platoon: PlatoonAI = PlatoonAI.new()
	platoon.influence_map_controller = controller
	platoon.set_squads([own])
	var mission: MissionOrder = MissionOrder.new()
	mission.objective_hex = own.current_hex
	platoon.receive_mission_order(mission)
	platoon._start_plan(true)
	_finish_area_plan(platoon)
	var pending: PositionQueryJob = platoon._planning_job
	platoon.set_active(false)
	_check(pending != null and pending.canceled and platoon._planning_job == null and controller.position_jobs.is_empty(), "Player handoff cancels queued planning without publishing stale orders")
	platoon.set_active(true)
	platoon.receive_mission_order(mission)
	platoon._start_plan(true)
	_finish_area_plan(platoon)
	pending = platoon._planning_job
	mission.objective_hex += Vector2i(1, 0)
	platoon._continue_budgeted_plan()
	_check(pending.canceled and platoon._planning_job == null, "An objective change cancels the old budgeted plan")
	platoon._start_plan(true)
	_finish_area_plan(platoon)
	pending = platoon._planning_job
	while not pending.completed:
		controller._process_position_queries()
	var origin: Vector2i = own.current_hex
	var order_id: int = own.action_controller.action_order_id
	own.current_hex += Vector2i(1, 0)
	platoon._continue_budgeted_plan()
	_check(pending.canceled and platoon._planning_job == null and own.action_controller.action_order_id == order_id, "Moving off the query origin discards completed advice without issuing a stale route")
	own.current_hex = origin
	platoon.free()
	add_child(controller)
	var preview: PositionQuery = _defense_fixture()
	preview.geography = PositionQuery.Geography.OBJECTIVE_OR_SECTOR
	_check(controller.query_inspection_positions(preview) == null and controller.position_jobs.size() == 1, "Live player inspection queues work instead of blocking selection")
	controller.query_inspection_positions(_query())
	_check(controller.position_jobs.size() == 1, "Repeated overlay refreshes reuse the pending query")
	while not controller.position_jobs.is_empty():
		controller._process_position_queries()
	var completed_preview: PositionResult = controller.query_inspection_positions(_query())
	_check(completed_preview != null and controller.position_jobs.is_empty(), "Completed player inspection reuses its published result")
	_publish()
	var retained_preview: PositionResult = controller.query_inspection_positions(_query())
	var pending_preview: PositionResult = controller.query_inspection_positions(_query())
	_check(retained_preview == completed_preview and pending_preview == completed_preview and controller.position_jobs.size() == 1, "A new snapshot keeps the last completed overlay visible throughout queued work")
	controller.clear_inspection_queries()
	_check(controller.position_jobs.is_empty() and controller.inspection_results.is_empty(), "Deselection releases pending inspection and its cached results")
	remove_child(controller)


func _finish_area_plan(platoon: PlatoonAI) -> void:
	if platoon._area_job != null:
		platoon._area_job.advance(-1)
		platoon._process(0.0)


func _area_contact(hex: Vector2i, capture_time: float, observed: bool = true) -> InfluenceContact:
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = hex
	contact.firepower = 0.01
	contact.weapon_range = 6
	contact.observed = observed
	contact.last_seen_at = capture_time
	contact.crossing_seconds = 2.0
	return contact


func _test_defense_area() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(4, 3)
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var west: Vector2i = Vector2i(2, 3)
	var east: Vector2i = Vector2i(5, 3)
	var interior: Vector2i = Vector2i(3, 3)
	var original_role: Globals.SquadType = own.squad_type
	own.squad_type = Globals.SquadType.MG
	# Woods use the same building-layer cover custom data as the authored maps.
	var woods: HexagonTileMapLayer = HexagonTileMapLayer.new()
	woods.tile_set = ground.tile_set.duplicate(true)
	woods.tile_set.add_custom_data_layer()
	woods.tile_set.set_custom_data_layer_name(0, "cover")
	woods.tile_set.set_custom_data_layer_type(0, TYPE_INT)
	var atlas: TileSetAtlasSource = woods.tile_set.get_source(0) as TileSetAtlasSource
	atlas.get_tile_data(Vector2i.ZERO, 0).set_custom_data("cover", 3)
	for cell: Vector2i in map.playable_cells:
		var wooded: bool = cell.x >= 2 and cell.x <= 5 and cell.y >= 2 and cell.y <= 4
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, float(wooded))
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, float(wooded))
		if wooded:
			woods.set_cell(cell, 0, Vector2i.ZERO)
	add_child(woods)
	LOSHelper.building_layer = woods
	var capture: InfluenceSnapshot = InfluenceSnapshotBuilder.capture(88, {}, 0, controller.create_default_weights())
	_check(capture.maps[own.team].get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, west) == 1.0 and capture.maps[own.team].get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(0, 3)) == 0.0, "Building-layer woods supply defensive cover while adjacent fields stay open")
	LOSHelper.building_layer = null
	woods.free()
	query.snapshot.terrain_key = 888
	query.snapshot.defense_geometry_cache = {}
	query.snapshot.los = query.snapshot.los.duplicate(true)
	query.snapshot.los[west] = {}
	query.snapshot.los[east] = {}
	query.snapshot.los[interior] = {}
	for cell: Vector2i in map.playable_cells:
		var record: Dictionary = {"target_cover": map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), "hindrance": 0.0}
		if cell.x <= 4:
			query.snapshot.los[west][cell] = record
		if cell.x >= 4:
			query.snapshot.los[east][cell] = record
		if cell.x >= 2 and cell.x <= 5:
			query.snapshot.los[interior][cell] = record
	query.snapshot.captured_at = 100.0
	query.snapshot.defensive_contacts[own.team] = [_area_contact(Vector2i(0, 3), 100.0)]
	var area_job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 4, 7)
	area_job.advance(Time.get_ticks_usec() - 1)
	_check(not area_job.completed and area_job.phase == DefenseAreaJob.Phase.GEOMETRY, "Area work respects an exhausted frame budget")
	var slices: int = 0
	while not area_job.completed and slices < 10000:
		area_job.advance(Time.get_ticks_usec() + 100)
		slices += 1
	query.defense_area = area_job.result
	query.assigned_sector = query.defense_area.sector_at(Vector2i(0, 3))
	query.sector_cells = [west, east, interior]
	query.reservations = {}
	_check(area_job.completed and slices > 1 and area_job.snapshot == null, "Area assessment resumes across slices and releases its captured snapshot")
	_check(query.defense_area.edge_positions.has(west) and query.defense_area.edge_positions.has(east) and not query.defense_area.edge_positions.has(interior), "Terrain assessment identifies woodland boundaries rather than treating all covered hexes alike")
	var approach: Dictionary = query.defense_area.approach_for_sector(query.assigned_sector)
	_check(approach["cells"].size() > 3 and approach["cells"].has(Vector2i(1, 2)), "Approach corridors include competitive route alternatives rather than one shortest path")
	_check(approach["weights"][Vector2i(1, 3)] > approach["weights"][interior], "Exposed crossing time makes open approach cells valuable to cover")
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == west and advice.features["interdiction"] > 0.0, "An MG selects the woodland edge covering the western crossing instead of hugging the objective")
	_check(advice.approach_cells.has(Vector2i(1, 3)) and advice.eligibility[map.cell_to_index(Vector2i(1, 3))] == 0 and advice.sector_priorities.has(query.assigned_sector), "Diagnostics distinguish exposed approach corridors from covered position candidates")
	query.reset_evaluation()
	var edge_value: float = query.defense_area.features(query, west)["interdiction"]
	var interior_value: float = query.defense_area.features(query, interior)["interdiction"]
	_check(edge_value > interior_value, "Long open firing lanes outrank concealed woodland interior without those lanes")
	var guard_role: Globals.SquadType = other.squad_type
	other.squad_type = Globals.SquadType.Rifle
	_check(DefenseSectorAllocator.select_guard([own, other]) == own, "A squad label alone does not exclude it from objective guard duty")
	var armed_power: int = own.firepower
	own.firepower = 0
	_check(DefenseSectorAllocator.select_guard([own, other]) == own, "Temporary firing availability does not rotate the objective guard")
	own.firepower = armed_power
	var original_context: String = query.context_key()
	query.has_accepted_target = true
	query.accepted_target = west
	query.accepted_context = original_context
	query.accepted_at = 100.0
	map.set_layer_value(InfluenceMap.Layer.THREAT, west, 1.0)
	# A fresh confirmed eastern attack outranks an old western hazard without erasing it.
	query.snapshot.captured_at = 140.0
	query.snapshot.defensive_contacts[own.team] = [_area_contact(Vector2i(0, 3), 100.0, false), _area_contact(Vector2i(8, 3), 140.0)]
	var shifted: DefenseAreaJob = DefenseAreaJob.new()
	shifted.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	_check(shifted.phase == DefenseAreaJob.Phase.SOURCES, "Changing intelligence reuses the objective and terrain assessment")
	shifted.advance(-1)
	query.defense_area = shifted.result
	query.assigned_sector = query.defense_area.sector_at(Vector2i(8, 3))
	_check(query.context_key() != original_context, "A changed coverage responsibility invalidates commitment to the old axis")
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == east and advice.should_move and advice.features["assigned_coverage"] >= 0.5, "A healthy pressured defender repositions to cover a newly urgent eastern approach")
	_check(query.snapshot.get_defensive_contacts(own.team).size() == 2, "Reprioritizing the old axis does not erase its known movement danger")
	query.has_accepted_target = true
	query.accepted_target = east
	query.accepted_context = advice.context
	query.accepted_at = 140.0
	var repeated: PositionResult = PositionQueryService.query_positions(query)
	_check(repeated.target_hex == east, "Unchanged sector pressure preserves the selected defensive position")
	query.relocation_allowed = false
	query.has_accepted_target = false
	advice = PositionQueryService.query_positions(query)
	_check(not advice.is_valid() and advice.rejections.has("handoff_wait"), "A second redeployment waits for established covering fire")
	query.relocation_allowed = true
	var handoff: PlatoonAI = PlatoonAI.new()
	own.movement.is_moving = true
	other.movement.is_moving = false
	handoff._reset_relocation([own, other])
	query.relocation_allowed = handoff._can_relocate(own)
	query.has_accepted_target = true
	query.accepted_target = west
	query.accepted_context = original_context
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == east and not handoff._can_relocate(other), "A defender already moving can redirect to cover after an axis change while another relocation waits")
	own.movement.is_moving = false
	query.has_accepted_target = false
	handoff.free()
	var reverse_query: PositionQuery = PositionQuery.new()
	reverse_query.unit = enemy
	reverse_query.team = enemy.team
	reverse_query.objective_hex = query.objective_hex
	reverse_query.snapshot = query.snapshot
	reverse_query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	reverse_query.geography = PositionQuery.Geography.SECTOR_ONLY
	reverse_query.sector_cells = [west, east, interior]
	for cell: Vector2i in map.playable_cells:
		reverse_query.snapshot.maps[enemy.team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell))
		reverse_query.snapshot.maps[enemy.team].set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell))
	reverse_query.snapshot.defensive_contacts[enemy.team] = [_area_contact(Vector2i(8, 3), 140.0)]
	var reverse_job: DefenseAreaJob = reverse_query.snapshot.defense_area_job(enemy.team, query.objective_hex, 4, 7)
	reverse_job.advance(-1)
	reverse_query.defense_area = reverse_job.result
	reverse_query.assigned_sector = query.assigned_sector
	var mirrored: PositionResult = PositionQueryService.query_positions(reverse_query)
	_check(mirrored.is_valid() and mirrored.target_hex == east, "The same terrain and approach responsibility work for either team")
	_check(reverse_job.result.geometry["return_open_costs"] == shifted.result.geometry["return_open_costs"], "Objective return geography is identical for mirrored teams")
	var assignments: Dictionary[Unit, int] = DefenseSectorAllocator.assign(query.defense_area, [own, other], {})
	_check(assignments[own as Unit] == query.assigned_sector, "The strongest firing role receives the dominant current approach")
	query.snapshot.defensive_contacts[own.team] = [_area_contact(Vector2i(0, 3), 140.0), _area_contact(Vector2i(8, 3), 140.0)]
	var balanced: DefenseAreaJob = DefenseAreaJob.new()
	balanced.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	balanced.advance(-1)
	var west_sector: int = balanced.result.sector_at(Vector2i(0, 3))
	var east_sector: int = balanced.result.sector_at(Vector2i(8, 3))
	assignments = DefenseSectorAllocator.assign(balanced.result, [own], {own: {"sector": west_sector}})
	_check(assignments[own as Unit] == west_sector, "Minor pressure differences retain the existing sector assignment")
	query.defense_area = balanced.result
	query.reserve_position = true
	query.assigned_sector = -1
	query.defense_responsibility = PositionQuery.Responsibility.AUTO
	query.reset_evaluation()
	var center_readiness: float = query.defense_area.features(query, interior)["reserve_readiness"]
	var west_readiness: float = query.defense_area.features(query, west)["reserve_readiness"]
	var east_readiness: float = query.defense_area.features(query, east)["reserve_readiness"]
	_check(center_readiness > west_readiness and center_readiness > east_readiness, "A mobile reserve values response to both fronts rather than hugging one firing edge")
	var third: UnitProbe = _unit(own.team, Vector2i(6, 5))
	third.squad_type = Globals.SquadType.Rifle
	var planner: PlatoonAI = PlatoonAI.new()
	planner.influence_map_controller = controller
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = query.objective_hex
	planner.defense_area = balanced.result
	planner._planning_snapshot = query.snapshot
	planner._build_sector_requests([own, other, third])
	var guard_count: int = 0
	var reserve_count: int = 0
	var tasked: Array[int] = []
	for request: Dictionary in planner._planning_requests:
		if request["role"] == "guard_objective":
			guard_count += 1
		if request["role"] == "reserve":
			reserve_count += 1
		var planned: PositionQuery = request["query"]
		if planned.assigned_sector >= 0:
			tasked.append(planned.assigned_sector)
	_check(guard_count == 1 and reserve_count == 0 and tasked.has(west_sector) and tasked.has(east_sector), "Two significant fronts mobilize the reserve while retaining an objective guard")
	planner._planning_requests.clear()
	planner.defense_area = shifted.result
	planner._build_sector_requests([own, other, third])
	reserve_count = 0
	for request: Dictionary in planner._planning_requests:
		if request["role"] == "reserve":
			reserve_count += 1
			_check(request["query"].reserve_position and request["query"].defense_responsibility == PositionQuery.Responsibility.AUTO, "An unneeded reserve receives readiness advice rather than another forced guard duty")
	_check(reserve_count == 1, "A single significant front retains the mobile reserve")
	planner._planning_requests.clear()
	planner.current_order.defense_responsibility = PositionQuery.Responsibility.GUARD
	planner._build_sector_requests([own, other])
	var explicit_guards: bool = planner._planning_requests.size() == 2
	for request: Dictionary in planner._planning_requests:
		explicit_guards = explicit_guards and request["query"].assigned_sector == -1 and request["query"].defense_responsibility == PositionQuery.Responsibility.GUARD
	_check(explicit_guards, "An explicit objective guard mission does not acquire an unrelated sector coverage duty")
	planner.free()
	third.free()
	balanced.result.approach_for_sector(east_sector)["priority"] = balanced.result.approach_for_sector(west_sector)["priority"] * 2.0
	assignments = DefenseSectorAllocator.assign(balanced.result, [own], {own: {"sector": west_sector}})
	_check(assignments[own as Unit] == east_sector, "A substantial priority change overrides sector assignment hysteresis")
	var moved_objective: DefenseAreaJob = query.snapshot.defense_area_job(own.team, Vector2i(3, 2), 4, 7)
	moved_objective.advance(-1)
	_check(moved_objective.result.objective_hex == Vector2i(3, 2) and moved_objective.result.geometry["objective_distances"][Vector2i(3, 2)] == 0.0, "A changed objective receives a distinct reverse travel field")
	query.use_defense_area = true
	query.reserve_position = false
	query.area_job = balanced
	query.objective_hex = Vector2i(3, 2)
	query.assigned_sector = -1
	PositionQueryService.query_positions(query)
	_check(query.defense_area.objective_hex == query.objective_hex, "Reusing a query after an objective change replaces its stale assessment")
	query.objective_hex = own.current_hex
	query.sector_cells = [own.current_hex]
	query.defense_responsibility = PositionQuery.Responsibility.AUTO
	query.assigned_sector = east_sector
	query.profile.max_incoming_risk = 0.0
	map.set_layer_value(InfluenceMap.Layer.THREAT, own.current_hex, 10.0)
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == own.current_hex and advice.decision == PositionResult.Decision.HOLD_DEFENSE, "A lone healthy capture guard holds the covered objective even when its distant firing corridor is incomplete")
	own.squad_type = original_role
	other.squad_type = guard_role


func _test_corridor_evidence() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(4, 3)
	query.use_defense_area = true
	query.snapshot.captured_at = 100.0
	var fresh: Vector2i = Vector2i(8, 6)
	var sector: int = DefenseAreaAssessment.sector_for(query.objective_hex, fresh)
	var stale: Vector2i = fresh
	for cell: Vector2i in query.snapshot.maps[own.team].playable_cells:
		if cell != query.objective_hex and DefenseAreaAssessment.sector_for(query.objective_hex, cell) == sector and LOSHelper.get_hex_distance(cell, query.objective_hex) < LOSHelper.get_hex_distance(stale, query.objective_hex):
			stale = cell
	var stale_enemy: UnitProbe = _unit(enemy.team, stale)
	var stale_contact: InfluenceContact = _area_contact(stale, 20.0, false)
	stale_contact.unit = stale_enemy
	query.snapshot.defensive_contacts[own.team] = [stale_contact, _area_contact(fresh, 100.0)]
	var job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 4, 7)
	job.advance(-1)
	var approach: Dictionary = job.result.approach_for_sector(sector)
	_check(stale != fresh and approach["source"] == fresh and approach["evidence"] == "observed", "Fresh observed pressure anchors a sector corridor rather than its nearest stale contact")
	var passes_objective: bool = false
	for cell: Vector2i in approach["cells"]:
		passes_objective = passes_objective or approach["distances"][cell] > approach["distances"][query.objective_hex]
	_check(not passes_objective, "An approach corridor does not include branches beyond arrival at the objective")
	query.defense_area = job.result
	query.sector_cells = [own.current_hex]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(not advice.approach_cells.is_empty() and advice.inferred_approach_cells.is_empty() and advice.approach_sources[sector] == fresh, "Inspection shows the important observed approach without speculative opposite-sector corridors")
	query.snapshot.defensive_contacts[own.team] = [_area_contact(fresh, 95.0, false)]
	job = DefenseAreaJob.new()
	job.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	job.advance(-1)
	query.defense_area = job.result
	advice = PositionQueryService.query_positions(query)
	_check(advice.approach_cells.is_empty() and not advice.remembered_approach_cells.is_empty() and advice.approach_evidence[sector] == "remembered", "Last-seen approaches remain useful but have distinct inspection evidence")
	query.snapshot.captured_at = 1000.0
	job = DefenseAreaJob.new()
	job.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	job.advance(-1)
	query.defense_area = job.result
	advice = PositionQueryService.query_positions(query)
	_check(not advice.remembered_approach_cells.is_empty() and advice.inferred_approach_cells.is_empty() and DefenseSectorAllocator.priorities(job.result)[0]["id"] == sector, "Aging confirmed knowledge cannot make a speculative opposite approach the dominant duty")
	query.snapshot.captured_at = 100.0
	query.snapshot.defensive_contacts[own.team] = []
	job = DefenseAreaJob.new()
	job.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	job.advance(-1)
	query.defense_area = job.result
	advice = PositionQueryService.query_positions(query)
	_check(advice.approach_cells.is_empty() and advice.remembered_approach_cells.is_empty() and not advice.inferred_approach_cells.is_empty(), "Terrain-only approach estimates never appear as observed enemy corridors")
	var adapted: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, null, "test")
	_check(adapted.inferred_approach_cells == advice.inferred_approach_cells and adapted.approach_evidence == advice.approach_evidence, "Defense adapters preserve approach evidence diagnostics")
	query.snapshot.defensive_contacts[own.team] = [_area_contact(LOSHelper.get_hex_neighbors(query.objective_hex)[0], 100.0)]
	job = DefenseAreaJob.new()
	job.start(query.snapshot, own.team, query.objective_hex, 4, 7, [])
	job.advance(-1)
	approach = job.result.approach_for_sector(job.result.sector_at(query.snapshot.get_defensive_contacts(own.team)[0].hex))
	var excluded_branches: int = 0
	var branch_in_corridor: bool = false
	for cell: Vector2i in query.snapshot.maps[own.team].playable_cells:
		var source_cost: float = approach["distances"].get(cell, INF)
		var best: float = approach["distances"][query.objective_hex]
		var detour: float = source_cost + job.result.geometry["objective_distances"].get(cell, INF) - best
		if source_cost > best and detour <= 2.5:
			excluded_branches += 1
			branch_in_corridor = branch_in_corridor or approach["cells"].has(cell)
	_check(excluded_branches > 0 and not branch_in_corridor, "A close attacker cannot generate the former cheap corridor branches behind the objective")
	stale_enemy.free()


func _test_objective_connected_defense() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(3, 3)
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var local: Vector2i = Vector2i(4, 3)
	var detached: Vector2i = Vector2i(7, 3)
	var role: Globals.SquadType = own.squad_type
	own.squad_type = Globals.SquadType.MG
	for cell: Vector2i in map.playable_cells:
		var wooded: bool = cell.x >= 2 and cell.x <= 4 and cell.y >= 2 and cell.y <= 4
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, float(wooded or cell == detached))
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, 0.0)
	query.snapshot.captured_at = 100.0
	query.snapshot.defensive_contacts[own.team] = [_area_contact(Vector2i(8, 6), 100.0)]
	var job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 5, 8)
	job.advance(-1)
	query.defense_area = job.result
	query.assigned_sector = job.result.sector_at(Vector2i(8, 6))
	query.sector_cells = [local, detached]
	var approach: Dictionary = job.result.approach_for_sector(query.assigned_sector)
	approach["arrival_seconds"] = INF
	# Both woods positions fulfil the duty; the detached one has a somewhat wider firing lane.
	var total: float = 0.0
	for cell: Vector2i in approach["cells"]:
		total += approach["weights"][cell]
	var supplied: float = 0.0
	query.snapshot.los = query.snapshot.los.duplicate(true)
	query.snapshot.los[local] = {}
	query.snapshot.los[detached] = {}
	for cell: Vector2i in approach["cells"]:
		var record: Dictionary = {"target_cover": map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), "hindrance": 0.0}
		query.snapshot.los[detached][cell] = record
		if supplied < total * 0.7:
			query.snapshot.los[local][cell] = record
			supplied += approach["weights"][cell]
	query.profile.cover_weight = 0.0
	query.profile.incoming_weight = 0.0
	query.profile.forecast_weight = 0.0
	query.profile.support_weight = 0.0
	query.profile.travel_weight = 0.0
	query.profile.exposure_weight = 0.0
	query.profile.open_ground_weight = 0.0
	query.profile.proximity_weight = 0.0
	query.profile.area_interposition_weight = 0.0
	query.profile.area_objective_weight = 0.0
	query.profile.area_blocking_weight = 0.0
	query.profile.open_crossing_time_weight = 0.0
	query.profile.objective_return_open_weight = 0.0
	query.profile.connected_cover_improvement_absolute = 0.0
	query.profile.connected_cover_improvement_relative = 0.0
	var outward_only: PositionResult = PositionQueryService.query_positions(query)
	_check(outward_only.is_valid() and outward_only.target_hex == detached and outward_only.features["open_crossing_seconds"] > 0.0, "An interdiction-only assessment reproduces the unnecessary crossing to a detached firing position")
	query.profile.connected_cover_improvement_absolute = 0.75
	query.profile.connected_cover_improvement_relative = 0.2
	query.profile.interdiction_weight = 1.0
	var marginal_excursion: PositionResult = PositionQueryService.query_positions(query)
	_check(marginal_excursion.target_hex == local and marginal_excursion.features.get("connected_cover_preferred", false), "A small firing gain cannot send the defender across unknown open ground when useful connected woods exist")
	_check(marginal_excursion.eligibility[map.cell_to_index(detached)] == 1, "Protected-cover preference preserves detached candidates for exceptional tactical gains")
	query.profile.interdiction_weight = 12.0
	var exceptional: PositionResult = PositionQueryService.query_positions(query)
	_check(exceptional.target_hex == detached, "A substantial firing advantage can justify a detached position without a blanket exclusion")
	query.profile.interdiction_weight = 6.0
	query.profile.open_crossing_time_weight = 0.35
	query.profile.objective_return_open_weight = 0.75
	var sustainable: PositionResult = PositionQueryService.query_positions(query)
	_check(sustainable.is_valid() and sustainable.target_hex == local and sustainable.features["assigned_coverage"] >= 0.5 and sustainable.features["objective_connected_cover"], "The woods at the objective cover the approach without abandoning protected access to it")
	_check(sustainable.features["return_open_seconds"] == 0.0 and outward_only.features["return_open_seconds"] >= 2.0 * query.defense_crossing_seconds(), "The shared return field distinguishes connected woodland from several open hexes of objective response")
	query.sector_cells = [detached]
	var necessary: PositionResult = PositionQueryService.query_positions(query)
	_check(necessary.is_valid() and necessary.target_hex == detached, "A detached position remains possible when the mission has no suitable connected firing position")
	query.sector_cells = [local, detached]
	query.has_accepted_target = true
	query.accepted_target = local
	query.accepted_context = sustainable.context
	query.accepted_at = 100.0
	var repeated: PositionResult = PositionQueryService.query_positions(query)
	_check(repeated.target_hex == local and not repeated.path.has(Vector2i(6, 3)), "Repeated assessment retains the connected defense rather than sending it back across the field")
	query.objective_hex = detached
	job = query.snapshot.defense_area_job(own.team, detached, 5, 8)
	job.advance(-1)
	_check(job.result.geometry["return_open_costs"][detached] == 0.0 and job.result.geometry["return_open_costs"][local] > 0.0, "Changing the objective rebuilds protected return access rather than retaining the former woodland anchor")
	var graph: AStar2D = query.snapshot.routes[own.team]
	var objective_id: int = query.snapshot.point_ids[own.team][detached]
	for neighbor: int in graph.get_point_connections(objective_id):
		graph.disconnect_points(objective_id, neighbor)
	query.snapshot.defense_geometry_cache.clear()
	job = DefenseAreaJob.new()
	job.start(query.snapshot, own.team, detached, 5, 8, [])
	job.advance(-1)
	query.defense_area = job.result
	query.assigned_sector = -1
	query.has_accepted_target = false
	query.defense_responsibility = PositionQuery.Responsibility.AUTO
	query.sector_cells = [local]
	query.snapshot.los[local][detached] = {"target_cover": 1.0, "hindrance": 0.0}
	var disconnected: PositionResult = PositionQueryService.query_positions(query)
	_check(not disconnected.is_valid() and disconnected.rejections.has("objective_access"), "Fire visibility cannot authorize a position with no terrain route back to objective protection")
	own.squad_type = role


func _test_local_interception() -> void:
	var query: PositionQuery = _defense_fixture()
	var original_hex: Vector2i = own.current_hex
	var original_range: int = own.weapon_range
	var local: Vector2i = Vector2i(7, 3)
	var upstream: Vector2i = Vector2i(2, 3)
	own.current_hex = local
	own.weapon_range = 3
	query.snapshot.positions[own as Unit] = local
	query.objective_hex = Vector2i(8, 3)
	query.defense_radius = 3
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.sector_cells = [local, upstream]
	query.snapshot.defensive_contacts[own.team] = [_area_contact(Vector2i(0, 3), query.snapshot.captured_at)]
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, float(cell.x >= 6 or cell == upstream))
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, 0.0)
	query.snapshot.los = query.snapshot.los.duplicate(true)
	query.snapshot.los[local] = {}
	query.snapshot.los[upstream] = {}
	for cell: Vector2i in map.playable_cells:
		var record: Dictionary = {"target_cover": map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), "hindrance": 0.0}
		if LOSHelper.get_hex_distance(cell, query.objective_hex) <= query.defense_radius:
			query.snapshot.los[local][cell] = record
		if cell.x <= 4:
			query.snapshot.los[upstream][cell] = record
	var job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 8, 10)
	job.advance(-1)
	query.defense_area = job.result
	query.assigned_sector = job.result.sector_at(Vector2i(0, 3))
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == local and not advice.should_move, "A short-range defender can hold the woods covering the final approach of a long incoming route")
	_check(advice.features.get("assigned_coverage", 0.0) >= 0.5 and advice.features.get("assigned_corridor_coverage", 1.0) < 0.5, "Local interception responsibility is independent of whole-corridor visibility")
	_check(advice.eligibility[map.cell_to_index(upstream)] == 0, "An upstream firing position that cannot cover the objective-side approach is not a valid interception duty")
	var shorter: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 4, 8)
	shorter.advance(-1)
	query.defense_area = shorter.result
	var repeated: PositionResult = PositionQueryService.query_positions(query)
	_check(repeated.target_hex == local and is_equal_approx(repeated.features.get("assigned_coverage", 0.0), advice.features.get("assigned_coverage", 1.0)), "Extending the outer analysis horizon does not change an unchanged local interception duty")
	own.current_hex = original_hex
	own.weapon_range = original_range
	own.position = ground.map_to_local(original_hex)


func _test_complementary_defense() -> void:
	var query: PositionQuery = _defense_fixture()
	var original_hex: Vector2i = own.current_hex
	var original_role: Globals.SquadType = own.squad_type
	var original_own_power: int = own.firepower
	var original_power: int = other.firepower
	var near: Vector2i = Vector2i(4, 3)
	var edge: Vector2i = Vector2i(5, 3)
	var common: Array[Vector2i] = [Vector2i(4, 2), Vector2i(4, 4)]
	var first_crossing: Vector2i = Vector2i(6, 2)
	var second_crossing: Vector2i = Vector2i(6, 4)
	query.objective_hex = Vector2i(3, 3)
	query.defense_radius = 4
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.sector_cells = [near, edge]
	own.squad_type = Globals.SquadType.MG
	own.firepower = 16
	other.firepower = 16
	own.current_hex = near
	own.position = ground.map_to_local(near)
	query.snapshot.positions[own as Unit] = near
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, float(cell.x >= 2 and cell.x <= 5 and cell.y >= 2 and cell.y <= 4))
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, 0.0)
	query.snapshot.terrain_key = 9234
	query.snapshot.defense_geometry_cache = {}
	var axis: ThreatAxis = ThreatAxis.new()
	axis.source_hex = Vector2i(8, 3)
	axis.confidence = 1.0
	var job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 8, 10, [axis])
	job.advance(-1)
	query.defense_area = job.result
	query.assigned_sector = job.result.sector_at(axis.source_hex)
	var approach: Dictionary = job.result.approach_for_sector(query.assigned_sector).duplicate()
	approach.erase("branches")
	approach["cells"] = [common[0], common[1], first_crossing, second_crossing]
	approach["weights"] = {common[0]: 0.5, common[1]: 0.5, first_crossing: 4.0, second_crossing: 4.0}
	approach["arrival_seconds"] = INF
	query.defense_area.approaches = [approach]
	query.defense_area.max_priority = approach["priority"]
	query.snapshot.los = query.snapshot.los.duplicate(true)
	query.snapshot.los[near] = {query.objective_hex: {"target_cover": 1.0, "hindrance": 0.0}}
	query.snapshot.los[edge] = {}
	query.snapshot.los[query.objective_hex] = {}
	for target: Vector2i in common:
		query.snapshot.los[near][target] = {"target_cover": 1.0, "hindrance": 0.0}
		query.snapshot.los[edge][target] = {"target_cover": 1.0, "hindrance": 1.0}
		query.snapshot.los[query.objective_hex][target] = {"target_cover": 1.0, "hindrance": 0.0}
	query.snapshot.los[near][first_crossing] = {"target_cover": 0.0, "hindrance": 0.0}
	query.snapshot.los[edge][second_crossing] = {"target_cover": 0.0, "hindrance": 1.0}
	query.snapshot.los[query.objective_hex][first_crossing] = {"target_cover": 0.0, "hindrance": 0.0}
	var alone: PositionResult = PositionQueryService.query_positions(query)
	_check(alone.target_hex == near and not alone.should_move, "Useful woods beside the objective remain a stable approach position without a distance requirement")
	query.reservations[other as Unit] = query.objective_hex
	var complementary: PositionResult = PositionQueryService.query_positions(query)
	var near_features: Dictionary = PositionFeatureEvaluator.evaluate(query, near, [])
	var edge_features: Dictionary = PositionFeatureEvaluator.evaluate(query, edge, [])
	_check(is_equal_approx(near_features["assigned_coverage"], edge_features["assigned_coverage"]), "Both woodland firing lanes satisfy the same final-approach responsibility")
	_check(edge_features["additional_interdiction"] > near_features["additional_interdiction"], "Covering another open crossing contributes more than duplicating the guard's firing lane")
	_check(complementary.target_hex == edge and complementary.features["objective_connected_cover"] and complementary.features["open_crossing_seconds"] == 0.0, "An approach squad uses the connected woodland edge to complement the guard without an open crossing")
	query.has_accepted_target = true
	query.accepted_target = edge
	query.accepted_context = complementary.context
	query.accepted_at = query.snapshot.captured_at
	_check(PositionQueryService.query_positions(query).target_hex == edge, "The complementary firing position remains stable on repeated advice")
	query.has_accepted_target = false
	other.firepower = 0
	var unarmed: PositionResult = PositionQueryService.query_positions(query)
	_check(unarmed.target_hex == near and is_equal_approx(unarmed.features["additional_interdiction"], unarmed.features["interdiction"]), "An unarmed guard cannot claim firing coverage or displace the established defender")
	other.firepower = original_power
	other.in_close_combat = true
	var engaged: PositionResult = PositionQueryService.query_positions(query)
	_check(engaged.target_hex == near and is_equal_approx(engaged.features["additional_interdiction"], engaged.features["interdiction"]), "A guard occupied in close combat cannot supply supporting fire")
	other.in_close_combat = false
	query.reservations.clear()
	query.snapshot.los[edge] = query.snapshot.los[near].duplicate(true)
	var same_lane: PositionResult = PositionQueryService.query_positions(query)
	_check(same_lane.target_hex == near and not same_lane.should_move, "Greater distance from the objective does not reward the same firing lane")
	own.current_hex = original_hex
	own.position = ground.map_to_local(original_hex)
	own.squad_type = original_role
	own.firepower = original_own_power


func _test_defensive_memory() -> void:
	var memory: DefensiveContactMemory = DefensiveContactMemory.new()
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.maps[own.team] = InfluenceMap.new()
	snapshot.positions[own as Unit] = own.current_hex
	snapshot.teams[own as Unit] = own.team
	snapshot.captured_at = 10.0
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = Vector2i(6, 3)
	contact.firepower = 2.0
	contact.weapon_range = 6
	contact.observed = true
	snapshot.contacts[own.team] = [contact]
	memory.capture_into(snapshot)
	var published: InfluenceContact = snapshot.get_defensive_contacts(own.team)[0]
	snapshot.contacts[own.team] = []
	snapshot.captured_at = 100.0
	memory.capture_into(snapshot)
	var remembered: InfluenceContact = snapshot.get_defensive_contacts(own.team)[0]
	_check(not remembered.observed and remembered.hex == contact.hex and remembered.firepower == contact.firepower and remembered.confidence == 0.5, "Last-confirmed tactical danger persists at bounded confidence beyond firing-track expiry")
	_check(published.observed and published.confidence == 1.0, "Remembering a contact does not mutate a previously published contact")
	snapshot.los = {contact.hex: {own.current_hex: {"target_cover": 0.8, "hindrance": 0.0}}}
	var query: PositionQuery = _query()
	query.snapshot = snapshot
	var observed_risk: float = PositionFeatureEvaluator._contact_fire_risk(query, [published], own.current_hex, true)
	var remembered_risk: float = PositionFeatureEvaluator._contact_fire_risk(query, [remembered], own.current_hex, true)
	_check(observed_risk > 0.0 and is_equal_approx(observed_risk, remembered_risk), "Fading location confidence does not turn a last-confirmed firing lane into a safe route")
	_check(observed_risk > PositionFeatureEvaluator._contact_fire_risk(query, [published], own.current_hex, false), "Moving squads do not claim stationary target cover in exposure checks")
	snapshot.positions[own as Unit] = contact.hex
	snapshot.captured_at = 14.0
	contact.observed = false
	contact.confidence = 1.0 - 4.0 / Unit.ENEMY_MEMORY_LIFETIME
	snapshot.contacts[own.team] = [contact]
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team).is_empty(), "Physically checking an unoccupied last-known hex clears its danger")
	snapshot.positions[own as Unit] = own.current_hex
	snapshot.captured_at = 15.0
	contact.confidence = 1.0 - 5.0 / Unit.ENEMY_MEMORY_LIFETIME
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team).is_empty(), "Old firing memory cannot resurrect a cleared danger location")
	contact.observed = true
	contact.confidence = 1.0
	contact.hex = Vector2i(8, 6)
	snapshot.captured_at = 16.0
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team)[0].hex == contact.hex, "A new confirmed sighting updates the tactical danger location")
	var was_alive: bool = enemy.alive
	enemy.alive = false
	snapshot.contacts[own.team] = []
	memory.capture_into(snapshot)
	_check(not snapshot.get_defensive_contacts(own.team).is_empty(), "An unobserved casualty cannot leak hidden live state into danger knowledge")
	Globals.unit_visible_enemies[own] = [enemy]
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team).is_empty(), "A reported visible casualty clears the remembered threat")
	enemy.alive = was_alive
	Globals.unit_visible_enemies[own] = []
	controller.reset_for_match()
	_check(controller.defensive_memory.contacts_by_team.is_empty(), "Starting a new match clears prior tactical danger")


func _test_branch_defense() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(1, 3)
	query.defense_radius = 6
	query.snapshot.captured_at = 100.0
	var upper_source: Vector2i = Vector2i(8, 1)
	var lower_source: Vector2i = Vector2i(8, 5)
	var spread_enemy: UnitProbe = _unit(enemy.team, lower_source)
	var lower_contact: InfluenceContact = _area_contact(lower_source, 99.0, false)
	lower_contact.unit = spread_enemy
	query.snapshot.defensive_contacts[own.team] = [_area_contact(upper_source, 100.0), lower_contact]
	var job: DefenseAreaJob = query.snapshot.defense_area_job(own.team, query.objective_hex, 6, 10)
	job.advance(-1)
	var sector: int = job.result.sector_at(upper_source)
	var parent: Dictionary = job.result.approach_for_sector(sector)
	_check(sector == job.result.sector_at(lower_source) and parent["branches"].size() == 2, "Separated observed and remembered enemy groups in one sector receive distinct branches")
	_check(parent["source"] == upper_source and parent["branches"][1]["source"] == lower_source and parent["branches"][1]["evidence"] == "remembered", "Each branch retains its own captured source and knowledge evidence")
	var primary: Dictionary = parent["branches"][0]
	var margin_count: int = 0
	var bounded: bool = true
	for cell: Vector2i in primary["cells"]:
		if parent["cells"].has(cell):
			continue
		margin_count += 1
		var adjacent: bool = false
		for core: Vector2i in parent["cells"]:
			adjacent = adjacent or job.result.geometry["neighbors"].get(core, []).has(cell)
		bounded = bounded and adjacent and primary["distances"][cell] <= primary["distances"][query.objective_hex]
	_check(margin_count > 0 and bounded, "Lateral uncertainty adds one connected terrain step and never branches beyond objective arrival")
	var assignments: Dictionary[Unit, String] = DefenseSectorAllocator.assign_branches(job.result, [own, other], {})
	_check(assignments.size() == 2 and assignments[own as Unit] != assignments[other as Unit] and DefenseSectorAllocator.critical_count(job.result) == 2, "Two credible branches in one sector receive separate defenders and can mobilize a reserve")
	var previous: Dictionary = {own: {"branch": assignments[own as Unit]}, other: {"branch": assignments[other as Unit]}}
	_check(DefenseSectorAllocator.assign_branches(job.result, [own, other], previous) == assignments, "Repeated branch assignments preserve existing responsibilities")
	spread_enemy.current_hex = Vector2i(0, 0)
	var remembered_job: DefenseAreaJob = DefenseAreaJob.new()
	remembered_job.start(query.snapshot, own.team, query.objective_hex, 6, 10, [])
	remembered_job.advance(-1)
	_check(remembered_job.result.approach_for_sector(sector)["branches"][1]["source"] == lower_source, "Unseen live movement cannot shift a remembered approach branch")
	var freshness_planner: PlatoonAI = PlatoonAI.new()
	freshness_planner.influence_map_controller = controller
	freshness_planner.team = own.team
	freshness_planner.current_order = MissionOrder.new()
	freshness_planner.defense_area = job.result
	var captured_contact: InfluenceContact = query.snapshot.defensive_contacts[own.team][0]
	query.snapshot.contacts[own.team] = [captured_contact]
	_check(not freshness_planner._defense_plan_outdated(), "An unchanged observed branch permits the completed batch to publish")
	captured_contact.hex = lower_source
	_check(freshness_planner._defense_plan_outdated(), "Observed movement to a different branch within the same sector invalidates old branch advice")
	captured_contact.observed = false
	_check(not freshness_planner._defense_plan_outdated(), "Remembered hidden movement cannot invalidate a captured branch plan")
	captured_contact.hex = upper_source
	captured_contact.observed = true
	freshness_planner.free()
	var reverse: DefenseAreaJob = query.snapshot.defense_area_job(enemy.team, query.objective_hex, 6, 10)
	for cell: Vector2i in query.snapshot.maps[own.team].playable_cells:
		query.snapshot.maps[enemy.team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, query.snapshot.maps[own.team].get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell))
		query.snapshot.maps[enemy.team].set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, query.snapshot.maps[own.team].get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell))
	query.snapshot.defensive_contacts[enemy.team] = query.snapshot.defensive_contacts[own.team]
	reverse.advance(-1)
	_check(reverse.result.approach_for_sector(sector)["branches"].size() == 2 and reverse.result.geometry["return_open_costs"] == job.result.geometry["return_open_costs"], "Mirrored teams produce the same branch and return geography from the same knowledge")
	spread_enemy.free()
	# Isolate complementary firing lanes: one side position sees only one of three target cells.
	var candidate: Vector2i = Vector2i(4, 3)
	var upper: Vector2i = Vector2i(5, 2)
	var lower: Vector2i = Vector2i(5, 4)
	var bottom: Vector2i = Vector2i(6, 4)
	var other_hex: Vector2i = other.current_hex
	var other_power: int = other.firepower
	other.current_hex = Vector2i(3, 4)
	other.firepower = 16
	query.snapshot.positions[other as Unit] = other.current_hex
	query.snapshot.los = query.snapshot.los.duplicate(true)
	var record: Dictionary = {"target_cover": 0.0, "hindrance": 0.0}
	query.snapshot.los[own.current_hex] = {upper: record}
	query.snapshot.los[candidate] = {upper: record}
	query.snapshot.los[other.current_hex] = {lower: record, bottom: record}
	query.snapshot.defensive_contacts[own.team] = []
	var upper_branch: Dictionary = {"id": sector, "key": "upper", "source": upper_source, "evidence": "observed", "priority": 1.0, "share": 0.5,
		"cells": [upper], "weights": {upper: 1.0}, "arrival_seconds": INF, "response_distances": parent["response_distances"]}
	var lower_branch: Dictionary = {"id": sector, "key": "lower", "source": lower_source, "evidence": "remembered", "priority": 1.0, "share": 0.5,
		"cells": [lower, bottom], "weights": {lower: 1.0, bottom: 1.0}, "arrival_seconds": INF, "response_distances": parent["response_distances"]}
	var pooled: Dictionary = upper_branch.duplicate()
	pooled.erase("key")
	pooled.erase("share")
	pooled["priority"] = 2.0
	pooled["cells"] = [upper, lower, bottom]
	pooled["weights"] = {upper: 1.0, lower: 1.0, bottom: 1.0}
	pooled["branches"] = [upper_branch, lower_branch]
	var area: DefenseAreaAssessment = DefenseAreaAssessment.new()
	area.objective_hex = query.objective_hex
	area.snapshot_version = query.snapshot.version
	area.geometry = job.result.geometry.duplicate(true)
	area.approaches = [pooled]
	area.max_priority = 2.0
	query.defense_area = area
	query.assigned_sector = sector
	query.sector_cells = [candidate]
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.reservations = {}
	var map: InfluenceMap = query.snapshot.maps[own.team]
	var index: int = map.cell_to_index(candidate)
	var pooled_advice: PositionResult = PositionQueryService.query_positions(query)
	_check(not pooled_advice.is_valid() and pooled_advice.rejection_reasons[index] == "responsibility", "The old pooled fifty-percent rule reproduces exclusion of a useful side firing position")
	query.assigned_branch = "upper"
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == candidate and advice.features["assigned_coverage"] == 1.0 and advice.features["branch_coverage"]["lower"] == 0.0, "A woodland side position qualifies by covering its branch while another established squad covers the remainder")
	_check(advice.branch_sources["lower"] == lower_source and advice.branch_evidence["lower"] == "remembered" and not advice.approach_cells.has(lower), "The position overlay publishes the assigned branch and separate captured branch evidence")
	var upper_context: String = query.context_key()
	query.assigned_branch = "lower"
	_check(query.context_key() != upper_context and not PositionQueryService.query_positions(query).is_valid(), "Changing branch responsibility invalidates a commitment to a different firing lane")
	query.assigned_branch = "upper"
	query.sector_cells.append(own.current_hex)
	advice = PositionQueryService.query_positions(query)
	_check(advice.target_hex == own.current_hex and not advice.should_move, "Additional branch alternatives do not force movement from a useful covered position")
	query.sector_cells = [candidate]
	query.relocation_allowed = false
	advice = PositionQueryService.query_positions(query)
	_check(not advice.is_valid() and advice.cell_states[index] == PositionResult.CellState.WAITING_HANDOFF and advice.eligibility[index] == 0 and advice.rejection_reasons[index] == "handoff_wait", "A fully safe useful hex waiting for a handoff is diagnosed separately from executable candidates")
	query.fallback_hexes = [own.current_hex]
	var fallback_advice: PositionResult = PositionQueryService.query_positions(query)
	_check(fallback_advice.is_valid() and fallback_advice.target_hex == own.current_hex and fallback_advice.cell_states[index] == PositionResult.CellState.WAITING_HANDOFF, "A fallback hold preserves the useful primary hex's handoff diagnosis")
	query.fallback_hexes = []
	var draw: InfluenceMapDebugDraw = InfluenceMapDebugDraw.new()
	draw.influence_controller = controller
	draw.tile_map_layer = ground
	draw.team = own.team
	draw.debug_view = InfluenceMapDebugDraw.DebugView.POSITION_SCORE
	draw.selected_unit = own
	draw.position_advice = advice
	_check(draw._should_draw_cell(map, candidate) and draw.hex_diagnostic(candidate).contains("waiting"), "Waiting positions remain visible with a hover explanation")
	draw.free()
	var adapted: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, null, "test")
	_check(adapted.cell_states == advice.cell_states and adapted.rejection_reasons == advice.rejection_reasons and adapted.branch_sources == advice.branch_sources, "Defense adapters preserve per-hex and branch diagnostics")
	var incremental: PositionQueryJob = PositionQueryJob.new()
	incremental.query = query
	while not incremental.completed:
		incremental.advance(Time.get_ticks_usec() + 100)
	_check(incremental.result.cell_states == advice.cell_states and incremental.result.rejection_reasons == advice.rejection_reasons and incremental.result.score_map == advice.score_map, "Incremental queries preserve waiting states, per-hex reasons and useful-position scores")
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, candidate, 0.0)
	advice = PositionQueryService.query_positions(query)
	_check(advice.cell_states[index] == PositionResult.CellState.REJECTED and advice.rejection_reasons[index] == "cover", "An open destination is unsuitable even while a handoff is pending")
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, candidate, 1.0)
	query.reservations[other as Unit] = candidate
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "capacity", "A reserved branch position remains unavailable")
	query.reservations.clear()
	area.geometry["return_open_costs"].erase(candidate)
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "objective_access", "Branch usefulness cannot override missing objective access")
	area.geometry["return_open_costs"][candidate] = 0.0
	map.set_layer_value(InfluenceMap.Layer.THREAT, candidate, 100.0)
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "risk", "Excessive fire danger is not mislabeled as a temporary handoff wait")
	map.set_layer_value(InfluenceMap.Layer.THREAT, candidate, 0.0)
	var graph: AStar2D = query.snapshot.routes[own.team]
	var origin_id: int = query.snapshot.point_ids[own.team][own.current_hex]
	var connected: PackedInt64Array = graph.get_point_connections(origin_id)
	for neighbor: int in connected:
		graph.disconnect_points(origin_id, neighbor)
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "route", "An unreachable useful firing hex is unsuitable rather than merely waiting for a handoff")
	for neighbor: int in connected:
		graph.connect_points(origin_id, neighbor)
	query.relocation_allowed = true
	query.snapshot.los[own.current_hex][lower] = record
	query.snapshot.los[own.current_hex][bottom] = record
	_check(PositionQueryService.query_positions(query).is_valid(), "Established covering fire permits a branch handoff without opening the other branch")
	other.movement.is_moving = true
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "A moving squad cannot replace the established coverage of another branch")
	other.movement.is_moving = false
	var captured_support: Vector2i = other.current_hex
	other.current_hex = Vector2i(3, 5)
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "A stationary squad at a different live hex cannot provide covering fire from its old snapshot position")
	other.current_hex = captured_support
	query.reservations[other as Unit] = Vector2i(4, 4)
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "A future firing reservation cannot authorize abandoning an established branch")
	query.reservations.clear()
	other.firepower = 0
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "An unarmed supporting squad cannot supply a branch handoff")
	other.firepower = 16
	other.in_close_combat = true
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "A supporting squad in close combat cannot supply a branch handoff")
	other.in_close_combat = false
	# Shared coverage matters even when no individual squad covers half a branch.
	var shared_a: Vector2i = Vector2i(5, 1)
	var shared_b: Vector2i = Vector2i(6, 1)
	var shared_c: Vector2i = Vector2i(7, 1)
	var shared: Dictionary = upper_branch.duplicate()
	shared["key"] = "shared"
	shared["cells"] = [shared_a, shared_b, shared_c]
	shared["weights"] = {shared_a: 1.0, shared_b: 1.0, shared_c: 1.0}
	pooled["branches"].append(shared)
	for branch: Dictionary in pooled["branches"]:
		branch["share"] = 1.0 / 3.0
	pooled["priority"] = 3.0
	area.max_priority = 3.0
	query.defense_radius = 8
	query.snapshot.los[own.current_hex][shared_a] = record
	query.snapshot.los[other.current_hex][shared_b] = record
	_check(PositionQueryService.query_positions(query).rejection_reasons[index] == "screen_gap", "Relocation preserves established combined coverage even when each defender covers less than half individually")
	query.snapshot.los[candidate][shared_a] = record
	_check(PositionQueryService.query_positions(query).is_valid(), "Complementary partial firing lanes jointly preserve a branch during relocation")
	advice = PositionQueryService.query_positions(query)
	var requests: Array[Dictionary] = [{"query": query}]
	var results: Array[DefensePositionResult] = [DefensePositionAnalyzer.adapt_result(advice, null, "test")]
	var validation: DefensePlanValidationJob = DefensePlanValidationJob.new()
	validation.start(area, requests, results)
	validation.advance(Time.get_ticks_usec() - 1)
	_check(not validation.completed and validation.index == 0, "Live final validation respects an exhausted frame budget without publishing a partial plan")
	other.movement.is_moving = true
	validation.advance(-1)
	_check(validation.completed and not validation.valid, "Supporting movement during deferred validation invalidates the entire pending plan")
	other.movement.is_moving = false
	validation = DefensePlanValidationJob.new()
	validation.start(area, requests, results)
	var validation_slices: int = 0
	while not validation.completed and validation_slices < 1000:
		validation.advance(Time.get_ticks_usec() + 100)
		validation_slices += 1
	_check(validation.completed and validation.valid and validation_slices > 1 and validation.branch_gaps.is_empty(), "Incremental final validation publishes complete shared branch coverage when supporting state remains unchanged")
	_check(query.destination_features.is_empty() and query.route_field == null and advice.target_hex == candidate and advice.eligibility[index] == 1, "Incremental cache release preserves the completed advice and its candidate diagnostics")
	other.firepower = 0
	_check(not validation.unchanged(), "Equipment loss after final validation prevents publishing stale supporting fire")
	other.firepower = 16
	other.current_hex = other_hex
	other.firepower = other_power
	_publish()
