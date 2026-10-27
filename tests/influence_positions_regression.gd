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
	_check(controller.knowledge_policy == InfluenceMapController.KnowledgePolicy.OMNISCIENT, "Default tactical knowledge includes hidden enemy positions")
	controller.knowledge_policy = InfluenceMapController.KnowledgePolicy.OBSERVED_AND_MEMORY
	controller.set_objective_for_team(Globals.Team.AXIS, Vector2i(3, 3))
	controller.set_objective_for_team(Globals.Team.ALLIES, Vector2i(5, 3))
	_publish()
	_test_knowledge()
	_test_concealed_escape()
	controller.defensive_memory.clear()
	_test_publication()
	_test_snapshot_capture_slices()
	_test_cached_stamp_geometry()
	_test_forecast_jobs()
	_test_selection()
	_test_geography()
	_test_ownership_and_reservations()
	_test_automatic_registration()
	_test_legacy_score_parity()
	_test_profiles()
	_test_suppressed_hex_entry()
	_test_attack_overwatch()
	_test_supported_close_assault()
	_test_attack_support_recovery()
	_test_attack_pressure_and_following()
	_test_position_stability()
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
	_test_secured_objective_cover()
	_test_screen_deployment_budget()
	_test_crossing_budget()
	_test_rapid_defense_response()
	_test_defensive_withdrawal()
	_test_defense_mission_context()
	_test_defensive_memory()
	_test_budgeted_position_queries()
	_test_defense_area()
	_test_corridor_evidence()
	_test_objective_connected_defense()
	_test_forward_screen_and_fallback()
	_test_established_screen_retention()
	_test_local_interception()
	_test_complementary_defense()
	_test_loadout_stationary_roles()
	_test_branch_defense()
	_test_sector_pressure_and_protected_reserve()
	_test_flexible_defense()
	_test_concurrent_relocation()
	_test_progressive_planning()
	await _test_headquarters_support()
	_test_attack_headquarters_support()
	_test_headquarters_stacking()
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
	var query: PositionQuery = _query()
	query.snapshot = controller.snapshot
	var hidden_risk: float = PositionFeatureEvaluator.route_step(query, own.current_hex)["risk"]
	_check(hidden_risk > 0.0, "Hidden enemy firing lanes contribute defensive flood exposure")
	query.profile.max_route_exposure = 0.0
	var field: PositionRouteField = PositionRouteField.new()
	field.start(query, [enemy.current_hex])
	field.advance(-1)
	_check(field.path_to(enemy.current_hex).is_empty(), "The defensive flood rejects crossing hidden enemy fire beyond the route budget")
	field.release_query()
	var hidden_hex: Vector2i = enemy.current_hex
	enemy.current_hex = Vector2i(8, 6)
	_publish()
	_check(controller.snapshot.get_defensive_contacts(own.team)[0].hex == enemy.current_hex, "Tactical danger follows the real position of an unseen moving enemy")
	enemy.current_hex = hidden_hex
	controller.knowledge_policy = InfluenceMapController.KnowledgePolicy.OBSERVED_AND_MEMORY
	_publish()


func _test_concealed_escape() -> void:
	var exit: Vector2i = Vector2i(7, 3)
	var detour: Vector2i = Vector2i(4, 0)
	var direct_path: Array[Vector2i] = controller.snapshot.get_path(own.team, own.current_hex, exit)
	var concealed_path: Array[Vector2i] = controller.snapshot.get_path(own.team, own.current_hex, detour)
	concealed_path.append_array(controller.snapshot.get_path(own.team, detour, exit).slice(1))
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(Rect2i(0, 0, 9, 7))
	var graph: AStar2D = AStar2D.new()
	var ids: Dictionary[Vector2i, int] = {}
	# Two complete corridors share an exit: a short visible road and a longer hidden bypass.
	for path: Array[Vector2i] in [direct_path, concealed_path]:
		for index: int in range(path.size()):
			var cell: Vector2i = path[index]
			if not ids.has(cell):
				ids[cell] = ids.size()
				graph.add_point(ids[cell], ground.map_to_local(cell))
				map.playable_cells[cell] = true
			if index > 0:
				graph.connect_points(ids[path[index - 1]], ids[cell])
	snapshot.maps[own.team] = map
	snapshot.routes[own.team] = graph
	snapshot.point_ids[own.team] = ids
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = Vector2i(4, 6)
	contact.weapon_range = 8
	contact.observed = true
	# Isolate concealment from the existing fire-risk and terrain-cover preferences.
	contact.firepower = 0.0
	snapshot.defensive_contacts[own.team] = [contact]
	snapshot.los[contact.hex] = {}
	for cell: Vector2i in ids:
		snapshot.los[contact.hex][cell] = {"hindrance": 0.0, "target_concealment": 0.0}
	for cell: Vector2i in concealed_path:
		if not direct_path.has(cell):
			snapshot.los[contact.hex][cell]["hindrance"] = 8.0
	var query: PositionQuery = PositionQuery.new()
	query.unit = own
	query.team = own.team
	query.snapshot = snapshot
	query.objective_hex = exit
	query.escape_hexes = [exit]
	query.escape_policy = EscapeMissionPolicy.new()
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	query.profile.max_incoming_risk = 1.0
	query.profile.max_route_exposure = 1.0
	query.profile.avoid_unsuppressed_defenders = true
	query.use_defense_area = false
	var weight: float = query.escape_policy.concealment_weight
	query.escape_policy.concealment_weight = 0.0
	var direct: PositionResult = PositionQueryService.query_positions(query)
	_check(direct.is_valid() and direct.path == direct_path, "Travel and fire risk alone reproduce the short crossing near the defender")
	query.escape_policy.concealment_weight = weight
	var concealed: PositionResult = PositionQueryService.query_positions(query)
	_check(concealed.is_valid() and concealed.path.has(detour) and concealed.features["route_seconds"] > direct.features["route_seconds"], "Escape accepts a longer concealed detour instead of the nearby visible road crossing")
	_check(concealed.features["visibility_seconds"] < direct.features["visibility_seconds"], "The concealed bypass reduces time visible to the defender")
	var settled: int = query.route_field.labels_by_cell[exit][0]
	_check(is_equal_approx(concealed.features["escape_cost"], query.route_field.labels[settled]["cost"]), "Exit scoring and the weighted route search use the same concealment cost")
	query.escape_hexes.append(direct_path[-2])
	var alternate_exit: PositionResult = PositionQueryService.query_positions(query)
	_check(alternate_exit.is_valid() and alternate_exit.target_hex == exit and alternate_exit.path.has(detour), "A concealed route to a farther exit beats an exposed route to the nearer exit")
	var job: PositionQueryJob = PositionQueryJob.new()
	job.query = query
	var slices: int = 0
	while not job.completed and slices < 10000:
		job.advance(Time.get_ticks_usec() + 50)
		slices += 1
	_check(job.completed and job.result.path == alternate_exit.path and is_equal_approx(job.result.score, alternate_exit.score), "Sliced planning preserves the concealed route and exit choice")
	graph.set_point_disabled(ids[detour], true)
	var exposed: PositionResult = PositionQueryService.query_positions(query)
	_check(exposed.is_valid() and not exposed.path.has(detour), "Escape still uses an exposed route when the concealed bypass is unavailable")
	graph.set_point_disabled(ids[detour], false)
	contact.observed = false
	contact.confidence = 0.0
	var forgotten: PositionResult = PositionQueryService.query_positions(query)
	_check(forgotten.is_valid() and not forgotten.path.has(detour), "A contact with no remaining confidence does not impose a concealed detour")
	contact.confidence = 1.0
	var remembered: PositionResult = PositionQueryService.query_positions(query)
	_check(remembered.is_valid() and remembered.path.has(detour), "Remembered enemy sightlines favor a concealed route without becoming hard blockers")
	var sample: Vector2i = direct_path[2]
	var visible: float = EscapeCorridorPolicy.route_visibility(snapshot, own.team, sample)
	snapshot.los[contact.hex][sample]["target_concealment"] = 2.0
	_check(EscapeCorridorPolicy.route_visibility(snapshot, own.team, sample) < visible, "Target concealment reduces observation independently of terrain cover")
	snapshot.los[contact.hex].erase(sample)
	_check(is_zero_approx(EscapeCorridorPolicy.route_visibility(snapshot, own.team, sample)), "Blocked enemy LOS adds no observation cost")
	var context: String = query.context_key()
	query.escape_policy.concealment_weight = 0.0
	_check(query.context_key() != context, "Editing concealment preference invalidates the escape query context")
	query.escape_policy.exit_condition = ExitUnitsCondition.new()
	query.escape_policy.concealment_weight = -1.0
	_check(query.escape_policy.configuration_error([query.escape_policy.exit_condition]) != "", "Escape policies reject negative concealment weights")
	query.escape_policy.concealment_weight = NAN
	_check(query.escape_policy.configuration_error([query.escape_policy.exit_condition]) != "", "Escape policies reject nonfinite concealment weights")


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


func _test_snapshot_capture_slices() -> void:
	var weights: PackedFloat32Array = controller.create_default_weights()
	var job: InfluenceSnapshotBuilder.CaptureJob = InfluenceSnapshotBuilder.begin_capture(99, controller.objectives_by_team, controller.knowledge_policy, weights)
	var expected: InfluenceSnapshot = InfluenceSnapshotBuilder.capture(99, controller.objectives_by_team, controller.knowledge_policy, weights)
	job.advance(Time.get_ticks_usec() - 1)
	_check(not job.completed and job.snapshot.maps.is_empty(), "An exhausted capture budget leaves map construction pending")
	var own_hex: Vector2i = own.current_hex
	var enemy_hex: Vector2i = enemy.current_hex
	var own_state: STATES.MoraleState = own.stress_system.state
	own.current_hex += Vector2i(1, 0)
	enemy.current_hex += Vector2i(-1, 0)
	own.stress_system.state = STATES.MoraleState.PANIC
	job.advance(-1)
	_check(job.completed and job.snapshot.positions == expected.positions and job.snapshot.support_units == expected.support_units, "Capture slices retain initial unit positions and morale after live state changes")
	for team: int in expected.maps:
		for layer: int in range(InfluenceMap.Layer.COUNT):
			_check(job.snapshot.maps[team].get_layer_data_copy(layer) == expected.maps[team].get_layer_data_copy(layer), "Budgeted capture preserves synchronous layer values")
		_check(job.snapshot.point_ids[team] == expected.point_ids[team] and job.snapshot.route_topology_key == expected.route_topology_key, "Budgeted capture preserves navigation topology")
	var fixture: InfluenceMapController = InfluenceMapController.new()
	fixture.pending_snapshot = job.snapshot
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	config.unit_team = own.team
	config.enemy_team = enemy.team
	config.contacts = job.snapshot.get_contacts(own.team)
	LosInfluenceProjector.begin_budgeted_rebuild_for_team(fixture, job.snapshot.maps[own.team], config)
	var found: bool = false
	for source: ProjectionSource in fixture.los_rebuild_jobs[0].sources:
		if source.unit == own:
			found = source.observer_hex == own_hex and source.effectiveness == expected.support_units.get(own, {})["effectiveness"]
	_check(found, "Friendly LOS sources use the same captured positions and effectiveness as their tactical layers")
	fixture.reset_for_match()
	fixture.free()
	own.current_hex = own_hex
	enemy.current_hex = enemy_hex
	own.stress_system.state = own_state


func _test_cached_stamp_geometry() -> void:
	for center: Vector2i in [Vector2i(-1, -1), Vector2i.ZERO, Vector2i(1, 2), Vector2i(2, 3)]:
		for falloff: InfluenceMap.FalloffMode in [InfluenceMap.FalloffMode.NONE, InfluenceMap.FalloffMode.LINEAR, InfluenceMap.FalloffMode.SQUARE_ROOT, InfluenceMap.FalloffMode.EXPONENTIAL]:
			var stamp: InfluenceStamp = InfluenceMapStampOps.create_radius_stamp(center, 3, 2.3, falloff)
			var scaled: InfluenceStamp = InfluenceMapStampOps.create_radius_stamp(center, 3, -0.7, falloff)
			var original: PackedFloat32Array = PackedFloat32Array()
			var negative: PackedFloat32Array = PackedFloat32Array()
			original.resize(stamp.values.size())
			negative.resize(stamp.values.size())
			for y: int in range(stamp.size.y):
				for x: int in range(stamp.size.x):
					var distance: int = LOSHelper.get_hex_distance(center, stamp.min_cell + Vector2i(x, y))
					if distance <= 3:
						original[y * stamp.size.x + x] = InfluenceMapStampOps.get_radius_falloff_value(2.3, distance, 3, falloff)
						negative[y * stamp.size.x + x] = InfluenceMapStampOps.get_radius_falloff_value(-0.7, distance, 3, falloff)
			_check(stamp.values == original and scaled.values == negative, "Cached hex geometry preserves exact falloff values across centers and strengths")
			for mode: InfluenceMap.WriteMode in [InfluenceMap.WriteMode.SET, InfluenceMap.WriteMode.ADD, InfluenceMap.WriteMode.SUBTRACT, InfluenceMap.WriteMode.MAX, InfluenceMap.WriteMode.MIN]:
				var optimized: InfluenceMap = InfluenceMap.new()
				var reference: InfluenceMap = InfluenceMap.new()
				optimized.configure(Rect2i(-2, -2, 7, 7))
				reference.configure(optimized.bounds)
				optimized.clear_layer(InfluenceMap.Layer.UNIT_INFLUENCE, 0.4)
				reference.clear_layer(InfluenceMap.Layer.UNIT_INFLUENCE, 0.4)
				optimized.write_stamp_to_layer(InfluenceMap.Layer.UNIT_INFLUENCE, stamp, mode)
				for y: int in range(stamp.size.y):
					for x: int in range(stamp.size.x):
						var cell: Vector2i = stamp.min_cell + Vector2i(x, y)
						var value: float = stamp.values[y * stamp.size.x + x]
						if reference.is_valid_cell(cell) and InfluenceMapLayerOps.should_write_stamp_value(value, mode):
							InfluenceMapLayerOps.write_layer_value(reference, InfluenceMap.Layer.UNIT_INFLUENCE, cell, value, mode)
				_check(optimized.get_layer_data_copy(InfluenceMap.Layer.UNIT_INFLUENCE) == reference.get_layer_data_copy(InfluenceMap.Layer.UNIT_INFLUENCE), "Batched stamp writes preserve clipped layer values for every supported mode")


func _reference_forecast(snapshot: InfluenceSnapshot, team: int, objective: Vector2i) -> PackedFloat32Array:
	var forecast: InfluenceMap = InfluenceMap.new()
	forecast.configure(snapshot.maps[team].bounds)
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	config.objective_hex = objective
	for source: ProjectionSource in ProjectionSourceBuilder.build_from_contacts(snapshot.get_contacts(team), config):
		LosInfluenceProjector.project_los_from_source(forecast, source, false, snapshot.los)
	return forecast.get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT)


func _forecast_capture(version: int, cache: InfluenceSnapshot.ForecastCache) -> InfluenceSnapshot:
	var snapshot: InfluenceSnapshot = InfluenceSnapshotBuilder.capture(version, controller.objectives_by_team, InfluenceMapController.KnowledgePolicy.OMNISCIENT, controller.create_default_weights())
	snapshot.forecast_cache = cache
	return snapshot


func _test_forecast_jobs() -> void:
	var cache: InfluenceSnapshot.ForecastCache = InfluenceSnapshot.ForecastCache.new()
	var snapshot: InfluenceSnapshot = _forecast_capture(400, cache)
	var objective: Vector2i = Vector2i(4, 2)
	var expected: PackedFloat32Array = _reference_forecast(snapshot, own.team, objective)
	var job: InfluenceSnapshot.ForecastJob = snapshot.request_forecast(own.team, objective)
	_check(snapshot.request_forecast(own.team, objective) == job, "Queries for the same captured objective share one forecast job")
	job.advance(Time.get_ticks_usec() - 1)
	_check(not job.completed and job.data.is_empty() and cache.entries.is_empty(), "An exhausted deadline leaves forecasts unpublished")
	var slices: int = 0
	var max_slice: int = 0
	while not job.completed and slices < 1000:
		var started: int = Time.get_ticks_usec()
		job.advance(started + 100)
		max_slice = maxi(max_slice, Time.get_ticks_usec() - started)
		slices += 1
	_check(job.completed and slices > 1 and max_slice < 10000, "Forecast projection yields across sources and visible hexes within its caller's deadline")
	_check(job.data == expected and job.projected_cells > 0, "Incremental forecast values match the original complete projection exactly")
	var repeated: InfluenceSnapshot = _forecast_capture(401, cache)
	var reused: InfluenceSnapshot.ForecastJob = repeated.request_forecast(own.team, objective)
	reused.advance(-1)
	_check(reused.reused and reused.projected_cells == 0 and reused.data == expected, "A later snapshot reuses an unchanged forecast without projecting any hexes")
	for field: String in ["hex", "confidence", "firepower", "effectiveness", "weapon_range"]:
		var changed: InfluenceSnapshot = _forecast_capture(402, cache)
		var contact: InfluenceContact = changed.get_contacts(own.team)[0]
		match field:
			"hex":
				contact.hex += Vector2i(1, 0)
			"confidence":
				contact.confidence *= 0.8
			"firepower":
				contact.firepower += 0.0000000001
			"effectiveness":
				contact.effectiveness *= 0.5
			"weapon_range":
				contact.weapon_range += 1
		var invalidated: InfluenceSnapshot.ForecastJob = changed.request_forecast(own.team, objective)
		invalidated.advance(-1)
		_check(not invalidated.reused and invalidated.data == _reference_forecast(changed, own.team, objective), "Changed contact " + field + " invalidates forecast reuse")
	var changed_los: InfluenceSnapshot = _forecast_capture(403, cache)
	changed_los.los = changed_los.los.duplicate(true)
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	config.objective_hex = objective
	var observer: Vector2i = ProjectionSourceBuilder.build_from_contacts(changed_los.get_contacts(own.team), config)[0].observer_hex
	var visible: Dictionary = changed_los.los[observer]
	var target: Vector2i = visible.keys()[0]
	visible[target]["target_cover"] = 3.0
	var los_job: InfluenceSnapshot.ForecastJob = changed_los.request_forecast(own.team, objective)
	los_job.advance(-1)
	_check(not los_job.reused and los_job.data == _reference_forecast(changed_los, own.team, objective), "Changed LOS records invalidate cached forecasts")
	var changing: InfluenceSnapshot = _forecast_capture(406, InfluenceSnapshot.ForecastCache.new())
	changing.los = changing.los.duplicate(true)
	var changing_job: InfluenceSnapshot.ForecastJob = changing.request_forecast(own.team, objective)
	while changing_job.projected_cells == 0 and not changing_job.completed:
		changing_job.advance(Time.get_ticks_usec() + 50)
	changing.los[observer][target]["hindrance"] = 4.0
	changing_job.advance(-1)
	_check(changing_job.completed and changing_job.data == _reference_forecast(changing, own.team, objective), "LOS edits during a forecast restart the job before publishing mixed inputs")
	var saved_cache: PackedFloat32Array = cache.entries.values()[0].duplicate()
	job.data[0] += 10.0
	_check(cache.entries.values()[0] == saved_cache, "Published forecast buffers cannot modify the shared cache")
	var second_objective: Vector2i = objective + Vector2i(1, 0)
	var other_job: InfluenceSnapshot.ForecastJob = repeated.request_forecast(own.team, second_objective)
	other_job.advance(-1)
	_check(not other_job.reused and other_job.data == _reference_forecast(repeated, own.team, second_objective), "Different objectives receive their own forecast")
	var cold: InfluenceSnapshot = _forecast_capture(404, InfluenceSnapshot.ForecastCache.new())
	var query: PositionQuery = _query(PositionProfile.Mode.ADVANCE)
	query.snapshot = cold
	query.objective_hex = objective
	var query_job: PositionQueryJob = PositionQueryJob.new()
	query_job.query = query
	for attempt: int in range(100):
		query_job.advance(Time.get_ticks_usec() + 100)
		if query_job.phase == PositionQueryJob.Phase.FORECAST or query_job.completed:
			break
	_check(not query_job.completed and query_job.phase == PositionQueryJob.Phase.FORECAST and query.forecast_data.is_empty(), "Position queries wait for a complete forecast before evaluating candidates")
	query_job.advance(-1)
	_check(query_job.completed and query.forecast_data == expected, "Waiting position queries resume with the complete forecast")
	var readiness_snapshot: InfluenceSnapshot = _forecast_capture(405, InfluenceSnapshot.ForecastCache.new())
	var area_job: DefenseAreaJob = readiness_snapshot.defense_area_job(own.team, objective, 3, 5)
	area_job.advance(-1)
	var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
	readiness.start(area_job.result, readiness_snapshot, own.team, [own, other], null, 3)
	_check(readiness.forecast_job == null and readiness.query.forecast_data.is_empty(), "Starting reserve readiness does not synchronously build forecasts")
	readiness.advance(Time.get_ticks_usec() - 1)
	_check(not readiness.completed and readiness.phase == DefenseReadinessJob.Phase.FORECAST, "Reserve readiness also waits within its caller's deadline")
	readiness.advance(-1)
	_check(readiness.completed and readiness.query.forecast_data == expected, "Reserve readiness resumes after its budgeted forecast completes")
	controller.forecast_cache.store(["fixture"], expected)
	controller.reset_for_match()
	_check(controller.forecast_cache.entries.is_empty(), "Match reset releases the shared forecast cache")
	controller.set_objective_for_team(own.team, Vector2i(3, 3))
	controller.set_objective_for_team(enemy.team, Vector2i(5, 3))
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


func _test_suppressed_hex_entry() -> void:
	var query: PositionQuery = _query(PositionProfile.Mode.ASSAULT)
	query.objective_hex = enemy.current_hex
	query.profile.enter_suppressed_enemy_hex = true
	var snapshot: InfluenceSnapshot = controller.snapshot
	var saved_contacts: Array[InfluenceContact] = snapshot.get_contacts(own.team)
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = enemy.current_hex
	contact.observed = true
	contact.weapon_range = 1
	snapshot.contacts[own.team] = [contact]
	var saved_state: UnitStates.MoraleState = enemy.stress_system.state
	var saved_stress: float = enemy.stress_system.S_eff
	enemy.stress_system.state = UnitStates.MoraleState.PINNED
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.target_hex == enemy.current_hex and result.path[-1] == enemy.current_hex, "Explicit close assault enters the suppressed defender's occupied hex")
	query.profile.enter_suppressed_enemy_hex = false
	_check(not PositionQueryService.can_enter_suppressed_enemy_hex(query, enemy.current_hex), "Ordinary position advice cannot bypass occupied-hex capacity")
	query.profile.enter_suppressed_enemy_hex = true
	enemy.surrendered = true
	_check(not PositionQueryService.can_enter_suppressed_enemy_hex(query, enemy.current_hex), "Surrendered squads cannot become close-combat assault targets")
	_check(PositionQueryService.approach_path_is_safe(query, [own.current_hex, enemy.current_hex]), "An observed surrendered squad does not block a rifle approach as a fresh defender")
	enemy.surrendered = false
	enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	enemy.stress_system.S_eff = 0.0
	_check(not PositionQueryService.can_enter_suppressed_enemy_hex(query, enemy.current_hex), "Fresh defenders require suppression before same-hex assault")
	enemy.stress_system.state = saved_state
	enemy.stress_system.S_eff = saved_stress
	snapshot.contacts[own.team] = saved_contacts
	query = _query(PositionProfile.Mode.ADVANCE)
	query.profile.minimum_cover = 0.1
	var map: InfluenceMap = snapshot.maps[own.team]
	var old_cover: PackedFloat32Array = map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER)
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 0.0)
	_check(not PositionQueryService.query_positions(query).is_valid(), "Rifle approach holds when every reachable destination lacks cover")
	map.set_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER, old_cover)


func _test_attack_overwatch() -> void:
	var first: UnitProbe = _unit(own.team, Vector2i(3, 3))
	var second: UnitProbe = _unit(own.team, Vector2i(3, 4))
	var rifle: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	var saved_state: UnitStates.MoraleState = enemy.stress_system.state
	var saved_stress: float = enemy.stress_system.S_eff
	enemy.stress_system.state = UnitStates.MoraleState.PINNED
	for unit: UnitProbe in [first, second]:
		_equip(unit, [rifle])
		unit.squad_type = Globals.SquadType.Rifle
		unit.combat_stats.combat_effectiveness = 1.0
		unit.squad_fire.unit = unit
		unit.squad_fire.target_unit = enemy
		unit.squad_fire.has_target_hex = true
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		unit.movement.is_moving = false
		var advice: PositionResult = PositionResult.new()
		advice.status = PositionResult.Status.ACCEPTED
		advice.unit = unit
		advice.target_hex = unit.current_hex
		advice.target_index = controller.snapshot.maps[own.team].cell_to_index(unit.current_hex)
		advice.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
		advice.features = {"cover": 0.5, "firing": 1.0}
		unit.position_advice = advice
		Globals.unit_visible_enemies[unit] = [enemy]
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.squads = [first, second]
	planner.current_order = MissionOrder.new()
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner.current_order.objective_hex = enemy.current_hex
	planner._build_combat_planning_requests(planner.squads)
	var maneuver: Unit = planner.attack_maneuver_squad
	var overwatch: Unit = second
	if maneuver == second:
		overwatch = first
	_check(maneuver != null and planner.attack_advance_released, "Established rifle fire support can release an attack without an MG")
	_check(planner._attack_mode_for_unit(maneuver) == PositionProfile.Mode.ADVANCE and planner._attack_mode_for_unit(overwatch) == PositionProfile.Mode.SUPPORT_BY_FIRE, "Two rifles facing a pinned defender assign only one to advance and retain the other on overwatch")
	for request: Dictionary in planner._planning_requests:
		var query: PositionQuery = request["query"]
		if query.unit == overwatch:
			_check(query.stability == planner.position_stability and query.profile.commitment_seconds == 8.0 and query.objective_hex == enemy.current_hex, "Rifle overwatch retains a stable position policy while targeting the pinned defender")
	planner._update_attack_roles([second, first])
	_check(planner.attack_maneuver_squad == maneuver, "Reordered squad evaluation preserves the moving rifle's assignment")
	maneuver.movement.is_moving = true
	var relocation: DefensePositionResult = DefensePositionResult.new()
	relocation.unit = overwatch
	relocation.status = PositionResult.Status.ACCEPTED
	relocation.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
	relocation.should_move = true
	relocation.target_hex = Vector2i(2, 4)
	relocation.target_index = controller.snapshot.maps[own.team].cell_to_index(relocation.target_hex)
	relocation.path = controller.snapshot.get_path(own.team, overwatch.current_hex, relocation.target_hex)
	planner._apply_position_results([relocation], "support_by_fire", null)
	var order_id: int = overwatch.action_controller.action_order_id
	planner._issue_order(overwatch)
	_check(overwatch.action_controller.action_order_id == order_id and not overwatch.movement.is_moving, "The last overwatch rifle retains its position during the other rifle's bound")
	_check(planner.reserved_hexes_by_squad[overwatch] == overwatch.current_hex, "Blocked overwatch relocation reserves the actual firing position")
	maneuver.movement.is_moving = false
	Globals.unit_visible_enemies[overwatch] = []
	_check(not planner._has_established_attack_support(planner.squads), "The moving rifle's old firing position cannot count as its own overwatch")
	var advance: DefensePositionResult = DefensePositionResult.new()
	advance.unit = maneuver
	advance.status = PositionResult.Status.ACCEPTED
	advance.profile_mode = PositionProfile.Mode.ADVANCE
	advance.target_hex = Vector2i(4, 3)
	advance.target_index = controller.snapshot.maps[own.team].cell_to_index(advance.target_hex)
	advance.should_move = true
	advance.path = controller.snapshot.get_path(own.team, maneuver.current_hex, advance.target_hex)
	planner._apply_position_results([advance], "advance", null)
	order_id = maneuver.action_controller.action_order_id
	planner._issue_order(maneuver)
	_check(maneuver.action_controller.action_order_id == order_id and not maneuver.movement.is_moving, "Cached advance advice cannot start a bound after overwatch loses the defender")
	planner._planning_requests.clear()
	planner._build_combat_planning_requests(planner.squads)
	for request: Dictionary in planner._planning_requests:
		var query: PositionQuery = request["query"]
		if query.unit == maneuver:
			_check(query.movement_radius == 0, "Loss of the overwatch firing lane holds the rifle at its forward position")
	Globals.unit_visible_enemies[overwatch] = [enemy]
	maneuver.current_hex = enemy.current_hex + Vector2i(-1, 0)
	overwatch.current_hex = enemy.current_hex + Vector2i(0, 1)
	overwatch.position_advice.target_hex = overwatch.current_hex
	_check(planner._attack_mode_for_unit(maneuver) == PositionProfile.Mode.ASSAULT and planner._attack_mode_for_unit(overwatch) == PositionProfile.Mode.SUPPORT_BY_FIRE, "Only the selected rifle enters close combat even when both rifles are adjacent to the pinned defender")
	overwatch.stress_system.state = UnitStates.MoraleState.PINNED
	planner._update_attack_roles(planner.squads)
	_check(planner.attack_maneuver_squad == null, "An incapacitated covering rifle blocks a new bound instead of sending the last capable rifle forward")
	overwatch.stress_system.state = UnitStates.MoraleState.NORMAL
	overwatch.surrendered = true
	planner._update_attack_roles(planner.squads)
	_check(planner.attack_maneuver_squad == null, "A surrendered rifle cannot satisfy the overwatch requirement")
	overwatch.surrendered = false
	planner.squads = [maneuver]
	planner._update_attack_roles(planner.squads)
	_check(planner.attack_maneuver_squad == null and planner._attack_mode_for_unit(maneuver) == PositionProfile.Mode.SUPPORT_BY_FIRE, "A lone rifle holds fire support rather than advancing without overwatch")
	enemy.stress_system.state = saved_state
	enemy.stress_system.S_eff = saved_stress
	for unit: UnitProbe in [first, second]:
		Globals.unit_visible_enemies.erase(unit)
		unit.squad_fire.free()
		unit.squad_fire = null
		unit.free()
	planner.free()


func _test_supported_close_assault() -> void:
	var attacker: Unit = _unit(own.team, Vector2i(5, 3))
	var gun: Unit = _unit(own.team, Vector2i(3, 3))
	var defender: Unit = _unit(enemy.team, Vector2i(6, 3))
	var rear: Unit = _unit(enemy.team, Vector2i(7, 3))
	gun.squad_type = Globals.SquadType.MG
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	defender.stress_system.S_eff = 40.0
	var weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for unit: Unit in [attacker, gun]:
		_equip(unit, [weapon])
		unit.squad_fire.unit = unit
		unit.combat_stats.combat_effectiveness = 1.0
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	Globals.unit_visible_enemies[attacker] = [defender]
	Globals.unit_visible_enemies[gun] = [defender, rear]
	gun.squad_fire.target_unit = rear
	gun.squad_fire.has_target_hex = true
	var saved_snapshot: InfluenceSnapshot = controller.snapshot
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.los = LOSHelper.los_lookup
	snapshot.routes[own.team] = saved_snapshot.routes[own.team]
	snapshot.point_ids[own.team] = saved_snapshot.point_ids[own.team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(saved_snapshot.maps[own.team].bounds)
	map.playable_cells = saved_snapshot.maps[own.team].playable_cells.duplicate()
	map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER, 0.5)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, rear.current_hex, 0.9)
	map.set_layer_value(InfluenceMap.Layer.THREAT, defender.current_hex, 1.0)
	snapshot.maps[own.team] = map
	for unit: Unit in [attacker, gun]:
		snapshot.positions[unit] = unit.current_hex
		snapshot.teams[unit] = own.team
	var contacts: Array[InfluenceContact] = []
	for unit: Unit in [defender, rear]:
		var contact: InfluenceContact = InfluenceContact.new()
		contact.unit = unit
		contact.hex = unit.current_hex
		contact.observed = true
		contact.firepower = 2.0
		contact.weapon_range = 5
		contacts.append(contact)
	snapshot.contacts[own.team] = contacts
	snapshot.defensive_contacts[own.team] = contacts
	controller.snapshot = snapshot
	var cover: PositionResult = PositionResult.new()
	cover.unit = gun
	cover.status = PositionResult.Status.ACCEPTED
	cover.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
	cover.target_hex = gun.current_hex
	cover.target_index = map.cell_to_index(gun.current_hex)
	cover.features = {"cover": 0.5, "firing": 1.0}
	gun.position_advice = cover
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.squads = [attacker, gun]
	planner.influence_map_controller = controller
	planner.current_order = MissionOrder.new()
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner.current_order.objective_hex = defender.current_hex
	planner._build_planning_requests(planner.squads)
	_check(not planner._are_visible_attack_defenders_suppressed(planner.squads) and planner._attack_mode_for_unit(attacker) == PositionProfile.Mode.ASSAULT, "Established fire support releases the adjacent close assault even while the covered rear defender remains fresh")
	var query: PositionQuery
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == attacker:
			query = request["query"]
	_check(query != null and query.profile.enter_suppressed_enemy_hex and not query.press_attack, "The rear defender keeps overwatch mandatory without vetoing a supported close assault")
	query.origin_hex = attacker.current_hex
	var path: Array[Vector2i] = [attacker.current_hex, defender.current_hex]
	_check(PositionQueryService.approach_path_is_safe(query, path), "The direct final step can enter a suppressed defender beside a fresh covered enemy")
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == defender.current_hex and advice.path == path, "The assault planner accepts the suppressed defender's hex instead of holding beside it")
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "assault")], "assault", null)
	planner._issue_order(attacker)
	_check(attacker.movement.is_moving and attacker.movement.target_hex == defender.current_hex and (attacker.action_controller as ActionProbe).intent == "assault", "The selected rifle executes close combat against the suppressed squad with the fresh defender behind it")
	planner.executor.cancel_all(true)
	query.profile.mode = PositionProfile.Mode.ADVANCE
	_check(not PositionQueryService.approach_path_is_safe(query, path), "Ordinary approach movement still avoids adjacency to fresh defenders")
	query.profile.mode = PositionProfile.Mode.ASSAULT
	_check(not PositionQueryService.approach_path_is_safe(query, [attacker.current_hex, rear.current_hex, defender.current_hex]), "The close-combat exception does not authorize longer routes through another defender")
	map.set_layer_value(InfluenceMap.Layer.THREAT, defender.current_hex, 100.0)
	_check(not PositionQueryService.query_positions(query).is_valid(), "Supported close combat still respects the incoming fire risk limit")
	map.set_layer_value(InfluenceMap.Layer.THREAT, defender.current_hex, 1.0)
	contacts[1].hex = defender.current_hex
	_check(not PositionQueryService.approach_path_is_safe(query, path), "A fresh defender in the same target hex still prevents the suppressed-only entry exception")
	contacts[1].hex = rear.current_hex
	defender.stress_system.state = UnitStates.MoraleState.NORMAL
	defender.stress_system.S_eff = 0.0
	_check(not PositionQueryService.approach_path_is_safe(query, path), "A recovered assault target no longer qualifies for suppressed close-combat entry")
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	defender.stress_system.S_eff = 40.0
	gun.stress_system.state = UnitStates.MoraleState.PINNED
	planner._issue_order(attacker)
	_check(not attacker.movement.is_moving, "Loss of covering fire blocks cached assault advice when the fresh rear defender remains")
	attacker.stress_system.state = UnitStates.MoraleState.PINNED
	_check(not planner.executor.execute(advice) and not attacker.movement.is_moving, "Pinned attackers cannot use the supported close-combat exception to move")
	controller.snapshot = saved_snapshot
	planner.free()
	for unit: Unit in [attacker, gun]:
		Globals.unit_visible_enemies.erase(unit)
		unit.squad_fire.free()
		unit.squad_fire = null
	for unit: Unit in [attacker, gun, defender, rear]:
		unit.free()


func _test_attack_support_recovery() -> void:
	var gun: Unit = _unit(own.team, Vector2i(3, 2))
	var rifle: Unit = _unit(own.team, Vector2i(3, 3))
	var observer: Unit = _unit(own.team, Vector2i(4, 4))
	var pinned: Unit = _unit(enemy.team, Vector2i(6, 3))
	var fresh: Unit = _unit(enemy.team, Vector2i(7, 4))
	gun.squad_type = Globals.SquadType.MG
	pinned.stress_system.state = UnitStates.MoraleState.PINNED
	var weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for unit: Unit in [gun, rifle, observer]:
		_equip(unit, [weapon])
		unit.combat_stats.combat_effectiveness = 1.0
		unit.squad_fire.unit = unit
		unit.squad_fire.target_unit = pinned
		unit.squad_fire.has_target_hex = true
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		Globals.unit_visible_enemies[unit] = [pinned]
	Globals.unit_visible_enemies[observer] = [pinned, fresh]
	var saved_snapshot: InfluenceSnapshot = controller.snapshot
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.version = saved_snapshot.version + 1
	snapshot.los = LOSHelper.los_lookup
	snapshot.routes[own.team] = saved_snapshot.routes[own.team]
	snapshot.point_ids[own.team] = saved_snapshot.point_ids[own.team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(saved_snapshot.maps[own.team].bounds)
	map.playable_cells = saved_snapshot.maps[own.team].playable_cells.duplicate()
	map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER, 0.5)
	snapshot.maps[own.team] = map
	for unit: Unit in [gun, rifle, observer]:
		snapshot.positions[unit] = unit.current_hex
		snapshot.teams[unit] = own.team
	var contacts: Array[InfluenceContact] = []
	for defender: Unit in [pinned, fresh]:
		var contact: InfluenceContact = InfluenceContact.new()
		contact.unit = defender
		contact.hex = defender.current_hex
		contact.observed = true
		contacts.append(contact)
	snapshot.contacts[own.team] = contacts
	snapshot.defensive_contacts[own.team] = contacts
	controller.snapshot = snapshot
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.squads = [gun, rifle, observer]
	planner.current_order = MissionOrder.new()
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner.current_order.objective_hex = pinned.current_hex
	planner.attack_maneuver_squad = rifle
	planner._build_planning_requests(planner.squads)
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == gun:
			_check(not request["query"].require_live_support_target and request["query"].profile.commitment_seconds == 16.0, "Initial MG fire support establishes a covered lane with a stationary weapon commitment")
	planner._planning_requests.clear()
	planner.attack_approach_started = true
	planner._build_planning_requests(planner.squads)
	var support: PositionQuery
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == gun:
			support = request["query"]
	_check(support.objective_hex == fresh.current_hex and support.require_live_support_target and support.stability == planner.position_stability, "MG reassesses a lost priority firing lane without globally discarding movement commitments")
	support.has_accepted_target = true
	support.accepted_target = gun.current_hex
	support.accepted_context = support.context_key()
	support.accepted_at = snapshot.captured_at
	support.profile.commitment_seconds = INF
	var advice: PositionResult = PositionQueryService.query_positions(support)
	_check(advice.is_valid() and advice.should_move and advice.rejection_reasons[map.cell_to_index(gun.current_hex)] == "firing", "A theoretical LOS lane without a live priority target cannot retain an idle MG even with an old infinite commitment")
	gun.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	var establishing: PositionResult = PositionQueryService.query_positions(support)
	_check(establishing.eligibility[map.cell_to_index(gun.current_hex)] == 1, "MG positioning allows setup and target acquisition before declaring a new firing position idle")
	planner._planning_requests.clear()
	planner._build_planning_requests(planner.squads)
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == gun:
			_check(request["query"].profile.commitment_seconds == 16.0, "An establishing MG keeps its stationary weapon commitment instead of restarting before it can fire")
	gun.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	snapshot.los = snapshot.los.duplicate(true)
	snapshot.los[gun.current_hex].erase(pinned.current_hex)
	Globals.unit_visible_enemies[gun] = [fresh]
	support.objective_hex = pinned.current_hex
	var active_support: PositionResult = PositionQueryService.query_positions(support)
	_check(active_support.eligibility[map.cell_to_index(gun.current_hex)] == 1, "MG suppression of another live fresh defender stays useful when the assigned target is outside its firing lane")
	snapshot.los = LOSHelper.los_lookup
	Globals.unit_visible_enemies[gun] = [pinned]
	support.objective_hex = fresh.current_hex
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "support_by_fire")], "support_by_fire", null)
	planner._issue_order(gun)
	_check(gun.movement.is_moving and gun.movement.target_hex == advice.target_hex, "The stalled MG starts a new movement order to restore useful suppression")
	planner.executor.cancel_all(true)
	gun.current_hex = advice.target_hex
	gun.position = ground.map_to_local(gun.current_hex)
	snapshot.positions[gun] = gun.current_hex
	gun.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	gun.position_advice = advice
	gun.squad_fire.target_unit = null
	gun.squad_fire.has_target_hex = false
	pinned.surrendered = true
	fresh.surrendered = true
	for unit: Unit in planner.squads:
		Globals.unit_visible_enemies[unit] = []
	_check(not planner._has_known_attack_defenders(planner.squads) and planner._has_established_attack_support(planner.squads), "After observed surrender, stationary MG overwatch remains valid without a fire target")
	planner._planning_requests.clear()
	planner._build_planning_requests(planner.squads)
	var advance: PositionQuery
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == rifle:
			advance = request["query"]
	_check(planner.attack_advance_released and advance.movement_radius > 0 and advance.profile.minimum_cover == 0.0, "The rifle resumes occupation of a cleared objective with overwatch instead of waiting for a nonexistent suppression target")
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, pinned.current_hex, 0.0)
	advice = PositionQueryService.query_positions(advance)
	_check(advice.is_valid() and advice.target_hex == pinned.current_hex, "An open cleared objective and an observed surrendered defender do not prevent rifle occupation")
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "advance")], "advance", null)
	planner._issue_order(rifle)
	_check(rifle.movement.is_moving and rifle.movement.target_hex == pinned.current_hex, "A cleared-objective advance starts actual rifle movement while the MG remains on overwatch")
	planner.executor.cancel_all(true)
	contacts[1].observed = false
	fresh.current_hex = Vector2i(8, 6)
	_check(planner._has_known_attack_defenders(planner.squads) and not planner._has_established_attack_support(planner.squads), "An unobserved surrender cannot clear the attack's remembered defender or release unsupported movement")
	_check(planner._attack_support_objective(planner.squads) == contacts[1].hex, "Support searches the last known defender position without reading its hidden live location")
	controller.snapshot = saved_snapshot
	planner.free()
	for unit: Unit in [gun, rifle, observer]:
		Globals.unit_visible_enemies.erase(unit)
		unit.squad_fire.free()
		unit.squad_fire = null
	for unit: Unit in [gun, rifle, observer, pinned, fresh]:
		unit.free()


func _test_attack_pressure_and_following() -> void:
	var gun: UnitProbe = _unit(own.team, Vector2i(1, 5))
	var headquarters: UnitProbe = _unit(own.team, Vector2i(0, 6))
	var pinned: UnitProbe = _unit(own.team, Vector2i(6, 3))
	var first: UnitProbe = _unit(own.team, Vector2i(5, 3))
	var second: UnitProbe = _unit(own.team, Vector2i(6, 4))
	var defender: UnitProbe = _unit(enemy.team, pinned.current_hex)
	var fresh: UnitProbe = _unit(enemy.team, Vector2i(8, 6))
	gun.squad_type = Globals.SquadType.MG
	headquarters.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	headquarters.leader_aura.aura_radius_hexes = 1
	pinned.stress_system.state = UnitStates.MoraleState.PINNED
	pinned.in_close_combat = true
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	defender.stress_system.S_eff = 80.0
	var weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for unit: UnitProbe in [gun, pinned, first, second]:
		unit.combat_stats.combat_effectiveness = 1.0
		_equip(unit, [weapon])
		unit.squad_fire.unit = unit
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		Globals.unit_visible_enemies[unit] = [defender]
	var saved_snapshot: InfluenceSnapshot = controller.snapshot
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.version = saved_snapshot.version + 1
	snapshot.los = LOSHelper.los_lookup.duplicate(true)
	snapshot.routes[own.team] = saved_snapshot.routes[own.team]
	snapshot.point_ids[own.team] = saved_snapshot.point_ids[own.team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(saved_snapshot.maps[own.team].bounds)
	map.playable_cells = saved_snapshot.maps[own.team].playable_cells.duplicate()
	map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER, 0.5)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, gun.current_hex, 0.95)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, headquarters.current_hex, 0.95)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, defender.current_hex, 0.0)
	snapshot.maps[own.team] = map
	for unit: Unit in [gun, headquarters, pinned, first, second]:
		snapshot.positions[unit] = unit.current_hex
		snapshot.teams[unit] = own.team
		snapshot.support_units[unit] = {"headquarters": unit == headquarters, "company": unit.company,
			"platoon": unit.platoon, "commander": headquarters, "company_hq": false,
			"members": unit.members_alive, "radius": unit.leader_aura.aura_radius_hexes, "need": 0.1, "surrendered": false}
	snapshot.support_units[pinned as Unit]["need"] = 1.5
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = defender
	contact.hex = defender.current_hex
	contact.observed = true
	contact.confidence = 1.0
	contact.firepower = 1.0
	contact.effectiveness = 0.35
	contact.weapon_range = 8
	snapshot.contacts[own.team] = [contact]
	snapshot.defensive_contacts[own.team] = [contact]
	controller.snapshot = snapshot
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.squads = [gun, headquarters, pinned, first, second]
	planner.current_order = MissionOrder.new()
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner.current_order.objective_hex = defender.current_hex
	planner.attack_maneuver_squad = pinned
	planner.attack_approach_started = true
	_check(not planner._has_established_attack_support(planner.squads) and not planner._has_pressing_attack(planner.squads), "Exactly 80 percent defender stress still requires established overwatch")
	defender.stress_system.S_eff = 81.0
	planner._build_planning_requests(planner.squads)
	_check(planner.attack_advance_released and not planner._has_established_attack_support(planner.squads), "Stress above 80 percent releases a fresh rifle attack even without established overwatch")
	_check(planner._attack_mode_for_unit(first) == PositionProfile.Mode.ASSAULT and planner._attack_mode_for_unit(second) == PositionProfile.Mode.ASSAULT, "Both eligible adjacent rifles press an overwhelmed defender while the original attacker is pinned")
	var assault: PositionQuery
	var support: PositionQuery
	var escort: PositionQuery
	for request: Dictionary in planner._planning_requests:
		var query: PositionQuery = request["query"]
		if query.unit == first:
			assault = query
		elif query.unit == gun:
			support = query
		elif query.unit == headquarters:
			escort = query
	_check(assault.press_attack and assault.movement_radius > 0 and assault.profile.enter_suppressed_enemy_hex, "The pressure exception preserves a real same-hex assault instead of freezing movement for missing overwatch")
	map.clear_layer(InfluenceMap.Layer.THREAT, 100.0)
	var advice: PositionResult = PositionQueryService.query_positions(assault)
	_check(advice.is_valid() and advice.target_hex == defender.current_hex, "An eligible rifle can join the overwhelmed defender's hex despite a pinned friendly already there")
	_check(advice.features.get("incoming", 1.0) < 0.9 and advice.features.get("peak_exposure", 1.0) < 0.9, "Observed overwhelming stress overrides an older unsuppressed threat field for both the route and assault destination")
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "assault")], "assault", null)
	planner._issue_order(first)
	_check(first.movement.is_moving and first.movement.target_hex == defender.current_hex, "The fresh rifle executes its assault without an overwatch unit")
	var pinned_advice: PositionResult = PositionResult.new()
	pinned_advice.status = PositionResult.Status.ACCEPTED
	pinned_advice.unit = pinned
	pinned_advice.profile_mode = PositionProfile.Mode.ADVANCE
	pinned_advice.target_hex = first.current_hex
	pinned_advice.target_index = map.cell_to_index(first.current_hex)
	pinned_advice.should_move = true
	pinned_advice.path = snapshot.get_path(own.team, pinned.current_hex, first.current_hex)
	_check(not planner.executor.execute(pinned_advice) and not pinned.movement.is_moving, "The overwhelmed-defender exception never releases movement of the pinned attacker")
	defender.stress_system.S_eff = 80.0
	planner._issue_order(first)
	_check(not first.movement.is_moving and not planner.accepted_positions.has(first), "Defender recovery invalidates a cached unsupported assault before execution")
	defender.stress_system.S_CAP = 200.0
	defender.stress_system.S_eff = 81.0
	_check(not TacticalPositionExecutor.is_overwhelmed(defender), "Pressure uses the defender's stress percentage rather than a fixed 80-point threshold")
	defender.stress_system.S_CAP = 100.0
	defender.stress_system.S_eff = 90.0
	var fresh_contact: InfluenceContact = InfluenceContact.new()
	fresh_contact.unit = fresh
	fresh_contact.hex = fresh.current_hex
	fresh_contact.observed = true
	snapshot.defensive_contacts[own.team].append(fresh_contact)
	_check(not planner._has_pressing_attack(planner.squads), "A second defender covering the overwhelmed squad prevents abandoning overwatch")
	fresh_contact.observed = false
	fresh.stress_system.S_eff = 100.0
	_check(not planner._has_pressing_attack(planner.squads), "A remembered defender's hidden stress cannot authorize an unsupported assault")
	snapshot.los[fresh.current_hex] = {}
	_check(planner._has_pressing_attack(planner.squads), "A separate remembered defender without LOS to the assault does not block exploitation of the overwhelmed squad")
	snapshot.los[fresh.current_hex][Vector2i(3, 4)] = {}
	_check(not PositionQueryService.press_attack_path_is_safe(snapshot, own.team, gun.current_hex, [gun.current_hex, Vector2i(3, 4), first.current_hex]), "An unsupported assault cannot cross another known defender's firing lane")
	snapshot.defensive_contacts[own.team].erase(fresh_contact)
	defender.stress_system.S_eff = 55.0
	map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	_check(support.has_support_anchor and support.support_anchor_hex == pinned.current_hex and support.profile.commitment_seconds == 16.0, "A lagging MG follows the forward rifle through a stable support policy rather than disabling its commitment")
	gun.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	planner._planning_requests.clear()
	planner._build_planning_requests(planner.squads)
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == gun:
			_check(request["query"].profile.commitment_seconds == 16.0, "A lagging MG still finishes its bound and setup before reconsidering the next forward support position")
	gun.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	support.has_accepted_target = true
	support.accepted_target = gun.current_hex
	support.accepted_context = support.context_key()
	support.accepted_at = snapshot.captured_at
	advice = PositionQueryService.query_positions(support)
	_check(advice.is_valid() and advice.should_move and LOSHelper.get_hex_distance(advice.target_hex, pinned.current_hex) < LOSHelper.get_hex_distance(gun.current_hex, pinned.current_hex), "A useful rear firing lane does not prevent the MG moving into a closer covered support position")
	defender.stress_system.S_eff = 90.0
	planner._apply_position_results([DefensePositionAnalyzer.adapt_result(advice, null, "support_by_fire")], "support_by_fire", null)
	planner._issue_order(gun)
	_check(gun.movement.is_moving and gun.movement.target_hex == advice.target_hex, "The last MG can close the support gap during an attack on an overwhelmed defender")
	planner.executor.cancel_all(true)
	defender.stress_system.S_eff = 55.0
	support.movement_radius = 2
	for cell: Vector2i in snapshot.los:
		snapshot.los[cell].erase(defender.current_hex)
	advice = PositionQueryService.query_positions(support)
	_check(advice.is_valid() and advice.should_move and advice.features["firing"] == 0.0 and advice.features["support_advance"] > 0.0 and advice.features["cover"] >= 0.1, "MG can make a covered intermediate bound when the next useful firing lane lies beyond its planning radius")
	_check(escort.assault_support_squad == pinned, "HQ continues rally support of the pinned forward attacker when other rifles take over the assault")
	escort.movement_radius = 2
	escort.has_accepted_target = true
	escort.accepted_target = headquarters.current_hex
	HqSupportPositionPolicy.prepare(escort)
	escort.accepted_context = escort.context_key()
	escort.accepted_at = snapshot.captured_at
	advice = PositionQueryService.query_positions(escort)
	_check(advice.is_valid() and advice.should_move and not advice.features["support_priority_covered"] and advice.features["support_priority_progress"] > 0.0, "HQ leaves rear cover and takes an intermediate step toward a stressed squad beyond one planning radius")
	_check(LOSHelper.get_hex_distance(advice.target_hex, pinned.current_hex) < LOSHelper.get_hex_distance(headquarters.current_hex, pinned.current_hex), "Intermediate HQ movement closes the leadership gap to the forward squad")
	_check(planner.executor.execute(advice) and headquarters.movement.is_moving, "Intermediate HQ support advice starts actual movement")
	planner.executor.cancel_all(true)
	controller.snapshot = saved_snapshot
	planner.free()
	for unit: UnitProbe in [gun, pinned, first, second]:
		Globals.unit_visible_enemies.erase(unit)
		unit.squad_fire.free()
		unit.squad_fire = null
	for unit: UnitProbe in [gun, headquarters, pinned, first, second, defender, fresh]:
		unit.free()


func _stability_query(unit: Unit, snapshot: InfluenceSnapshot, stability: PlatoonPositionStability, now: float, mode: PositionProfile.Mode = PositionProfile.Mode.SUPPORT_BY_FIRE) -> PositionQuery:
	var query: PositionQuery = PositionQuery.new()
	query.unit = unit
	query.team = unit.team
	query.snapshot = snapshot
	query.use_defense_area = false
	query.objective_hex = Vector2i(6, 3)
	query.mission_objective_hex = query.objective_hex
	query.profile = PositionProfile.for_mode(mode)
	query.profile.minimum_cover = 0.1
	query.profile.cover_weight = 10.0
	query.profile.firing_weight = 0.0
	query.movement_radius = 2
	query.stability = stability
	query.stability_time = now
	return query


func _test_position_stability() -> void:
	var first: UnitProbe = _unit(own.team, Vector2i(2, 3))
	var second: UnitProbe = _unit(own.team, Vector2i(2, 5))
	var headquarters: UnitProbe = _unit(own.team, Vector2i(1, 4))
	second.squad_type = Globals.SquadType.MG
	headquarters.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	headquarters.leader_aura.aura_radius_hexes = 1
	var weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for unit: Unit in [first, second]:
		_equip(unit, [weapon])
		unit.squad_fire.unit = unit
		unit.combat_stats.combat_effectiveness = 1.0
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	headquarters.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.los = LOSHelper.los_lookup
	snapshot.routes[own.team] = controller.snapshot.routes[own.team]
	snapshot.point_ids[own.team] = controller.snapshot.point_ids[own.team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(controller.snapshot.maps[own.team].bounds)
	map.playable_cells = controller.snapshot.maps[own.team].playable_cells.duplicate()
	map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER, 0.5)
	snapshot.maps[own.team] = map
	for unit: Unit in [first, second, headquarters]:
		snapshot.positions[unit] = unit.current_hex
		snapshot.teams[unit] = own.team
		snapshot.support_units[unit] = {"headquarters": unit == headquarters, "company": unit.company,
			"platoon": unit.platoon, "commander": headquarters, "company_hq": false,
			"members": unit.members_alive, "radius": unit.leader_aura.aura_radius_hexes, "need": 0.1, "surrendered": false}
	var stability: PlatoonPositionStability = PlatoonPositionStability.new()
	var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
	for unit: Unit in [first, second]:
		var initial: PositionQuery = _stability_query(unit, snapshot, stability, 0.0)
		initial.movement_radius = 0
		var result: PositionResult = PositionQueryService.query_positions(initial)
		if not result.is_valid():
			print("Initial stability support: ", unit.squad_type, " at ", unit.current_hex, " ", result.reason, " ", result.rejections)
		_check(result.is_valid() and not result.should_move, "Stable support begins with a useful accepted position")
		_check(executor.execute(result), "Stable support owns its initial holding order")
		stability.accepted(result, 0.0)
	_check(not stability.support_lane_failed(second, Vector2i(6, 3), 0.5), "A newly established support squad gets time to acquire an actual target")
	_check(stability.support_lane_failed(second, Vector2i(6, 3), 2.5), "An idle settled support position becomes a failed task before the first rifle advance")
	Globals.unit_visible_enemies[second] = [enemy]
	_check(not stability.support_lane_failed(second, Vector2i(6, 3), 3.0), "Acquiring a useful live defender restores the support position's task")
	Globals.unit_visible_enemies.erase(second)
	var initial_headquarters: PositionQuery = _stability_query(headquarters, snapshot, stability, 0.0, PositionProfile.Mode.HQ_SUPPORT)
	initial_headquarters.movement_radius = 0
	var headquarters_position: PositionResult = PositionQueryService.query_positions(initial_headquarters)
	_check(headquarters_position.is_valid() and executor.execute(headquarters_position), "Headquarters initially owns a useful safe position")
	stability.accepted(headquarters_position, 0.0)
	var query: PositionQuery = _stability_query(first, snapshot, stability, 1.0)
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(not advice.should_move, "Equal support positions do not initiate optional relocation")
	Globals.unit_visible_enemies[first] = [enemy]
	var retargeted: PositionQuery = _stability_query(first, snapshot, stability, 2.0)
	retargeted.objective_hex = Vector2i(8, 0)
	retargeted.require_live_support_target = true
	var useful_lane: PositionResult = PositionQueryService.query_positions(retargeted)
	_check(useful_lane.is_valid() and not useful_lane.should_move and useful_lane.target_hex == first.current_hex and useful_lane.features["firing"] > 0.0, "A shifted distant fire priority cannot dislodge support that still suppresses another useful live defender")
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(4, 3), 0.95)
	query.stability_time = 20.0
	advice = PositionQueryService.query_positions(query)
	_check(not advice.should_move and advice.proposed_hex != first.current_hex, "A substantial new improvement must persist before leaving a useful firing position")
	query.stability_time = 22.0
	_check(not PositionQueryService.query_positions(query).should_move, "Two seconds of optional improvement cannot start a relocation")
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(4, 3), 0.5)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(3, 3), 0.95)
	query.stability_time = 23.0
	_check(not PositionQueryService.query_positions(query).should_move, "Changing the preferred optional destination restarts its persistence requirement")
	var optional_hq: PositionQuery = _stability_query(headquarters, snapshot, stability, 23.0, PositionProfile.Mode.HQ_SUPPORT)
	optional_hq.profile.cover_weight = 30.0
	PositionQueryService.query_positions(optional_hq)
	query.stability_time = 25.0
	_check(not PositionQueryService.query_positions(query).should_move, "Alternating improvements cannot bypass the persistence requirement")
	query.stability_time = 26.0
	advice = PositionQueryService.query_positions(query)
	_check(advice.should_move and advice.features["movement_kind"] == "optional", "A stable substantial improvement can relocate a settled support squad")
	_check(executor.execute(advice), "The authorized optional relocation starts a real order")
	first.movement.path_hexes = advice.path.duplicate()
	first.movement.path_index = 0
	stability.accepted(advice, 26.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, Vector2i(4, 5), 0.95)
	var peer: PositionQuery = _stability_query(second, snapshot, stability, 20.0)
	peer.reservations[first] = advice.target_hex
	PositionQueryService.query_positions(peer)
	peer.stability_time = 27.0
	var peer_advice: PositionResult = PositionQueryService.query_positions(peer)
	_check(not peer_advice.should_move and peer_advice.reason.contains("another combat squad"), "Only one combat squad can perform optional repositioning at a time")
	optional_hq.stability_time = 27.0
	var hq_relocation: PositionResult = PositionQueryService.query_positions(optional_hq)
	_check(hq_relocation.should_move and hq_relocation.features["movement_kind"] == "optional" and executor.execute(hq_relocation), "Independent HQ repositioning can accompany a combat squad's optional move")
	stability.accepted(hq_relocation, 27.0)
	_check(stability.optional_mover == first, "Independent HQ movement cannot steal the combat relocation slot")
	executor.cancel(headquarters, true)
	stability.forget(headquarters)
	var alternate: PositionQuery = _stability_query(first, snapshot, stability, 28.0, PositionProfile.Mode.ADVANCE)
	alternate.objective_hex = Vector2i(8, 0)
	alternate.deliberate_movement = true
	var continuing: PositionResult = PositionQueryService.query_positions(alternate)
	_check(continuing.target_hex == advice.target_hex and continuing.path == advice.path and not continuing.should_move and continuing.profile_mode == PositionProfile.Mode.SUPPORT_BY_FIRE, "A changed tactical role cannot replace a safe accepted destination or route during movement")
	var order_id: int = first.action_controller.action_order_id
	_check(executor.execute(continuing) and first.action_controller.action_order_id == order_id, "Refreshing accepted movement preserves the order instead of restarting it")
	stability.accepted(continuing, 28.0)
	var shifted_fire: PositionQuery = _stability_query(first, snapshot, stability, 29.0)
	shifted_fire.objective_hex = Vector2i(7, 2)
	var original_context: String = shifted_fire.context_key()
	shifted_fire.objective_hex = Vector2i(8, 2)
	_check(shifted_fire.context_key() == original_context, "Changing support fire targets does not reset the position commitment context")
	first.current_hex = advice.target_hex
	first.position = ground.map_to_local(first.current_hex)
	snapshot.positions[first as Unit] = first.current_hex
	first.movement.is_moving = false
	first.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	stability.observe([first, second, headquarters], 29.0)
	alternate.stability_time = 30.0
	continuing = PositionQueryService.query_positions(alternate)
	_check(continuing.target_hex == first.current_hex and continuing.features.get("finishing_accepted_order", false), "Accepted positioning remains locked throughout setup")
	peer.stability_time = 30.0
	_check(not PositionQueryService.query_positions(peer).should_move, "The next optional squad waits for establishment, not just arrival")
	map.set_layer_value(InfluenceMap.Layer.THREAT, first.current_hex, 100.0)
	var unsafe: PositionQuery = _stability_query(first, snapshot, stability, 31.0)
	var escape: PositionResult = PositionQueryService.query_positions(unsafe)
	_check(escape.is_valid() and escape.should_move and escape.target_hex != first.current_hex and escape.features["movement_kind"] == "necessary", "Actual danger can interrupt setup and authorize an immediate necessary relocation")
	map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	first.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	stability.observe([first, second, headquarters], 32.0)
	_check(stability.optional_mover == null, "Completion of setup releases the optional relocation slot")
	peer.stability_time = 32.0
	_check(PositionQueryService.query_positions(peer).should_move, "The next squad can reconsider its persistent improvement after the first establishes")
	stability.release_unstarted_optional()
	query.stability_time = 39.0
	_check(stability.minimum_hold_active(query), "The minimum holding period begins after setup, not when movement was ordered")
	query.stability_time = 40.0
	_check(not stability.minimum_hold_active(query), "A rifle completes its minimum holding period eight seconds after establishment")
	second.squad_type = Globals.SquadType.Rifle
	for unit: Unit in [first, second]:
		var attack: PositionQuery = _stability_query(unit, snapshot, stability, 33.0, PositionProfile.Mode.ADVANCE)
		attack.objective_hex = Vector2i(7, 0)
		attack.movement_radius = 4
		attack.profile.progress_weight = 12.0
		attack.profile.cover_weight = 0.8
		attack.deliberate_movement = true
		var advancing: PositionResult = PositionQueryService.query_positions(attack)
		if not advancing.should_move:
			print("Stable deliberate move: ", unit.squad_type, " ", advancing.reason, " target ", advancing.target_hex, " ", advancing.rejections)
		_check(advancing.should_move and advancing.features["movement_kind"] == "attack", "Deliberate attack movement bypasses optional relocation serialization and holding periods")
	var hq_stability: PlatoonPositionStability = PlatoonPositionStability.new()
	var escort: PositionQuery = _stability_query(headquarters, snapshot, hq_stability, 0.0, PositionProfile.Mode.HQ_SUPPORT)
	escort.profile.support_assault_squads = true
	escort.profile.progress_weight = 12.0
	snapshot.support_units[first as Unit]["need"] = 0.9
	snapshot.support_units[second as Unit]["need"] = 0.8
	HqSupportPositionPolicy.prepare(escort)
	_check(escort.support_priority_squad == first, "HQ initially chooses the squad with the strongest support need")
	escort.movement_radius = 0
	var initial_hq: PositionResult = PositionQueryService.query_positions(escort)
	_check(initial_hq.is_valid() and executor.execute(initial_hq), "HQ accepts its current safe support position before following")
	hq_stability.accepted(initial_hq, 0.0)
	escort.movement_radius = 2
	escort.stability_time = 1.0
	_check(not PositionQueryService.query_positions(escort).should_move, "HQ does not follow the first transient loss of leadership coverage")
	escort.stability_time = 2.0
	_check(not PositionQueryService.query_positions(escort).should_move, "HQ waits for persistent loss of leadership coverage")
	escort.stability_time = 3.0
	var following_hq: PositionResult = PositionQueryService.query_positions(escort)
	_check(following_hq.should_move and following_hq.features["movement_kind"] == "follow" and following_hq.features["support_priority_covered"], "Persistent loss of leadership coverage releases useful HQ following during its holding period")
	snapshot.support_units[first as Unit]["need"] = 0.8
	snapshot.support_units[second as Unit]["need"] = 0.9
	escort.stability_time = 4.0
	HqSupportPositionPolicy.prepare(escort)
	_check(escort.support_priority_squad == first, "Small stress changes cannot toggle the HQ support assignment")
	snapshot.support_units[second as Unit]["need"] = 1.4
	escort.stability_time = 5.0
	HqSupportPositionPolicy.prepare(escort)
	_check(escort.support_priority_squad == first, "A new HQ priority must persist before replacing its support assignment")
	escort.stability_time = 7.0
	HqSupportPositionPolicy.prepare(escort)
	_check(escort.support_priority_squad == second, "A substantial persistent support need can change the HQ assignment")
	headquarters.movement.is_moving = true
	snapshot.support_units[first as Unit]["need"] = 2.0
	escort.stability_time = 9.0
	HqSupportPositionPolicy.prepare(escort)
	_check(escort.support_priority_squad == second, "HQ retains its supported squad through an accepted bound")
	headquarters.movement.is_moving = false
	var anchor: Unit = stability.choose_support_anchor(first, [first, second], Vector2i(7, 3), 40.0)
	second.current_hex = Vector2i(7, 2)
	second.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	_check(stability.choose_support_anchor(second, [first, second], Vector2i(7, 3), 41.0) == anchor, "MG and HQ retain the support anchor while another rifle finishes its bound")
	second.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	stability.choose_support_anchor(second, [first, second], Vector2i(7, 3), 42.0)
	_check(stability.choose_support_anchor(second, [first, second], Vector2i(7, 3), 44.0) == second, "A clearly more forward established rifle can become the support anchor after persistence")
	executor.cancel_all()
	for unit: Unit in [first, second]:
		Globals.unit_visible_enemies.erase(unit)
		unit.squad_fire.free()
		unit.squad_fire = null
	for unit: Unit in [first, second, headquarters]:
		unit.free()


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
		_check(_planned_role(planner, tripod) == "hq_support" and _planned_role(planner, bipod) == "guard_objective", "An explicit HQ policy keeps headquarters supporting and combat equipment guarding")
		tripod.squad_type = Globals.SquadType.Rifle
		planner.current_order.reserve_policy = MissionOrder.ReservePolicy.KEEP_ONE_SQUAD_IF_POSSIBLE
		area.approaches.append({"id": 3, "priority": 1.0, "response_distances": response})
		planner._planning_requests.clear()
		planner._build_sector_requests([rifle, tripod, spare])
		_check(_planned_role(planner, tripod) == "guard_objective" and _planned_role(planner, rifle) == "reserve" and _planned_role(planner, spare) == "defend_sector", "A second significant front preserves a protected mobile reserve and the MG anchor")
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
	var saved_visible: Array = Globals.unit_visible_enemies.get(own, []).duplicate()
	Globals.unit_visible_enemies[own] = [enemy]
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
	_check(own.commanded.has(Globals.UnitCmd.FIRE_AT_UNIT) and not own.commanded.has(Globals.UnitCmd.FIRE_AT_HEX), "Support intent targets a visible active defender after arrival")
	_check(own.attackState == Unit.AttackState.MANUAL_TRACK, "Support fire retains the selected suppression target between planner updates")
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
	Globals.unit_visible_enemies[own] = saved_visible


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
	_check(controller.threat_axis_composites_by_team.is_empty(), "Axis diagnostics stay lazy when a new snapshot is published")
	var composites: Array[ThreatAxisComposite] = controller.get_threat_axis_composites_for_team(own.team)
	var cached: Array[ThreatAxisComposite] = controller.get_threat_axis_composites_for_team(own.team)
	_check(cached.size() == composites.size() and cached[0] == composites[0] and not controller.threat_axis_composites_by_team.has(enemy.team), "Axis diagnostics reuse the requested team cache without computing the other team")
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


func _test_headquarters_support() -> void:
	var saved_hex: Vector2i = own.current_hex
	var saved_other: Vector2i = other.current_hex
	add_child(controller)
	var stressed: UnitProbe = _unit(own.team, Vector2i(7, 5))
	var foreign: UnitProbe = _unit(own.team, Vector2i(3, 4))
	foreign.platoon = 99
	foreign.stress_system.S_eff = 100.0
	foreign.stress_system.state = UnitStates.MoraleState.PANIC
	own.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	own.current_hex = Vector2i(4, 3)
	own.position = ground.map_to_local(own.current_hex)
	other.current_hex = Vector2i(1, 1)
	other.stress_system.S_eff = 0.0
	other.stress_system.state = UnitStates.MoraleState.NORMAL
	stressed.stress_system.S_eff = 90.0
	stressed.stress_system.state = UnitStates.MoraleState.PANIC
	var original_size: int = stressed.original_size
	stressed.original_size = 0
	_check(HqSupportNeedLayer.get_squad_support_need(stressed) > 1.0, "Unknown original roster size does not suppress urgent stress support")
	stressed.original_size = original_size
	for mirrored_team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		own.team = mirrored_team
		other.team = mirrored_team
		stressed.team = mirrored_team
		foreign.team = mirrored_team
		enemy.team = Globals.get_enemy_team(mirrored_team) as Globals.Team
		_publish()
		var snapshot: InfluenceSnapshot = controller.snapshot
		snapshot.contacts[own.team] = []
		snapshot.defensive_contacts[own.team] = []
		var map: InfluenceMap = snapshot.maps[own.team]
		map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER)
		map.clear_layer(InfluenceMap.Layer.THREAT)
		var quiet: Vector2i = Vector2i(2, 1)
		var urgent: Vector2i = Vector2i(6, 5)
		var concealed: Vector2i = Vector2i(6, 4)
		for cell: Vector2i in [quiet, urgent, own.current_hex]:
			map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 0.6)
		var query: PositionQuery = PositionQuery.new()
		query.unit = own
		query.team = own.team
		query.snapshot = snapshot
		query.objective_hex = Vector2i(0, 6)
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.target_hex == urgent, "Headquarters chooses cover beside its most stressed squad for either team")
		_check(result.profile_mode == PositionProfile.Mode.HQ_SUPPORT and result.features.get("firing", -1.0) == 0.0 and result.features.get("objective_coverage", -1.0) == 0.0, "Headquarters earns support utility without firing or capture utility")
		_check(result.features.get("supported_squads", []).has(stressed) and query.support_radius == own.leader_aura.aura_radius_hexes, "Support uses the actual leadership aura radius")
		query.has_accepted_target = true
		query.accepted_target = own.current_hex
		query.accepted_context = result.context
		query.accepted_at = snapshot.captured_at
		var urgent_response: PositionResult = PositionQueryService.query_positions(query)
		_check(urgent_response.should_move and urgent_response.features.get("support_priority_covered", false), "Urgent aura coverage interrupts an HQ commitment outside leadership range")
		query.has_accepted_target = false
		var inspection: PositionQuery = PositionQuery.new()
		inspection.unit = own
		inspection.team = own.team
		controller.query_inspection_positions(inspection)
		var inspection_job: PositionQueryJob = controller.inspection_jobs[own as Unit]
		while not inspection_job.completed:
			controller._process_position_queries()
		var fresh_inspection: PositionQuery = PositionQuery.new()
		fresh_inspection.unit = own
		fresh_inspection.team = own.team
		_check(controller.query_inspection_positions(fresh_inspection) == inspection_job.result and controller.inspection_jobs[own as Unit] == inspection_job and not inspection_job.canceled, "Refreshing headquarters inspection reuses completed advice instead of canceling and restarting it")
		controller.clear_inspection_queries()
		_check(not query.support_targets.has(foreign), "Another platoon's stress cannot lure headquarters away from its own squads")
		var captured_need: float = query.support_targets[stressed as Unit]["need"]
		stressed.stress_system.S_eff = 0.0
		HqSupportPositionPolicy.prepare(query)
		_check(query.support_targets[stressed as Unit]["need"] == captured_need, "Support need is frozen in the completed snapshot")
		stressed.stress_system.S_eff = 90.0
		query.objective_hex = Vector2i(8, 0)
		query.profile = PositionProfile.for_mode(PositionProfile.Mode.ASSAULT)
		var changed: PositionResult = PositionQueryService.query_positions(query)
		_check(changed.target_hex == urgent and changed.context == result.context and changed.profile_mode == PositionProfile.Mode.HQ_SUPPORT, "Offensive objectives cannot redirect headquarters away from support")
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, concealed, 0.6)
		var old_los: Dictionary = snapshot.los
		snapshot.los = old_los.duplicate(true)
		var contact: InfluenceContact = InfluenceContact.new()
		contact.unit = enemy
		contact.hex = Vector2i(8, 0)
		contact.observed = true
		contact.confidence = 1.0
		contact.firepower = 0.0
		contact.weapon_range = 9
		snapshot.defensive_contacts[own.team] = [contact]
		snapshot.los[contact.hex] = {urgent: {"target_cover": 0.0, "hindrance": 0.0}}
		changed = PositionQueryService.query_positions(query)
		_check(changed.is_valid() and changed.target_hex != urgent and changed.features.get("enemy_visibility", 1.0) == 0.0 and changed.features["support_priority_covered"], "Concealed support with aura coverage beats an exposed support position")
		_check(changed.features.get("exposure_seconds", INF) <= 3.0 and changed.features.get("open_exposure_seconds", INF) <= 1.0, "Support transit obeys stricter cumulative exposure budgets")
		var job: PositionQueryJob = PositionQueryJob.new()
		job.query = query
		while not job.completed:
			job.advance(Time.get_ticks_usec() + 50)
		_check(job.result.target_hex == changed.target_hex and job.result.eligibility == changed.eligibility, "Budgeted support advice matches synchronous candidates and selection")
		query.has_accepted_target = true
		query.accepted_target = changed.target_hex
		query.accepted_context = changed.context
		var retained: PositionResult = PositionQueryService.query_positions(query)
		_check(retained.target_hex == changed.target_hex and retained.status == PositionResult.Status.RETAINED, "Stable support need retains its accepted covered position")
		var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
		_check(executor.execute(changed, TacticalPositionExecutor.Intent.ASSAULT) and (own.action_controller as ActionProbe).intent == "defend", "Explicit assault intent cannot turn a support move into an assault")
		executor.cancel_all(true)
		query.has_accepted_target = false
		snapshot.defensive_contacts[own.team] = []
		snapshot.support_units[other as Unit]["need"] = 1.5
		snapshot.support_units[stressed as Unit]["need"] = 0.1
		changed = PositionQueryService.query_positions(query)
		_check(changed.target_hex == quiet, "Changing squad stress redirects headquarters to the newly stressed squad")
		map.clear_layer(InfluenceMap.Layer.THREAT, 1.0)
		for cell: Vector2i in [quiet, urgent, concealed, own.current_hex]:
			map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
		query.profile.max_open_exposure_seconds = 0.01
		changed = PositionQueryService.query_positions(query)
		_check(changed.is_valid() and changed.target_hex == own.current_hex and not changed.should_move, "Urgent support cannot force headquarters across dangerous open transit")
		_check(changed.eligibility[map.cell_to_index(quiet)] == 0 and changed.rejection_reasons[map.cell_to_index(quiet)] == "route", "Diagnostics distinguish useful support cover with an unsafe route")
		query.profile.max_open_exposure_seconds = 1.0
		map.clear_layer(InfluenceMap.Layer.THREAT)
		for cell: Vector2i in [quiet, urgent, concealed, own.current_hex]:
			map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 0.0)
		changed = PositionQueryService.query_positions(query)
		_check(changed.is_valid() and changed.features["cover"] == 0.0 and changed.features["support_priority_covered"], "HQ uses open support ground when no known good-order enemy has LOS")
		var planner: PlatoonAI = PlatoonAI.new()
		planner.team = own.team
		planner.influence_map_controller = controller
		planner.current_order = MissionOrder.new()
		planner.set_squads([own, other, stressed])
		_check(own.ai_support_only and PositionQueryService.can_follow_intent(own), "Support moves remain independent of combat handoffs")
		_check(not DefenseReadinessJob.established(own, query), "Headquarters cannot promise established combat coverage")
		planner._planning_snapshot = snapshot
		planner._build_planning_requests([own])
		_check(planner._planning_requests.size() == 1 and planner._planning_requests[0]["role"] == "hq_support", "A headquarters-only roster receives support advice without combat duties")
		var rifle: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
		_equip(own, [rifle])
		own.squad_fire.unit = own
		own.squad_fire.stress_controller = own.stress_system
		Globals.unit_visible_enemies[own] = [enemy]
		var command_count: int = own.commanded.size()
		SquadTargetSelector.handle_auto_fire(own.squad_fire, 1.0, own, own.current_hex, own.weapon_range, own.fire_rate, own.firepower)
		var fired: int = await own.squad_fire._try_fire_soldier(1.0, own.squad_fire.soldiers[0], false, 0, 0, 1, 0)
		own.squad_fire.has_target_hex = true
		own.squad_fire._process(1.0)
		_check(own.commanded.size() == command_count and fired == 0 and not own.squad_fire.has_target_hex, "Support-only headquarters neither acquires visible targets nor fires an existing target")
		own.squad_fire.free()
		own.squad_fire = null
		Globals.unit_visible_enemies.erase(own)
		planner.set_active(false)
		_check(not own.ai_support_only, "Player handoff releases the AI-only support restriction")
		planner.free()
		snapshot.los = old_los
	own.team = Globals.Team.AXIS
	other.team = Globals.Team.AXIS
	enemy.team = Globals.Team.ALLIES
	own.squad_type = Globals.SquadType.Rifle
	own.current_hex = saved_hex
	own.position = ground.map_to_local(saved_hex)
	other.current_hex = saved_other
	stressed.free()
	foreign.free()
	remove_child(controller)
	_publish()


func _test_attack_headquarters_support() -> void:
	var headquarters: Unit = _unit(own.team, Vector2i(1, 5))
	var forward: Unit = _unit(own.team, Vector2i(6, 3))
	var rear: Unit = _unit(own.team, Vector2i(1, 4))
	var defender: Unit = _unit(enemy.team, Vector2i(7, 3))
	headquarters.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	headquarters.leader_aura.aura_radius_hexes = 1
	var saved_snapshot: InfluenceSnapshot = controller.snapshot
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.version = saved_snapshot.version + 1
	snapshot.los = LOSHelper.los_lookup
	snapshot.routes[own.team] = saved_snapshot.routes[own.team]
	snapshot.point_ids[own.team] = saved_snapshot.point_ids[own.team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(saved_snapshot.maps[own.team].bounds)
	map.playable_cells = saved_snapshot.maps[own.team].playable_cells.duplicate()
	map.clear_layer(InfluenceMap.Layer.THREAT, 4.0)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, headquarters.current_hex, 0.9)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, forward.current_hex, 0.6)
	snapshot.maps[own.team] = map
	for friendly: Unit in [headquarters, forward, rear]:
		snapshot.positions[friendly] = friendly.current_hex
		snapshot.teams[friendly] = own.team
		snapshot.support_units[friendly] = {"headquarters": friendly == headquarters, "company": friendly.company,
			"platoon": friendly.platoon, "commander": headquarters, "company_hq": false,
			"members": friendly.members_alive, "radius": friendly.leader_aura.aura_radius_hexes, "need": 0.1, "surrendered": false}
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = defender
	contact.hex = defender.current_hex
	contact.observed = true
	contact.confidence = 1.0
	contact.firepower = 1.0
	contact.effectiveness = 0.4
	contact.weapon_range = 8
	snapshot.contacts[own.team] = [contact]
	snapshot.defensive_contacts[own.team] = [contact]
	controller.snapshot = snapshot
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.squads = [headquarters, forward, rear]
	planner.current_order = MissionOrder.new()
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner.current_order.objective_hex = defender.current_hex
	planner.attack_maneuver_squad = forward
	planner._build_planning_requests(planner.squads)
	var query: PositionQuery
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == headquarters:
			query = request["query"]
	_check(query != null and query.profile.support_assault_squads and query.assault_support_squad == forward, "The actual attack planner supplies HQ escort settings and the selected advancing rifle")
	_check(query.profile.commitment_seconds == 8.0 and query.profile.max_exposure_seconds == planner.current_order.exposure_budget_seconds and query.profile.max_open_exposure_seconds == planner.current_order.open_crossing_budget_seconds, "HQ escort requests retain the attack mission's movement budgets")
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == headquarters.current_hex, "A fresh adjacent defender blocks exposed forward HQ support")
	var fresh_risk: float = PositionFeatureEvaluator.route_step(query, forward.current_hex)["risk"]
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.should_move and advice.target_hex == forward.current_hex, "HQ follows its advancing rifle into leadership range while the defender is pinned, before surrender")
	_check(query.support_targets[forward]["need"] >= 0.35 and query.support_targets[rear]["need"] == 0.1, "Escort priority follows the advancing rifle rather than calm rear overwatch rifles")
	_check(advice.features["leadership_radius"] == 1 and advice.features["supported_squads"].has(forward), "HQ position selection respects a one-hex leadership aura")
	_check(advice.features["exposure_seconds"] <= query.profile.max_exposure_seconds and advice.features["open_exposure_seconds"] <= query.profile.max_open_exposure_seconds, "Suppression-aware HQ movement remains within its exposure budgets")
	_check(PositionFeatureEvaluator.route_step(query, forward.current_hex)["risk"] < fresh_risk, "Observed suppression lowers HQ route risk as well as its visibility penalty")
	var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
	_check(executor.execute(advice) and headquarters.movement.is_moving and headquarters.movement.target_hex == forward.current_hex, "HQ escort advice starts an actual support movement order")
	executor.cancel_all(true)
	query.has_accepted_target = true
	query.accepted_target = headquarters.current_hex
	query.accepted_context = query.context_key()
	query.accepted_at = snapshot.captured_at
	snapshot.support_units[forward]["need"] = 1.0
	advice = PositionQueryService.query_positions(query)
	_check(advice.should_move and advice.features["support_priority_covered"], "A stressed forward rifle interrupts a rear HQ position commitment")
	contact.observed = false
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == headquarters.current_hex, "A remembered defender retains its threat even if its hidden live state is pinned")
	contact.observed = true
	defender.surrendered = true
	advice = PositionQueryService.query_positions(query)
	_check(advice.should_move and advice.features["enemy_visibility"] == 0.0 and advice.features["incoming"] == 0.0, "An observed surrendered defender cannot obstruct HQ support or add enemy visibility")
	contact.observed = false
	_check(HqSupportPositionPolicy.contact_threat_multiplier(query, contact) == 1.0, "An unobserved surrender cannot reveal a safe route through remembered threats")
	query.has_accepted_target = false
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, forward.current_hex, 0.0)
	contact.observed = true
	defender.surrendered = false
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	advice = PositionQueryService.query_positions(query)
	_check(advice.should_move and advice.features["cover"] == 0.0 and advice.features["support_priority_covered"] and not advice.features["good_order_enemy_los"], "HQ can reach its stressed rifle in open ground watched only by an observed pinned defender")
	var open_support: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, null, "hq_support")
	defender.stress_system.state = UnitStates.MoraleState.NORMAL
	defender.stress_system.S_eff = 0.0
	planner._apply_position_results([open_support], "hq_support", null)
	planner._issue_order(headquarters)
	_check(not headquarters.movement.is_moving and not planner.accepted_positions.has(headquarters), "A defender recovering after planning blocks cached open-ground HQ movement before execution")
	advice = PositionQueryService.query_positions(query)
	_check(advice.rejection_reasons[map.cell_to_index(forward.current_hex)] == "hq_open_enemy_los", "A recovered good-order defender immediately rejects the same open HQ support hex")
	contact.observed = false
	defender.stress_system.state = UnitStates.MoraleState.PINNED
	advice = PositionQueryService.query_positions(query)
	_check(advice.rejection_reasons[map.cell_to_index(forward.current_hex)] == "hq_open_enemy_los", "A hidden defender's live pin state cannot authorize an exposed open HQ hex")
	snapshot.los = snapshot.los.duplicate(true)
	snapshot.los[contact.hex] = {}
	advice = PositionQueryService.query_positions(query)
	_check(advice.eligibility[map.cell_to_index(forward.current_hex)] == 1, "Remembered enemies without LOS do not forbid an open HQ destination")
	snapshot.support_units[forward]["surrendered"] = true
	HqSupportPositionPolicy.prepare(query)
	_check(not query.support_targets.has(forward), "HQ cannot chase a surrendered friendly squad's obsolete support need")
	controller.snapshot = saved_snapshot
	planner.free()
	for unit: Unit in [headquarters, forward, rear, defender]:
		unit.free()


func _test_headquarters_stacking() -> void:
	var saved_own: Vector2i = own.current_hex
	var saved_other: Vector2i = other.current_hex
	var saved_enemy: Vector2i = enemy.current_hex
	var saved_role: Globals.SquadType = own.squad_type
	own.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	own.current_hex = Vector2i(2, 3)
	other.current_hex = Vector2i(4, 3)
	enemy.current_hex = Vector2i(1, 3)
	own.position = ground.map_to_local(own.current_hex)
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		own.team = team
		other.team = team
		enemy.team = Globals.get_enemy_team(team) as Globals.Team
		_publish()
		var snapshot: InfluenceSnapshot = controller.snapshot
		var map: InfluenceMap = snapshot.maps[team]
		map.clear_layer(InfluenceMap.Layer.TERRAIN_COVER)
		map.clear_layer(InfluenceMap.Layer.THREAT)
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, own.current_hex, 0.6)
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, other.current_hex, 0.6)
		var contact: InfluenceContact = InfluenceContact.new()
		contact.unit = enemy
		contact.hex = enemy.current_hex
		contact.observed = true
		contact.confidence = 1.0
		contact.firepower = 0.01
		contact.effectiveness = 1.0
		contact.weapon_range = 6
		snapshot.contacts[team] = [contact]
		snapshot.defensive_contacts[team] = [contact]
		snapshot.los = snapshot.los.duplicate(true)
		snapshot.los[contact.hex] = {own.current_hex: {"target_cover": 2.0, "hindrance": 0.0}}
		var query: PositionQuery = PositionQuery.new()
		query.unit = own
		query.team = team
		query.snapshot = snapshot
		query.reservations[other as Unit] = other.current_hex
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.should_move and result.target_hex == other.current_hex, "Headquarters can escape an adjacent known enemy into the only covered friendly stack")
		_check(result.eligibility[map.cell_to_index(other.current_hex)] == 1 and result.rejection_reasons[map.cell_to_index(own.current_hex)] == "hq_frontline", "Friendly occupancy and reservations cannot hide the safe support candidate")
		if result.is_valid():
			var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
			_check(executor.execute(result), "The existing movement executor accepts a headquarters route ending in a friendly squad hex")
			executor.cancel_all(true)
			query.has_accepted_target = true
			query.accepted_target = result.target_hex
			query.accepted_context = result.context
			var retained: PositionResult = PositionQueryService.query_positions(query)
			_check(retained.is_valid() and retained.target_hex == result.target_hex and retained.status == PositionResult.Status.RETAINED, "A squad reservation does not invalidate an accepted headquarters support stack")
			query.has_accepted_target = false
		var job: PositionQueryJob = PositionQueryJob.new()
		job.query = query
		while not job.completed:
			job.advance(Time.get_ticks_usec() + 50)
		_check(job.result.target_hex == result.target_hex and job.result.eligibility == result.eligibility, "Budgeted and synchronous advice agree on stacked support candidates")
		own.current_hex = other.current_hex
		own.position = ground.map_to_local(own.current_hex)
		snapshot.positions[own as Unit] = own.current_hex
		var held: PositionResult = PositionQueryService.query_positions(query)
		_check(held.is_valid() and held.target_hex == own.current_hex and not held.should_move, "Headquarters can retain its current hex after stacking with a friendly squad")
		own.in_close_combat = true
		_check(not PositionQueryService.query_positions(query).is_valid(), "Stacking cannot release headquarters from the close-combat movement lock")
		own.in_close_combat = false
		own.current_hex = Vector2i(2, 3)
		own.position = ground.map_to_local(own.current_hex)
		snapshot.positions[own as Unit] = own.current_hex
		contact.hex = other.current_hex
		var blocked: PositionResult = PositionQueryService.query_positions(query)
		_check(blocked.rejection_reasons[map.cell_to_index(other.current_hex)] == "capacity", "A friendly stack with a known enemy remains unavailable to headquarters")
		contact.hex = enemy.current_hex
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, other.current_hex, 0.0)
		blocked = PositionQueryService.query_positions(query)
		_check(blocked.eligibility[map.cell_to_index(other.current_hex)] == 1, "HQ can stack with a friendly squad in open ground outside known good-order enemy LOS")
		snapshot.los[contact.hex][other.current_hex] = {"target_cover": 0.0, "hindrance": 0.0}
		blocked = PositionQueryService.query_positions(query)
		_check(blocked.rejection_reasons[map.cell_to_index(other.current_hex)] == "hq_open_enemy_los", "Friendly stacking does not waive the HQ open-ground enemy LOS restriction")
		snapshot.los[contact.hex].erase(other.current_hex)
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, other.current_hex, 0.6)
		map.set_layer_value(InfluenceMap.Layer.THREAT, other.current_hex, 100.0)
		blocked = PositionQueryService.query_positions(query)
		_check(blocked.rejection_reasons[map.cell_to_index(other.current_hex)] == "risk", "Friendly stacking does not waive headquarters incoming-danger limits")
		map.clear_layer(InfluenceMap.Layer.THREAT)
		var squad_query: PositionQuery = PositionQuery.new()
		squad_query.unit = other
		squad_query.team = team
		squad_query.snapshot = snapshot
		squad_query.profile = PositionProfile.for_mode(PositionProfile.Mode.LEGACY_DEFENSE)
		squad_query.geography = PositionQuery.Geography.SECTOR_ONLY
		squad_query.sector_cells = [own.current_hex]
		squad_query.objective_hex = own.current_hex
		squad_query.reservations[own as Unit] = own.current_hex
		var shared: PositionResult = PositionQueryService.query_positions(squad_query)
		_check(shared.is_valid() and shared.target_hex == own.current_hex, "A squad can use cover occupied or reserved by its headquarters")
		var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
		readiness.query = squad_query
		readiness.reserve = other
		_check(readiness._free_destination(own.current_hex), "Reserve response assessment treats headquarters-occupied cover as an available interception position")
		_check(not HqSupportPositionPolicy.can_share_position(own, enemy), "Headquarters stacking permission cannot include an opposing unit")
		own.current_hex = Vector2i(2, 3)
	own.team = Globals.Team.AXIS
	other.team = Globals.Team.AXIS
	enemy.team = Globals.Team.ALLIES
	own.current_hex = saved_own
	own.position = ground.map_to_local(saved_own)
	other.current_hex = saved_other
	enemy.current_hex = saved_enemy
	own.squad_type = saved_role
	_publish()


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
	_check(platoon._select_reserve_squad(available) == null, "An ineffective squad or headquarters cannot substitute for a combat-capable mobile reserve")
	platoon.current_order.reserve_policy = MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE
	_check(platoon._select_reserve_squad(available) == null, "An explicit HQ policy cannot turn headquarters into a combat reserve")
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
	draw.set_debug_enabled(true)
	var order_id: int = own.action_controller.action_order_id
	var tactical_advice: PositionResult = own.position_advice
	draw.set_selected_unit(own)
	_check(draw.debug_view == InfluenceMapDebugDraw.DebugView.POSITION_SCORE and draw.team == own.team and draw.position_advice == advice, "Selection displays read-only position advice when placement debugging is enabled")
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


func _test_rapid_defense_response() -> void:
	var query: PositionQuery = _defense_fixture()
	query.rapid_response = true
	query.optimize_position = false
	query.sector_cells = [own.current_hex, Vector2i(4, 3)]
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.target_hex == own.current_hex and result.features.get("rapid_role_check", false), "A rapid defense check retains a covered position fulfilling its responsibility")
	_check(query.route_field == null and result.eligibility.count(1) == 1, "A useful current position avoids candidate-field and route-flood optimization")
	query.sector_cells = [Vector2i(4, 3)]
	result = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.should_move and result.features.get("rapid_deployment", false) and query.route_field == null, "Rapid deployment finds a responsible covered position without a full route flood")
	var shortest: Array[Vector2i] = query.snapshot.get_path(query.team, own.current_hex, result.target_hex)
	var dangerous: Vector2i = shortest[1]
	query.snapshot.maps[own.team].set_layer_value(InfluenceMap.Layer.THREAT, dangerous, 500.0)
	query.profile.max_route_exposure = 0.2
	result = PositionQueryService.query_positions(query)
	_check(result.is_valid() and not result.path.has(dangerous) and query.route_field != null, "An unsafe shortest route falls back to a full search for a safe detour")
	_check(result.features["peak_exposure"] <= query.profile.max_route_exposure and result.features["exposure_seconds"] <= query.profile.max_exposure_seconds, "Rapid-response fallback preserves destination and accumulated route danger limits")
	query.reservations[other as Unit] = Vector2i(4, 3)
	_check(not PositionQueryService.query_positions(query).is_valid(), "Rapid deployment cannot take another squad's reserved position")
	var regular: PositionQuery = _defense_fixture()
	regular.sector_cells = [own.current_hex, Vector2i(4, 3)]
	var response: PositionQuery = _defense_fixture()
	response.rapid_response = true
	response.optimize_position = false
	response.response_priority = 3
	response.sector_cells = [own.current_hex]
	var regular_job: PositionQueryJob = controller.enqueue_position_query(regular)
	var response_job: PositionQueryJob = controller.enqueue_position_query(response)
	_check(controller.position_jobs[0] == response_job and controller.position_jobs[1] == regular_job, "An urgent defense response precedes an unfinished optional query without canceling it")
	controller._process_position_queries()
	_check(response_job.completed and not regular_job.canceled, "Urgent advice publishes while unrelated scheduled work remains resumable")
	controller.cancel_position_query(regular_job)
	controller.cancel_position_query(response_job)
	var version: int = controller.snapshot.version
	_check(controller.request_defense_refresh() == version + 1 and controller.defense_refresh_requested, "A defense event requests a fresh capture without waiting for the periodic update")
	controller.pending_snapshot = InfluenceSnapshot.new()
	controller.pending_snapshot.version = version + 1
	_check(controller.request_defense_refresh() == version + 2, "A capture predating an event cannot satisfy the requested tactical refresh")
	controller.pending_snapshot = null
	controller.defense_refresh_requested = false
	var visible: Dictionary = Globals.unit_visible_enemies.duplicate()
	Globals.unit_visible_enemies[own] = []
	Globals.unit_visible_enemies[other] = []
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.set_squads([own, other])
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = Vector2i(3, 3)
	planner.accepted_positions[other as Unit] = {"hex": other.current_hex, "context": "unaffected"}
	var previous_morale: UnitStates.MoraleState = own.stress_system.state
	own.stress_system.state = UnitStates.MoraleState.NORMAL
	planner._check_defense_events()
	_check(planner._defense_refresh_version == -1, "Initial defense observations do not restart the mission")
	Globals.unit_visible_enemies[own] = [enemy]
	planner._check_defense_events()
	_check(planner._defense_refresh_version == version + 1 and planner._defense_urgent_units.has(own), "A newly observed enemy triggers an immediate prioritized defense response")
	_check(not planner._defense_urgent_units.has(other) and planner.accepted_positions.has(other), "A new threat preserves an unrelated squad's accepted position")
	var timer: float = planner.time_until_reconsider
	planner._check_defense_events()
	_check(planner.time_until_reconsider == timer and planner._defense_refresh_version == version + 1, "An unchanged sighting does not repeatedly interrupt planning")
	own.stress_system.state = UnitStates.MoraleState.PINNED
	planner._check_defense_events()
	_check(planner._defense_urgent_units.has(other), "Losing a pinned defender prioritizes a mobile replacement")
	var enemy_hex: Vector2i = enemy.current_hex
	Globals.unit_visible_enemies[own] = []
	enemy.current_hex = Vector2i(0, 0)
	planner._check_defense_events()
	_check(planner._defense_observed_hexes[enemy as Unit] == enemy_hex, "Hidden live movement cannot trigger an observed-knowledge defense reaction")
	enemy.current_hex = enemy_hex
	own.stress_system.state = previous_morale
	Globals.unit_visible_enemies = visible
	planner.set_active(false)
	_check(planner._defense_refresh_version == -1 and planner._defense_observed_hexes.is_empty(), "Disabling AI releases pending event reactions")
	planner.free()
	controller.defense_refresh_requested = false
	_publish()


func _add_defense_contact(query: PositionQuery) -> void:
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = Vector2i(6, 3)
	contact.firepower = 0.15
	contact.weapon_range = 6
	contact.observed = true
	query.snapshot.defensive_contacts[own.team] = [contact]


func _test_secured_objective_cover() -> void:
	var query: PositionQuery = _defense_fixture()
	_add_defense_contact(query)
	query.objective_hex = own.current_hex
	query.defense_responsibility = PositionQuery.Responsibility.GUARD
	query.objective_guard_radius = 2
	query.defense_radius = 2
	query.objective_guard_required = false
	query.profile.minimum_cover = 0.1
	var map: InfluenceMap = query.snapshot.maps[own.team]
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 0.0)
	var covered: Vector2i = Vector2i(0, 3)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, covered, 1.0)
	query.sector_cells = [own.current_hex, covered]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == covered and advice.features.get("responsibility") == "guard", "A secured objective can be guarded from cover two hexes away instead of its open marker")
	var visible: Dictionary = query.snapshot.los[covered].duplicate()
	query.snapshot.los[covered].erase(query.objective_hex)
	_check(not PositionQueryService.query_positions(query).is_valid(), "Nearby cover without a firing lane to the objective cannot serve as its guard")
	query.snapshot.los[covered] = visible
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, covered, 0.0)
	query.use_directional_cover = true
	var contact_hex: Vector2i = Vector2i(6, 3)
	query.snapshot.los[covered][contact_hex] = {"wall_cover": 2.0, "shooter_cover": 2.0, "target_cover": 0.0, "hindrance": 0.0}
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == covered and advice.features["cover"] > 0.5, "A secured guard can use a wall or hedge facing a known threat without building cover")
	_check(is_finite(PositionQueryService.rapid_candidate_score(query, map.cell_to_index(covered))), "Rapid guard selection also recognizes directional wall cover")
	query.snapshot.los[covered][contact_hex]["wall_cover"] = 0.0
	query.snapshot.los[covered][contact_hex]["hindrance"] = 2.0
	query.snapshot.los[covered][query.objective_hex] = {"wall_cover": 2.0, "shooter_cover": 2.0, "target_cover": 0.0, "hindrance": 0.0}
	_check(not PositionQueryService.query_positions(query).is_valid(), "A wall facing the objective cannot conceal exposure to a known threat from another direction")
	_check(PositionFeatureEvaluator.defensive_cover(query, covered) == 0.0, "Distant vegetation in shooter_cover cannot qualify an open guard position as cover")
	_check(not is_finite(PositionQueryService.rapid_candidate_score(query, map.cell_to_index(covered))), "Rapid selection rejects distant hindrance without local cover")
	query.snapshot.defensive_contacts[own.team] = []
	_check(PositionQueryService.query_positions(query).is_valid(), "Without observed threats a wall facing the objective can protect its guard")
	query.snapshot.los[covered][query.objective_hex]["wall_cover"] = 0.0
	_check(not PositionQueryService.query_positions(query).is_valid(), "A quiet objective also rejects sightline hindrance without a local wall")
	query.use_directional_cover = false
	var detached: Vector2i = Vector2i(5, 3)
	map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, detached, 1.0)
	query.sector_cells = [detached]
	_check(not PositionQueryService.query_positions(query).is_valid(), "Secured-objective guards cannot withdraw to distant cover outside their response radius")
	_publish()


func _test_screen_deployment_budget() -> void:
	var query: PositionQuery = _defense_fixture()
	_add_defense_contact(query)
	query.objective_hex = own.current_hex
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.sector_cells = [Vector2i(4, 3)]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid(), "A nearby covered screen remains reachable within its deployment budget")
	if advice.is_valid():
		query.profile.max_screen_deployment_seconds = advice.features["route_seconds"] + query.profile.establishment_seconds - 0.1
		var rejected: PositionResult = PositionQueryService.query_positions(query)
		_check(not rejected.is_valid() and rejected.rejections.has("deployment_time"), "Screen deployment includes actual route time and weapon establishment, not hex distance alone")
		query.rapid_response = true
		_check(not PositionQueryService.query_positions(query).is_valid(), "Rapid screening decisions enforce the same deployment deadline")
		query.defense_responsibility = PositionQuery.Responsibility.OCCUPY
		query.objective_hex = Vector2i(4, 3)
		query.profile.max_screen_deployment_seconds = 0.0
		_check(PositionQueryService.query_positions(query).is_valid(), "A mandatory occupation move is not restricted by the optional screening deadline")
	_publish()


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
	query.rapid_response = true
	query.optimize_position = false
	query.stability = PlatoonPositionStability.new()
	query.stability_time = 1.1
	var action_state: int = own.action_controller.action_state
	own.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var held: PositionResult = PositionResult.new()
	held.unit = own
	held.status = PositionResult.Status.ACCEPTED
	held.target_hex = front
	held.target_index = query.snapshot.maps[own.team].cell_to_index(front)
	held.profile_mode = PositionProfile.Mode.DEFEND
	held.position_profile = query.profile
	query.stability.accepted(held, 1.0)
	var rapid_intercept: PositionResult = PositionQueryService.query_positions(query)
	_check(rapid_intercept.is_valid() and rapid_intercept.should_move and rapid_intercept.target_hex == query.objective_hex, "Rapid role checks cannot retain a covered screen after a confirmed enemy has passed it")
	_check(rapid_intercept.features.get("movement_kind", "") == "necessary" and query.stability.optional_mover == null, "An urgent interception bypasses optional holding periods and the single optional mover slot")
	own.action_controller.action_state = action_state
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
	director.objective_source = DefenseDirector.ObjectiveSource.LEGACY_FORCE_ANCHOR
	var previous: Dictionary[Globals.Team, ObjectivesCollection] = Globals.objectives.duplicate()
	var targets: ObjectivesCollection = ObjectivesCollection.new()
	var objective: ObjectiveDefinition = ObjectiveDefinition.new()
	objective.objective_id = 1
	objective.hex = Vector2i(4, 3)
	targets.objectives.append(objective)
	Globals.objectives[enemy.team] = targets
	director.configure_for_match([own])
	_check(director.objective_hex == own.current_hex, "Legacy opponent-target configuration stays at its own platoon anchor")
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
	while platoon._area_job != null:
		platoon._area_job.advance(-1)
		if platoon._readiness_job != null:
			platoon._readiness_job.advance(-1)
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
	own.movement.is_moving = true
	other.movement.is_moving = false
	query.has_accepted_target = true
	query.accepted_target = west
	query.accepted_context = original_context
	advice = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == east and query.relocation_allowed, "A defender already moving can redirect to cover without a global movement lock")
	own.movement.is_moving = false
	query.has_accepted_target = false
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
	_check(guard_count == 1 and reserve_count == 1 and tasked.size() == 1, "Two significant fronts retain a protected mobile reserve rather than consuming it on branch count alone")
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


func _test_forward_screen_and_fallback() -> void:
	var query: PositionQuery = _defense_fixture()
	query.objective_hex = Vector2i(4, 3)
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.minimum_forward_progress = 2
	query.protect_garrison_hex = true
	query.axis = ThreatAxis.new()
	query.axis.source_hex = Vector2i(8, 3)
	query.axis.target_hex = query.objective_hex
	query.sector_cells = [query.objective_hex, Vector2i(3, 3), Vector2i(7, 3)]
	var forward: PositionResult = PositionQueryService.query_positions(query)
	_check(forward.is_valid() and forward.features.get("forward_progress", 0) >= 2 and not forward.features.get("screen_fallback", true), "A screen occupies a forward firing position instead of treating the garrison as its front")
	query.sector_cells = [query.objective_hex, Vector2i(3, 3)]
	var fallback: PositionResult = PositionQueryService.query_positions(query)
	_check(fallback.is_valid() and fallback.target_hex == Vector2i(3, 3) and fallback.features.get("screen_fallback", false), "An infeasible forward screen gets an explicit covered fallback without occupying its garrison")
	_check(fallback.features["important_approaches_covered"] > 0 and fallback.features["exposure_seconds"] <= query.profile.max_exposure_seconds, "A screen fallback retains approach coverage and route safety")
	query.sector_cells.append(Vector2i(7, 3))
	var retried: PositionResult = PositionQueryService.query_positions(query)
	_check(retried.is_valid() and retried.features.get("forward_progress", 0) >= 2 and not retried.features.get("screen_fallback", true), "A later forward opportunity is not suppressed by an earlier fallback")
	query.minimum_forward_progress = 0
	query.sector_cells = [query.objective_hex]
	_check(not PositionQueryService.query_positions(query).is_valid(), "A covering squad cannot block the objective reserved for the required garrison")


func _screen_retention_query(planner: PlatoonAI, unit: Unit, snapshot: InfluenceSnapshot, source: Vector2i, cells: Array[Vector2i]) -> PositionQuery:
	var query: PositionQuery = PositionQuery.new()
	query.unit = unit
	query.team = unit.team
	query.snapshot = snapshot
	query.objective_hex = planner.current_order.objective_hex
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	query.use_defense_area = false
	query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	query.geography = PositionQuery.Geography.SECTOR_ONLY
	query.sector_cells = cells
	query.axis = ThreatAxis.new()
	query.axis.source_hex = source
	query.axis.target_hex = query.objective_hex
	query.axis.approach_hexes = [Vector2i(3, 3)]
	planner._configure_position_stability(query)
	return query


func _test_established_screen_retention() -> void:
	var fixture: PositionQuery = _defense_fixture()
	var first: UnitProbe = _unit(own.team, Vector2i(2, 5))
	var second: UnitProbe = _unit(own.team, Vector2i(0, 5))
	var third: UnitProbe = _unit(own.team, Vector2i(0, 6))
	var units: Array[Unit] = [first, second, third]
	var weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for unit: Unit in units:
		_equip(unit, [weapon])
		unit.combat_stats.combat_effectiveness = 1.0
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		unit.position = ground.map_to_local(unit.current_hex)
		fixture.snapshot.positions[unit] = unit.current_hex
		fixture.snapshot.teams[unit] = unit.team
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.set_squads(units)
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = first.current_hex
	var initial: PositionQuery = _screen_retention_query(planner, first, fixture.snapshot, Vector2i(8, 5), [Vector2i(4, 5)])
	_check(initial.initial_deployment and initial.minimum_forward_progress == 2, "An undeployed three-squad defense still establishes a forward screen")
	var deployment: PositionResult = PositionQueryService.query_positions(initial)
	_check(deployment.is_valid() and deployment.should_move, "The initial screen has a checked forward deployment")
	if deployment.is_valid():
		first.movement.is_moving = true
		first.movement.target_hex = deployment.target_hex
		first.action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
		planner.position_stability.accepted(deployment, 0.0)
		_check(not planner.position_stability.has_deployed_screen(first, initial.objective_hex), "An accepted destination does not count as an established screen before arrival")
		# Approach evidence can change while a squad finishes its accepted bound.
		var refreshed: PositionResult = PositionResult.new()
		refreshed.unit = first
		refreshed.status = PositionResult.Status.RETAINED
		refreshed.target_index = deployment.target_index
		refreshed.target_hex = deployment.target_hex
		refreshed.objective_hex = deployment.objective_hex
		refreshed.features = deployment.features.duplicate()
		refreshed.features["screen_fallback"] = true
		planner.position_stability.accepted(refreshed, 1.0)
		first.current_hex = deployment.target_hex
		first.position = ground.map_to_local(first.current_hex)
		fixture.snapshot.positions[first as Unit] = first.current_hex
		first.movement.is_moving = false
		first.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
		planner.position_stability.observe(units, 2.0)
		_check(not planner.position_stability.has_deployed_screen(first, initial.objective_hex), "Weapon establishment must finish before the screen is credited")
		first.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		planner.position_stability.observe(units, 3.0)
		_check(planner.position_stability.has_deployed_screen(first, initial.objective_hex), "Finishing the originally checked screen completes deployment despite newer approach evidence")
		planner._configure_position_stability(initial)
		_check(not initial.initial_deployment and initial.minimum_forward_progress == 0, "Reconfiguring an existing query clears its completed deployment requirement")
		var shifted: PositionQuery = _screen_retention_query(planner, first, fixture.snapshot, Vector2i(2, 1), [first.current_hex])
		_check(not shifted.initial_deployment and shifted.minimum_forward_progress == 0, "An established screen is not forced through initial forward deployment again")
		DefensePositionPolicy.prepare(shifted)
		_check(DefensePositionPolicy.forward_progress(shifted, first.current_hex) < 2, "The shifted approach reproduces a formerly disqualified forward position")
		var retained: PositionResult = PositionQueryService.query_positions(shifted)
		_check(retained.is_valid() and retained.target_hex == first.current_hex and not retained.should_move, "A useful covered screen remains in place after the approach direction changes")
		planner.position_stability.forget(first)
		planner.accepted_positions.erase(first)
		var recovered: PositionQuery = _screen_retention_query(planner, first, fixture.snapshot, Vector2i(2, 1), [first.current_hex])
		_check(not recovered.initial_deployment and recovered.minimum_forward_progress == 0, "Losing a transient order or recovering from suppression does not restart screen deployment")
		planner.current_order.objective_hex = Vector2i(3, 5)
		var reassigned: PositionQuery = _screen_retention_query(planner, first, fixture.snapshot, Vector2i(8, 5), [first.current_hex])
		_check(reassigned.initial_deployment and reassigned.minimum_forward_progress == 2, "A new defensive objective gets its own initial deployment")
		var fallback: PositionResult = PositionResult.new()
		fallback.unit = first
		fallback.status = PositionResult.Status.ACCEPTED
		fallback.target_index = deployment.target_index
		fallback.target_hex = first.current_hex
		fallback.objective_hex = reassigned.objective_hex
		fallback.features = {"responsibility": "cover_approach", "screen_fallback": true}
		planner.position_stability.accepted(fallback, 4.0)
		_check(not planner.position_stability.has_deployed_screen(first, reassigned.objective_hex), "A rear fallback does not suppress a later initial forward opportunity")
	planner.free()
	for unit: Unit in units:
		unit.squad_fire.free()
		unit.squad_fire = null
		unit.free()
	_publish()


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
	snapshot.contacts[own.team] = [contact]
	snapshot.captured_at = 17.0
	memory.capture_into(snapshot)
	snapshot.contacts[own.team] = []
	enemy.surrendered = true
	memory.capture_into(snapshot)
	_check(not snapshot.get_defensive_contacts(own.team).is_empty(), "An unobserved surrender cannot clear remembered enemy danger")
	snapshot.contacts[own.team] = [contact]
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team).is_empty(), "An observed surrender clears the defender from tactical threat memory")
	snapshot.contacts[own.team] = []
	snapshot.captured_at = 30.0
	memory.capture_into(snapshot)
	_check(snapshot.get_defensive_contacts(own.team).is_empty(), "Losing LOS after observing surrender cannot resurrect a threat and stall the attack")
	contact.observed = false
	snapshot.contacts[own.team] = [contact]
	memory.capture_into(snapshot)
	_check(not PositionQueryService._occupied(query, contact.hex), "An obsolete firing contact cannot block occupation after its defender's surrender was observed")
	enemy.surrendered = false
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


func _test_concurrent_relocation() -> void:
	var own_team: Globals.Team = own.team
	var other_team: Globals.Team = other.team
	var enemy_team: Globals.Team = enemy.team
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		own.team = team
		other.team = team
		enemy.team = Globals.get_enemy_team(team)
		own.movement.is_moving = false
		other.movement.is_moving = false
		own.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		other.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		var anchor: UnitProbe = _unit(team, Vector2i(1, 2))
		anchor.squad = 99
		anchor.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		var query: PositionQuery = _defense_fixture()
		var target: Vector2i = Vector2i(6, 3)
		query.rapid_response = true
		query.optimize_position = false
		var destination: Vector2i = Vector2i(4, 3)
		query.sector_cells = [destination]
		var job: DefenseAreaJob = query.snapshot.defense_area_job(team, query.objective_hex, 4, 7)
		job.advance(-1)
		query.defense_area = job.result
		var branch: Dictionary = job.result.approaches[0].duplicate()
		branch.erase("branches")
		branch["key"] = "concurrent_front"
		branch["source"] = target
		branch["evidence"] = "observed"
		branch["priority"] = 1.0
		branch["cells"] = [target]
		branch["weights"] = {target: 1.0}
		branch["arrival_seconds"] = 0.0
		branch.erase("distances")
		query.defense_area.approaches = [branch]
		query.defense_area.max_priority = 1.0
		var record: Dictionary = {"target_cover": 0.0, "hindrance": 0.0}
		query.snapshot.los = query.snapshot.los.duplicate(true)
		for cell: Vector2i in [own.current_hex, other.current_hex, destination, Vector2i(3, 2)]:
			query.snapshot.los[cell] = {target: record, query.objective_hex: record}
		query.snapshot.los[anchor.current_hex] = {}
		query.snapshot.defensive_contacts[team] = [_area_contact(target, query.snapshot.captured_at)]
		var reservations: Dictionary = {}
		query.reservations = reservations
		query.departure_baseline = DefensePositionPolicy.capture_departure_baseline(query.snapshot, team)
		query.has_departure_baseline = true
		var first: PositionResult = PositionQueryService.query_positions(query)
		_check(first.is_valid() and first.should_move, "One defender can depart while an established squad preserves the attacked branch")
		reservations[own as Unit] = destination
		own.movement.is_moving = true
		own.movement.target_hex = destination
		var second_query: PositionQuery = _query()
		second_query.rapid_response = true
		second_query.optimize_position = false
		second_query.unit = other
		second_query.team = team
		second_query.snapshot = query.snapshot
		second_query.defense_area = query.defense_area
		second_query.geography = PositionQuery.Geography.SECTOR_ONLY
		second_query.sector_cells = [Vector2i(3, 2)]
		second_query.reservations = reservations
		second_query.departure_baseline = query.departure_baseline
		second_query.has_departure_baseline = true
		var second: PositionResult = PositionQueryService.query_positions(second_query)
		var index: int = query.snapshot.maps[team].cell_to_index(second_query.sector_cells[0])
		_check(not second.is_valid() and second.cell_states[index] == PositionResult.CellState.WAITING_HANDOFF, "The second departure cannot use a moving defender's future firing lane to open an attacked branch")
		query.snapshot.los[anchor.current_hex] = {target: record}
		second = PositionQueryService.query_positions(second_query)
		_check(second.is_valid() and second.should_move, "Independent defenders can move together while a real stationary anchor preserves protection")
		var flank_target: Vector2i = Vector2i(5, 2)
		var flank: Dictionary = branch.duplicate()
		flank["id"] = posmod(branch["id"] + 1, 6)
		flank["key"] = "independent_flank"
		flank["source"] = flank_target
		flank["evidence"] = "inferred"
		flank["cells"] = [flank_target]
		flank["weights"] = {flank_target: 1.0}
		query.defense_area.approaches.append(flank)
		query.snapshot.los[other.current_hex] = {flank_target: record}
		query.snapshot.los[second_query.sector_cells[0]] = {flank_target: record}
		second_query.assigned_branch = "independent_flank"
		_check(PositionQueryService.query_positions(second_query).is_valid(), "Movement on another branch remains available while the attacked branch has established protection")
		query.defense_area.approaches.pop_back()
		query.snapshot.los[other.current_hex] = {target: record, query.objective_hex: record}
		query.snapshot.los[second_query.sector_cells[0]] = {target: record, query.objective_hex: record}
		second_query.assigned_branch = ""
		anchor.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
		_check(not PositionQueryService.query_positions(second_query).is_valid(), "An anchor still establishing cannot release concurrent departures")
		anchor.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		reservations[anchor as Unit] = Vector2i(2, 2)
		_check(not PositionQueryService.query_positions(second_query).is_valid(), "A proposed anchor departure cannot count as established covering fire")
		reservations.erase(anchor as Unit)
		anchor.in_close_combat = true
		_check(not PositionQueryService.query_positions(second_query).is_valid(), "An anchor in close combat cannot supply the remaining firing screen")
		anchor.in_close_combat = false
		query.snapshot.los[anchor.current_hex] = {}
		branch["arrival_seconds"] = 100.0
		query.defense_area._crossing_zones.clear()
		second = PositionQueryService.query_positions(second_query)
		_check(second.is_valid(), "A verified short redeployment can restore its lane before distant attackers arrive")
		second_query.coverage_delay_seconds = 100.0
		_check(not PositionQueryService.query_positions(second_query).is_valid(), "Time spent calculating consumes the available interception deadline")
		second_query.coverage_delay_seconds = 0.0
		branch["evidence"] = "inferred"
		branch["arrival_seconds"] = 0.0
		query.defense_area._crossing_zones.clear()
		_check(PositionQueryService.query_positions(second_query).is_valid(), "A quiet terrain hypothesis does not stagger initial deployment")
		branch["evidence"] = "observed"
		var shared_a: Vector2i = Vector2i(5, 2)
		var shared_b: Vector2i = Vector2i(5, 3)
		var shared_c: Vector2i = Vector2i(5, 4)
		branch["cells"] = [shared_a, shared_b, shared_c]
		branch["weights"] = {shared_a: 1.0, shared_b: 1.0, shared_c: 1.0}
		query.defense_area._interception_zones.clear()
		query.defense_area._crossing_zones.clear()
		own.movement.is_moving = false
		reservations.clear()
		query.snapshot.los[own.current_hex] = {shared_a: record, query.objective_hex: record}
		query.snapshot.los[destination] = {shared_a: record, query.objective_hex: record}
		query.snapshot.los[other.current_hex] = {shared_b: record}
		query.snapshot.los[anchor.current_hex] = {}
		_check(PositionQueryService.query_positions(query).rejections.has("handoff_wait"), "A departure cannot lose collective partial protection even when no individual defender covers half the branch")
		branch["arrival_seconds"] = 100.0
		query.defense_area._crossing_zones.clear()
		_check(PositionQueryService.query_positions(query).is_valid(), "One partial contributor can cross briefly while another stays and the lane is restored before arrival")
		reservations[own as Unit] = destination
		own.movement.is_moving = true
		query.snapshot.los[second_query.sector_cells[0]] = {shared_b: record, query.objective_hex: record}
		_check(PositionQueryService.query_positions(second_query).rejections.has("handoff_wait"), "A later departure retains the group's original combined coverage requirement after its first contributor starts moving")
		var continuing: PlatoonAI = PlatoonAI.new()
		continuing.team = team
		continuing._planning_snapshot = query.snapshot
		continuing._departure_origins[own as Unit] = query.departure_baseline[own as Unit]
		second_query.departure_baseline = continuing._capture_planning_baseline()
		_check(second_query.departure_baseline.has(own as Unit) and PositionQueryService.query_positions(second_query).rejections.has("handoff_wait"), "Replanning during a relocation cannot forget the original protection still supplied by its stationary partner")
		continuing.free()
		branch["arrival_seconds"] = 0.0
		branch["cells"] = [target]
		branch["weights"] = {target: 1.0}
		query.defense_area._interception_zones.clear()
		query.defense_area._crossing_zones.clear()
		query.snapshot.los[own.current_hex] = {target: record, query.objective_hex: record}
		query.snapshot.los[destination] = {target: record, query.objective_hex: record}
		query.snapshot.los[other.current_hex] = {target: record, query.objective_hex: record}
		query.snapshot.los[second_query.sector_cells[0]] = {target: record, query.objective_hex: record}
		reservations[own as Unit] = destination
		own.movement.is_moving = true
		query.snapshot.los[anchor.current_hex] = {target: record}
		other.in_close_combat = true
		_check(not PositionQueryService.query_positions(second_query).is_valid(), "Concurrent movement never bypasses the close-combat movement rule")
		other.in_close_combat = false
		own.movement.is_moving = false
		query.snapshot.defensive_contacts[team] = [_area_contact(Vector2i(4, 2), query.snapshot.captured_at)]
		_check(PositionQueryService.query_positions(query).rejections.has("handoff_wait"), "A nearby confirmed attacker keeps the last established objective guard in place")
		var freshness: PlatoonAI = PlatoonAI.new()
		freshness.team = team
		freshness.influence_map_controller = controller
		freshness.current_order = MissionOrder.new()
		freshness.current_order.objective_hex = query.objective_hex
		freshness.defense_area = query.defense_area
		freshness.defense_area.observed_contacts = {enemy as Unit: target}
		var advance: InfluenceContact = _area_contact(target, query.snapshot.captured_at)
		query.snapshot.contacts[team] = [advance]
		query.snapshot.defensive_contacts[team] = [advance]
		_check(not freshness._defense_plan_outdated(), "An unchanged observed attacker does not trigger redundant replanning")
		advance.hex = Vector2i(5, 3)
		_check(freshness._defense_plan_outdated(), "One hex of observed advance near the objective invalidates the old entrance timing")
		freshness.time_until_reconsider = 100.0
		freshness._process(0.0)
		_check(freshness._area_job != null or freshness._readiness_job != null, "A confirmed nearby advance starts a new plan without waiting for the ordinary reconsideration timer")
		freshness.free()
		anchor.free()
	own.team = own_team
	other.team = other_team
	enemy.team = enemy_team
	own.movement.is_moving = false
	_publish()


func _test_progressive_planning() -> void:
	own.movement.is_moving = false
	other.movement.is_moving = false
	own.movement.attack_in_progress = false
	other.movement.attack_in_progress = false
	own.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	other.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var first_query: PositionQuery = _defense_fixture()
	first_query.sector_cells = [Vector2i(4, 3)]
	var second_query: PositionQuery = _query()
	second_query.unit = other
	second_query.snapshot = first_query.snapshot
	second_query.geography = PositionQuery.Geography.SECTOR_ONLY
	second_query.sector_cells = [Vector2i(3, 2)]
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = own.team
	planner.influence_map_controller = controller
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = first_query.objective_hex
	planner.squads = [own, other]
	planner._planning_snapshot = first_query.snapshot
	planner._planning_reservations = planner._create_current_reserved_hexes([own, other])
	first_query.reservations = planner._planning_reservations
	second_query.reservations = planner._planning_reservations
	planner._planning_requests = [{"query": first_query, "role": "defend_objective", "axis": null}, {"query": second_query, "role": "defend_objective", "axis": null}]
	planner._submit_planning_query()
	var slices: int = 0
	while not own.movement.is_moving and slices < 1000:
		controller._process_position_queries()
		planner._process(0.0)
		slices += 1
	_check(own.movement.is_moving and not other.movement.is_moving and planner._planning_index == 1 and planner._planning_job != null, "A validated first defender starts moving while the next destination is still calculating")
	var first_order: int = own.action_controller.action_order_id
	var first_advice: PositionResult = own.position_advice
	own.movement.path_hexes = first_advice.path.duplicate()
	own.movement.path_index = 1
	var original_hex: Vector2i = own.current_hex
	var validation: DefensePlanValidationJob = DefensePlanValidationJob.new()
	validation.start(null, [{"query": first_query}], [DefensePositionAnalyzer.adapt_result(first_advice, null, "defend_objective")])
	own.current_hex = first_advice.path[1]
	own.position = ground.map_to_local(own.current_hex)
	validation.advance(-1)
	_check(validation.valid and first_query.origin_hex == own.current_hex and validation.results[0].path[0] == own.current_hex, "Progress along an owned checked path can rebase advice without restarting the platoon")
	var second_order: int = -1
	while (planner._planning_job != null or planner._validation_job != null) and slices < 2000:
		controller._process_position_queries()
		planner._process(0.0)
		if second_order < 0 and other.movement.is_moving:
			second_order = other.action_controller.action_order_id
		slices += 1
	_check(own.movement.is_moving and other.movement.is_moving and planner._planning_job == null and planner._validation_job == null, "Quiet deployment publishes both moves before the first squad arrives")
	_check(own.action_controller.action_order_id == first_order, "Completing the platoon summary does not restart an already executing move")
	_check(second_order >= 0 and other.action_controller.action_order_id == second_order, "A just-issued move is not restarted when final publication occurs before its first hex crossing")
	_check(planner.accepted_positions.size() == 2 and planner.reserved_hexes_by_squad.size() == 2, "Progressive publication retains accepted ownership and consistent destination reservations")
	validation = DefensePlanValidationJob.new()
	validation.start(null, [{"query": first_query}], [DefensePositionAnalyzer.adapt_result(first_advice, null, "defend_objective")])
	own.current_hex = first_advice.path[-1]
	own.movement.is_moving = false
	own.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	validation.advance(-1)
	_check(validation.valid and validation.unchanged() and first_query.origin_hex == own.current_hex, "Arrival at an owned destination does not discard otherwise valid pending advice")
	own.action_controller.action_order_id += 1
	_check(not PositionQueryService.refresh_moving_origin(first_query, first_advice), "A replacement order cannot reuse the old planner's route ownership")
	_check(not validation.unchanged(), "A changed action invalidates live validation even when ordinary movement progress is tolerated")
	own.movement.is_moving = false
	own.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var guard_query: PositionQuery = _defense_fixture()
	guard_query.defense_responsibility = PositionQuery.Responsibility.GUARD
	planner.accepted_positions[own as Unit] = {"hex": own.current_hex, "context": guard_query.context_key()}
	var guard_request: Dictionary = {"query": guard_query, "role": "guard_objective", "axis": null}
	var front_request: Dictionary = {"query": second_query, "role": "defend_sector", "axis": null}
	planner._planning_requests = [guard_request, front_request]
	planner._prioritize_planning_requests()
	_check(planner._planning_requests[0]["query"].unit == other, "An established objective anchor does not delay a responding squad's candidate calculation")
	own.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	planner._planning_requests = [guard_request, front_request]
	planner._prioritize_planning_requests()
	_check(planner._planning_requests[0]["query"].unit == own, "An anchor still establishing retains its initial planning priority")
	planner.set_active(false)
	_check(planner._departure_origins.is_empty(), "Player handoff clears ongoing group protection together with owned movement")
	planner.free()
	own.current_hex = original_hex
	own.position = ground.map_to_local(original_hex)
	own.movement.is_moving = false
	other.movement.is_moving = false
	own.movement.path_hexes.clear()
	own.movement.path_index = 0
	_publish()


func _test_flexible_defense() -> void:
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		for objective: Vector2i in [Vector2i(3, 3), Vector2i(5, 3)]:
			for direction: int in range(6):
				_test_directional_reserve(team, objective, direction)
	_test_quiet_watch_continuity()
	_publish()


func _test_quiet_watch_continuity() -> void:
	var area: DefenseAreaAssessment = DefenseAreaAssessment.new()
	area.geometry = {"cells": []}
	area.approaches = [{"id": 0, "key": "first", "priority": 0.08, "source": own.current_hex, "evidence": "inferred", "cells": []}, {"id": 3, "key": "second", "priority": 0.08, "source": other.current_hex, "evidence": "inferred", "cells": []}]
	var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
	readiness.start(area, controller.snapshot, own.team, [own], own, 3)
	readiness.responses = {"first": {"covered": false, "crossing": true, "has_intercept": true, "arrival_seconds": 20.0, "seconds": {own.current_hex: 0.0}}, "second": {"covered": false, "crossing": true, "has_intercept": true, "arrival_seconds": 20.0, "seconds": {own.current_hex: 9.0}}}
	_check(readiness.select_watch({}) == "second", "A slow response can create a quiet terrain watch before a sighting")
	_check(readiness.select_watch({}, "first") == "first", "Quiet response differences cannot rotate an established watch repeatedly between terrain guesses")
	area.approaches[1]["evidence"] = "estimated"
	area.approaches[1]["priority"] = 0.25
	_check(readiness.select_watch({}, "first") == "second", "New credible pressure can supersede a quiet watch without a fixed direction")
	_check(readiness.select_watch({other as Unit: "second"}, "first") == "first" and not readiness.responses["second"]["covered"], "A front's planned duty distributes reserve responsibility without claiming established fire")
	_check(readiness.select_watch({other as Unit: "second"}, "first", {other as Unit: "second"}) == "second", "A failed front position cannot indefinitely keep the reserve away from that uncovered approach")
	var headquarters: UnitProbe = _unit(own.team, own.current_hex)
	headquarters.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	_check(readiness.select_watch({headquarters as Unit: "second"}, "first") == "second", "An HQ assignment cannot substitute for a combat defender on a credible approach")
	headquarters.free()
	area.approaches[1]["evidence"] = "inferred"
	area.approaches[1]["priority"] = 0.08
	readiness.responses["first"]["seconds"][own.current_hex] = INF
	_check(readiness.select_watch({}, "first") == "second", "An unsafe or blocked old response route invalidates quiet watch continuity")


func _directional_area(snapshot: InfluenceSnapshot, team: int, objective: Vector2i, sources: Array[Vector2i], reversed: bool) -> DefenseAreaAssessment:
	var job: DefenseAreaJob = DefenseAreaJob.new()
	job.start(snapshot, team, objective, 2, 8, [])
	job.advance(-1)
	var area: DefenseAreaAssessment = job.result
	area.approaches.clear()
	for index: int in range(sources.size()):
		var source: Vector2i = sources[index]
		var delta: Vector3i = (ground.map_to_cube(source) - ground.map_to_cube(objective)) / 3
		var entry: Vector2i = ground.cube_to_map(ground.map_to_cube(source) - delta)
		var edge: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) + delta)
		var field: DefenseTravelField = DefenseTravelField.new()
		field.start(area.geometry, source)
		field.advance(-1)
		var observed: bool = index == 0
		if reversed:
			observed = index == 1
		var evidence: String = "estimated"
		var priority: float = 0.25
		var crossing: float = 2.0
		var arrival: float = 20.0
		if observed:
			evidence = "observed"
			priority = 4.0
			crossing = 12.0 / (field.distances[entry] + area.geometry["costs"][edge])
			arrival = field.distances[objective] * crossing
		var sector: int = area.sector_at(source)
		area.approaches.append({"id": sector, "key": str(sector) + ":front", "priority": priority, "source": source, "evidence": evidence, "cells": [entry, source], "weights": {entry: 1.0, source: 1.0}, "distances": field.distances, "arrival_seconds": arrival, "crossing_seconds": crossing, "response_distances": area.geometry["response_fields"][sector]})
	area.max_priority = 4.0
	return area


func _directional_plan(snapshot: InfluenceSnapshot, team: int, area: DefenseAreaAssessment, defenders: Array[Unit], reserve: Unit) -> PlatoonAI:
	var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
	readiness.start(area, snapshot, team, defenders, reserve, 4)
	readiness.advance(-1)
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = team
	planner.influence_map_controller = controller
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = area.objective_hex
	planner.defense_area = area
	planner.reserve_squad = reserve
	planner._planning_snapshot = snapshot
	planner._planning_readiness = readiness
	for unit: Unit in defenders:
		planner._planning_reservations[unit] = unit.current_hex
	planner._build_sector_requests(defenders.duplicate())
	return planner


func _reserve_request(planner: PlatoonAI, reserve: Unit) -> PositionQuery:
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == reserve:
			return request["query"]
	return null


func _test_directional_reserve(team: Globals.Team, objective: Vector2i, direction: int) -> void:
	var neighbors: Array[Vector2i] = LOSHelper.get_hex_neighbors(objective)
	var delta: Vector3i = ground.map_to_cube(neighbors[direction]) - ground.map_to_cube(objective)
	var main_source: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) + delta * 3)
	var flank_source: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) - delta * 3)
	var main_edge: Vector2i = neighbors[direction]
	var flank_edge: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) - delta)
	var anchor: UnitProbe = _unit(team, objective)
	var gun: UnitProbe = _unit(team, neighbors[(direction + 1) % 6])
	var infantry: UnitProbe = _unit(team, neighbors[(direction + 2) % 6])
	var reserve: UnitProbe = _unit(team, flank_edge)
	anchor.squad_type = Globals.SquadType.MG
	gun.squad_type = Globals.SquadType.MG
	infantry.squad_type = Globals.SquadType.Rifle
	reserve.squad_type = Globals.SquadType.Rifle
	_equip(anchor, [load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec])
	_equip(gun, [load("res://resources/weapons/mg34.tres") as WeaponSpec])
	_equip(infantry, [load("res://resources/weapons/kar98.tres") as WeaponSpec])
	_equip(reserve, [load("res://resources/weapons/kar98.tres") as WeaponSpec])
	var defenders: Array[Unit] = [anchor, gun, infantry, reserve]
	_publish()
	var snapshot: InfluenceSnapshot = controller.snapshot
	snapshot.positions.clear()
	snapshot.teams.clear()
	# This fixture changes captured terrain directly rather than changing authored tiles.
	snapshot.defense_geometry_cache.clear()
	snapshot.contacts[team] = []
	snapshot.defensive_contacts[team] = []
	snapshot.los = {}
	var map: InfluenceMap = snapshot.maps[team]
	for cell: Vector2i in map.playable_cells:
		var cover: float = 0.0
		if LOSHelper.get_hex_distance(cell, objective) <= 1:
			cover = 0.5
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, cover)
		map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
		map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, cover * float(direction % 2))
		snapshot.los[cell] = {}
	for unit: Unit in defenders:
		snapshot.positions[unit] = unit.current_hex
		snapshot.teams[unit] = team
	for id: int in snapshot.routes[team].get_point_ids():
		snapshot.routes[team].set_point_disabled(id, false)
	var record: Dictionary = {"target_cover": 0.0, "hindrance": 0.0}
	var main_entry: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) + delta * 2)
	var flank_entry: Vector2i = ground.cube_to_map(ground.map_to_cube(objective) - delta * 2)
	snapshot.los[main_edge] = {main_entry: record, main_source: record}
	snapshot.los[flank_edge] = {flank_entry: record, flank_source: record}
	var sources: Array[Vector2i] = [main_source, flank_source]
	var area: DefenseAreaAssessment = _directional_area(snapshot, team, objective, sources, false)
	var planner: PlatoonAI = _directional_plan(snapshot, team, area, defenders, reserve)
	var request: PositionQuery = _reserve_request(planner, reserve)
	var main_key: String = DefenseAreaAssessment.duty_key(area.approaches[0])
	var flank_key: String = DefenseAreaAssessment.duty_key(area.approaches[1])
	_check(not planner.reserve_deployed and request.required_crossing_branch == flank_key, "For every direction and objective the reserve watches the remaining approach after combat-front allocation")
	_check(planner._planning_readiness.coverage[main_key] == 0.0, "A front assignment cannot invent established fire on its approach")
	var held: PositionResult = PositionQueryService.query_positions(request)
	_check(held.is_valid() and held.target_hex == flank_edge and not held.should_move, "The reserve retains useful opposite-side coverage instead of joining the strong attack")
	_check(_planned_role(planner, anchor) == "guard_objective", "Changing attack direction never swaps the tripod anchor into the mobile role")
	request.required_crossing_branch = main_key
	request.assigned_branch = main_key
	request.assigned_sector = area.approaches[0]["id"]
	var concentrated: PositionResult = PositionQueryService.query_positions(request)
	_check(not concentrated.is_valid() and concentrated.rejections.has("reserve_gap"), "Even an explicit strong-front duty cannot consume the quiet approach's timely reserve response")
	planner.free()
	area = _directional_area(snapshot, team, objective, sources, true)
	planner = _directional_plan(snapshot, team, area, defenders, reserve)
	request = _reserve_request(planner, reserve)
	_check(request.required_crossing_branch == main_key, "Reversing attack pressure reverses the reserve's residual duty without fixed map directions")
	var waiting: PositionResult = PositionQueryService.query_positions(request)
	_check(not waiting.is_valid() and (waiting.rejections.has("reserve_gap") or waiting.rejections.has("screen_gap")), "A direction change cannot abandon timely protection before another defender establishes the new front")
	planner.free()
	# A real covering position, rather than its future assignment, releases the reserve.
	var handoff: Vector2i = neighbors[(direction + 4) % 6]
	snapshot.los[handoff] = {flank_entry: record, flank_source: record}
	gun.current_hex = handoff
	snapshot.positions[gun as Unit] = handoff
	planner = _directional_plan(snapshot, team, area, defenders, reserve)
	request = _reserve_request(planner, reserve)
	var repositioned: PositionResult = PositionQueryService.query_positions(request)
	_check(planner._planning_readiness.coverage[flank_key] >= DefensePositionPolicy.MIN_APPROACH_COVERAGE and repositioned.is_valid() and repositioned.target_hex == main_edge, "Established new-front fire releases the reserve to the opposite approach on translated and rotated terrain")
	_check(repositioned.features.get("objective_connected_cover", false) and repositioned.features.get("open_crossing_seconds", INF) == 0.0, "Flexible reserve reassignment stays in connected cover and does not force an open crossing")
	planner.free()
	for unit: Unit in defenders:
		unit.squad_fire.free()
		unit.squad_fire = null
		unit.free()


func _test_sector_pressure_and_protected_reserve() -> void:
	var fixture: PositionQuery = _defense_fixture()
	var snapshot: InfluenceSnapshot = fixture.snapshot
	var pressure: DefensiveSectorPressure = DefensiveSectorPressure.new()
	var objective: Vector2i = Vector2i(4, 3)
	snapshot.objectives[own.team] = objective
	snapshot.contacts[own.team] = []
	snapshot.positions[enemy as Unit] = Vector2i(8, 3)
	var old_sector: int = DefenseAreaAssessment.sector_for(objective, Vector2i(8, 3))
	var new_sector: int = DefenseAreaAssessment.sector_for(objective, Vector2i(0, 3))
	var threat_before: PackedFloat32Array = snapshot.maps[own.team].get_layer_data_copy(InfluenceMap.Layer.THREAT)
	snapshot.captured_at = 100.0
	pressure.capture_into(snapshot, own.team)
	_check(snapshot.sector_pressure[own.team].is_empty(), "Hidden pressure is delayed rather than exposing current locations at startup")
	snapshot.positions[enemy as Unit] = Vector2i(0, 3)
	snapshot.captured_at = 103.0
	pressure.capture_into(snapshot, own.team)
	_check(snapshot.sector_pressure[own.team].is_empty(), "Hidden movement cannot update estimates before the four-second sample boundary")
	snapshot.captured_at = 104.0
	pressure.capture_into(snapshot, own.team)
	var prior_estimate: Dictionary = snapshot.sector_pressure[own.team]
	_check(prior_estimate.has(old_sector) and not prior_estimate.has(new_sector) and is_equal_approx(prior_estimate[old_sector]["pressure"], 0.125), "Published pressure uses the previous sample and smooths a quarter-weight hidden squad")
	snapshot.captured_at = 108.0
	pressure.capture_into(snapshot, own.team)
	_check(snapshot.sector_pressure[own.team].has(new_sector) and snapshot.sector_pressure[own.team][old_sector]["pressure"] < prior_estimate[old_sector]["pressure"] and prior_estimate.size() == 1, "A hidden flank shift appears gradually without mutating previously published estimates")
	_check(snapshot.maps[own.team].get_layer_data_copy(InfluenceMap.Layer.THREAT) == threat_before and snapshot.get_contacts(own.team).is_empty(), "Coarse hidden pressure never writes actual threat or creates firing contacts")
	var estimated_area: DefenseAreaJob = DefenseAreaJob.new()
	estimated_area.start(snapshot, own.team, objective, 5, 8, [])
	estimated_area.advance(-1)
	_check(estimated_area.result.approach_for_sector(new_sector)["evidence"] == "estimated" and estimated_area.result.approach_for_sector(new_sector)["source"] != snapshot.positions[enemy as Unit], "Hidden pressure creates an explicitly estimated terrain branch instead of a corridor anchored on the hidden hex")
	var observed: InfluenceContact = _area_contact(Vector2i(0, 3), 108.0)
	snapshot.contacts[own.team] = [observed]
	snapshot.captured_at = 112.0
	pressure.capture_into(snapshot, own.team)
	snapshot.captured_at = 116.0
	pressure.capture_into(snapshot, own.team)
	_check(snapshot.sector_pressure[own.team][new_sector]["pressure"] < 0.25, "Observed attackers stop contributing fresh hidden pressure instead of being counted twice")
	snapshot.objectives[own.team] = Vector2i(3, 3)
	pressure.capture_into(snapshot, own.team)
	_check(snapshot.sector_pressure[own.team].is_empty(), "Changing the objective resets delayed sector geography")
	pressure.clear()
	_check(pressure.published.is_empty() and not is_finite(pressure.sampled_at), "Resetting a match clears hidden estimates and pending samples")
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		_test_four_squad_reserve(team)
	_publish()


func _test_four_squad_reserve(team: Globals.Team) -> void:
	var rifle_weapon: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	var tripod_weapon: WeaponSpec = load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec
	var bipod_weapon: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	var anchor: UnitProbe = _unit(team, Vector2i(4, 3))
	var gun: UnitProbe = _unit(team, Vector2i(5, 3))
	var infantry: UnitProbe = _unit(team, Vector2i(5, 4))
	var reserve: UnitProbe = _unit(team, Vector2i(4, 4))
	anchor.squad_type = Globals.SquadType.MG
	gun.squad_type = Globals.SquadType.MG
	infantry.squad_type = Globals.SquadType.Rifle
	reserve.squad_type = Globals.SquadType.Rifle
	_equip(anchor, [tripod_weapon])
	_equip(gun, [bipod_weapon])
	_equip(infantry, [rifle_weapon])
	_equip(reserve, [rifle_weapon])
	var defenders: Array[Unit] = [anchor, gun, infantry, reserve]
	_publish()
	var snapshot: InfluenceSnapshot = controller.snapshot
	snapshot.contacts[team] = []
	snapshot.defensive_contacts[team] = []
	for cell: Vector2i in snapshot.maps[team].playable_cells:
		snapshot.maps[team].set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, 1.0)
		snapshot.maps[team].set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
	var area_job: DefenseAreaJob = DefenseAreaJob.new()
	area_job.start(snapshot, team, anchor.current_hex, 5, 8, [])
	area_job.advance(-1)
	var area: DefenseAreaAssessment = area_job.result
	var main_target: Vector2i = Vector2i(6, 3)
	var flank_target: Vector2i = Vector2i(0, 3)
	var record: Dictionary = {"target_cover": 0.0, "hindrance": 0.0}
	snapshot.los = snapshot.los.duplicate(true)
	for cell: Vector2i in snapshot.maps[team].playable_cells:
		snapshot.los[cell] = {}
		if cell.x <= 3:
			snapshot.los[cell][flank_target] = record
		else:
			snapshot.los[cell][main_target] = record
	var main: Dictionary = {"id": 0, "key": "main", "priority": 4.0, "source": Vector2i(8, 3), "evidence": "observed", "cells": [main_target], "weights": {main_target: 1.0}, "arrival_seconds": 20.0, "response_distances": area.geometry["response_fields"][0]}
	var flank: Dictionary = {"id": 3, "key": "flank", "priority": 0.3, "source": Vector2i(0, 3), "evidence": "estimated", "cells": [flank_target], "weights": {flank_target: 1.0}, "arrival_seconds": 20.0, "response_distances": area.geometry["response_fields"][3]}
	area.approaches = [main, flank]
	area.max_priority = 4.0
	var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
	readiness.start(area, snapshot, team, defenders, reserve, 5)
	readiness.advance(Time.get_ticks_usec() - 1)
	_check(not readiness.completed, "Reserve response work respects an exhausted frame budget")
	var slices: int = 0
	while not readiness.completed and slices < 10000:
		readiness.advance(Time.get_ticks_usec() + 100)
		slices += 1
	_check(readiness.completed and slices > 1 and readiness.coverage["main"] == 1.0 and readiness.coverage["flank"] == 0.0 and readiness.emergency == "", "Established MG coverage satisfies the attacked branch without releasing the rifle reserve")
	var query: PositionQuery = readiness.query
	query.reserve_position = true
	query.reserve_responses = readiness.responses
	var reserve_features: Dictionary = area.features(query, reserve.current_hex)
	_check(reserve_features["reserve_branch_status"]["main"]["protected"] and reserve_features["reserve_branch_status"]["flank"]["protected"] and reserve_features["reserve_branch_status"]["flank"]["response_seconds"] < 20.0, "A quiet low-priority flank is protected by timely response to covered interception ground")
	readiness.responses["flank"]["arrival_seconds"] = 0.5
	_check(not area.features(query, reserve.current_hex)["reserve_branch_status"]["flank"]["protected"], "A response arriving after the attacker cannot count as protection of an unattended branch")
	readiness.responses["flank"]["arrival_seconds"] = 20.0
	var graph: AStar2D = snapshot.routes[team]
	var disabled: Dictionary[int, bool] = {}
	for neighbor: Vector2i in LOSHelper.get_hex_neighbors(reserve.current_hex):
		var id: int = snapshot.point_ids[team][neighbor]
		disabled[id] = graph.is_point_disabled(id)
		graph.set_point_disabled(id, true)
	var blocked: DefenseReadinessJob = DefenseReadinessJob.new()
	blocked.start(area, snapshot, team, defenders, reserve, 5)
	blocked.advance(-1)
	_check(not is_finite(blocked.responses["flank"]["seconds"][reserve.current_hex]), "A blocked response route cannot protect an unattended approach")
	for id: int in disabled:
		graph.set_point_disabled(id, disabled[id])
	for neighbor: Vector2i in LOSHelper.get_hex_neighbors(reserve.current_hex):
		snapshot.maps[team].set_layer_value(InfluenceMap.Layer.THREAT, neighbor, 100.0)
	var dangerous: DefenseReadinessJob = DefenseReadinessJob.new()
	dangerous.start(area, snapshot, team, defenders, reserve, 5)
	dangerous.advance(-1)
	_check(not is_finite(dangerous.responses["flank"]["seconds"][reserve.current_hex]), "An exposed response exceeding the mission budget cannot count as ready protection")
	for neighbor: Vector2i in LOSHelper.get_hex_neighbors(reserve.current_hex):
		snapshot.maps[team].set_layer_value(InfluenceMap.Layer.THREAT, neighbor, 0.0)
	main["arrival_seconds"] = 8.0
	readiness.coverage["main"] = 0.0
	anchor.combat_stats.combat_effectiveness = 0.3
	_check(readiness._emergency_reason() == "failing_defense", "A weakened established defense with an imminent uncovered observed approach releases the reserve")
	anchor.combat_stats.combat_effectiveness = 1.0
	readiness.coverage["main"] = 1.0
	main["arrival_seconds"] = 20.0
	var assignments: Dictionary[Unit, String] = DefenseSectorAllocator.assign_branches(area, [infantry], {}, {"main": 1.0})
	_check(assignments[infantry as Unit] == "flank", "An already protected strong branch offers less reinforcement value than an unattended weaker branch")
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = team
	planner.influence_map_controller = controller
	planner.current_order = MissionOrder.new()
	planner.current_order.objective_hex = area.objective_hex
	planner.defense_area = area
	planner.reserve_squad = reserve
	planner._planning_snapshot = snapshot
	planner._planning_readiness = readiness
	planner._build_sector_requests(defenders.duplicate())
	_check(_planned_role(planner, anchor) == "guard_objective" and _planned_role(planner, reserve) == "reserve" and _planned_role(planner, gun) == "defend_sector" and _planned_role(planner, infantry) == "defend_sector", "Two MGs and two rifles retain an MG anchor, a rifle reserve and two approach defenders for either team")
	var reserve_query: PositionQuery = null
	for request: Dictionary in planner._planning_requests:
		if request["query"].unit == reserve:
			reserve_query = request["query"]
	_check(reserve_query != null and reserve_query.reserve_responses == readiness.responses and not planner.reserve_deployed, "Protected reserve advice carries response coverage instead of turning branch count into deployment")
	reserve_query.geography = PositionQuery.Geography.SECTOR_ONLY
	reserve_query.sector_cells = [reserve.current_hex]
	var hold: PositionResult = PositionQueryService.query_positions(reserve_query)
	_check(hold.is_valid() and not hold.should_move and hold.features["responsibility"] == "reserve", "Extra response estimates permit a useful covered reserve to hold without forcing a flank move")
	var reserve_job: PositionQueryJob = PositionQueryJob.new()
	reserve_job.query = reserve_query
	while not reserve_job.completed:
		reserve_job.advance(Time.get_ticks_usec() + 100)
	_check(reserve_job.result.target_hex == hold.target_hex and reserve_job.result.path == hold.path and reserve_job.result.features["reserve_branch_status"] == hold.features["reserve_branch_status"] and reserve_job.result.cell_states == hold.cell_states, "Budgeted reserve advice preserves response deadlines and diagnostic parity")
	reserve_query.route_field = null
	var intercept: Vector2i = Vector2i(3, 4)
	var intercept_response: float = readiness.responses["flank"]["seconds"][intercept]
	readiness.responses["flank"]["arrival_seconds"] = intercept_response + 0.1
	reserve_query.destination_features.clear()
	var settled: Dictionary = PositionFeatureEvaluator.evaluate(reserve_query, intercept, [])
	var mobilizing: Dictionary = PositionFeatureEvaluator.evaluate(reserve_query, intercept, [reserve.current_hex, intercept])
	_check(settled["reserve_branch_status"]["flank"]["protected"] and not mobilizing["reserve_branch_status"]["flank"]["protected"], "Reserve relocation and establishment time count against the interception deadline")
	readiness.responses["flank"]["arrival_seconds"] = 20.0
	reserve_query.destination_features.clear()
	var validation: DefensePlanValidationJob = DefensePlanValidationJob.new()
	validation.queries = [reserve_query]
	validation.results = [DefensePositionAnalyzer.adapt_result(hold, null, "reserve")]
	_check(not validation._reserve_can_intercept("main") and validation._reserve_can_intercept("flank"), "Publication does not treat a stale established-coverage flag as timely reserve response")
	var capability: String = reserve_query.context_key()
	reserve.squad_fire.soldiers[0].jammed = true
	_check(reserve_query.context_key() != capability and not PositionQueryService.query_positions(reserve_query).is_valid() and not validation._reserve_can_intercept("flank"), "Losing usable reserve weapons invalidates old response advice and branch protection")
	reserve.squad_fire.soldiers[0].jammed = false
	var speed: float = reserve.movement.move_speed
	reserve.movement.move_speed *= 0.5
	_check(reserve_query.context_key() != capability and not PositionQueryService.query_positions(reserve_query).is_valid(), "Slower reserve mobility invalidates previously computed interception times")
	reserve.movement.move_speed = speed
	var contact: InfluenceContact = _area_contact(area.objective_hex + Vector2i(1, 0), snapshot.captured_at)
	snapshot.contacts[team] = [contact]
	_check(readiness._emergency_reason() == "imminent_breach", "A confirmed attacker adjacent to the objective releases the reserve for an imminent breach")
	readiness.emergency = readiness._emergency_reason()
	planner._planning_requests.clear()
	planner._build_sector_requests(defenders.duplicate())
	_check(planner.reserve_deployed and planner.reserve_reason == "imminent_breach" and _planned_role(planner, reserve) == "defend_sector" and _planned_role(planner, anchor) == "guard_objective", "Emergency deployment retains the designated reserve identity and the stationary MG anchor")
	snapshot.contacts[team] = []
	readiness.emergency = ""
	snapshot.captured_at = 200.0
	planner._planning_requests.clear()
	planner._build_sector_requests(defenders.duplicate())
	_check(planner.reserve_deployed, "A brief lull cannot immediately rotate a deployed reserve back out of its duty")
	snapshot.captured_at = 209.0
	planner._planning_requests.clear()
	planner._build_sector_requests(defenders.duplicate())
	_check(not planner.reserve_deployed and _planned_role(planner, reserve) == "reserve" and planner.reserve_squad == reserve, "After sustained recovery the same squad resumes reserve duty through normal safe position advice")
	reserve.in_close_combat = true
	_check(not DefenseSectorAllocator.combat_reserve_capable(reserve), "A squad locked in close combat cannot count as an available mobile reserve")
	reserve.in_close_combat = false
	planner._readiness_job = DefenseReadinessJob.new()
	planner._readiness_job.start(area, snapshot, team, defenders, reserve, 5)
	planner.current_order.objective_hex += Vector2i(1, 0)
	planner._process(0.0)
	_check(planner._readiness_job == null and planner._planning_readiness == null, "An objective change cancels unfinished reserve response geography")
	planner.set_active(false)
	_check(planner.reserve_squad == null and not planner.reserve_deployed and planner._planning_readiness == null, "Player handoff releases protected reserve state and pending response work")
	planner.free()
	for unit: Unit in defenders:
		unit.squad_fire.free()
		unit.squad_fire = null
		unit.free()
