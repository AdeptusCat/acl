class_name InfluenceSnapshotBuilder
extends RefCounted


class CaptureJob extends RefCounted:
	enum Phase { CONFIGURE, TERRAIN, FRIENDLY, ENEMY, SUPPORT, ROUTE_POINTS, ROUTE_CONNECTIONS, FINISH }

	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	var completed: bool = false
	var phase: Phase = Phase.CONFIGURE
	var ground: HexagonTileMapLayer
	var cells: Array[Vector2i] = []
	var units: Array[Unit] = []
	var teams: Array[int] = [Globals.Team.ALLIES, Globals.Team.AXIS]
	var weights: PackedFloat32Array
	var sources: Dictionary[int, AStar2D] = {}
	var team_index: int = 0
	var cursor: int = 0
	var support: PackedFloat32Array
	var route_points: PackedInt64Array
	var route_ids: Dictionary = {}
	var route: AStar2D


	func start(version: int, objectives: Dictionary[int, Vector2i], policy: int, composite_weights: PackedFloat32Array) -> void:
		snapshot.version = version
		snapshot.captured_at = float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
		snapshot.objectives = objectives.duplicate()
		snapshot.los = LOSHelper.los_lookup
		ground = LOSHelper.ground_layer
		cells = ground.get_used_cells()
		weights = composite_weights.duplicate()
		# Capture live unit observations once, before any construction slices run.
		for unit: Unit in Globals.get_units():
			if not InfluenceUnitQuery.is_valid_living_unit(unit):
				continue
			units.append(unit)
			snapshot.positions[unit] = unit.current_hex
			snapshot.teams[unit] = unit.team
			var radius: int = 2
			if unit.leader_aura != null:
				radius = unit.leader_aura.aura_radius_hexes
			snapshot.support_units[unit] = {"headquarters": HqSupportPositionPolicy.is_headquarters(unit),
				"company": unit.company, "platoon": unit.platoon, "commander": unit.command_squad,
				"company_hq": unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS,
				"members": unit.members_alive, "radius": radius, "need": HqSupportNeedLayer.get_squad_support_need(unit),
				"surrendered": unit.surrendered, "effectiveness": InfluenceUnitQuery.get_unit_effectiveness(unit),
				"firepower": InfluenceUnitQuery.get_unit_firepower(unit), "weapon_range": InfluenceUnitQuery.get_unit_range(unit)}
		for team: int in teams:
			snapshot.contacts[team] = InfluenceUnitQuery.capture_contacts(team, policy)
			var source: AStar2D = Globals.astars.get(team, ground.astar)
			if source != null:
				sources[team] = source


	func advance(deadline_usec: int) -> void:
		while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
			_step()


	func _next_phase() -> void:
		phase = (int(phase) + 1) as Phase
		cursor = 0


	func _step() -> void:
		var team: int = teams[team_index]
		if phase == Phase.CONFIGURE:
			var map: InfluenceMap = InfluenceMap.new()
			map.configure(ground.get_used_rect())
			map.configure_composite_weights(weights, 0.0, 0.0, 20.0)
			snapshot.maps[team] = map
			support = PackedFloat32Array()
			support.resize(map.cell_count)
			_next_phase()
			return
		var map: InfluenceMap = snapshot.maps[team]
		match phase:
			Phase.TERRAIN:
				if cursor >= cells.size():
					_next_phase()
					return
				var cell: Vector2i = cells[cursor]
				map.playable_cells[cell] = true
				var cover: float = 0.0
				if is_instance_valid(LOSHelper.building_layer):
					cover = float(LOSHelper.is_sample_point_in_building(ground.map_to_local(cell)))
				map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, clampf(cover / 3.0, 0.0, 1.0))
				map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, minf(cover, 1.0))
			Phase.FRIENDLY:
				if cursor >= units.size():
					_next_phase()
					return
				var unit: Unit = units[cursor]
				if snapshot.teams[unit] == team:
					map.stamp_radius(InfluenceMap.Layer.UNIT_INFLUENCE, snapshot.positions[unit], 5, 5.0, InfluenceMap.WriteMode.ADD, InfluenceMap.FalloffMode.LINEAR)
					map.stamp_radius(InfluenceMap.Layer.FRIENDLY_SUPPORT, snapshot.positions[unit], 5, snapshot.support_units[unit]["effectiveness"], InfluenceMap.WriteMode.ADD, InfluenceMap.FalloffMode.LINEAR)
			Phase.ENEMY:
				var contacts: Array = snapshot.contacts[team]
				if cursor >= contacts.size():
					_next_phase()
					return
				var contact: InfluenceContact = contacts[cursor]
				map.stamp_radius(InfluenceMap.Layer.UNIT_INFLUENCE, contact.hex, 5, 5.0 * contact.confidence, InfluenceMap.WriteMode.SUBTRACT, InfluenceMap.FalloffMode.LINEAR)
				map.set_layer_value(InfluenceMap.Layer.KNOWN_ENEMY_POSITION, contact.hex, contact.confidence)
			Phase.SUPPORT:
				if cursor >= units.size():
					map.set_layer_data_copy(InfluenceMap.Layer.HQ_SUPPORT_NEED, support)
					_next_phase()
					if sources.has(team):
						route = AStar2D.new()
						route_ids = {}
						route_points = sources[team].get_point_ids()
					else:
						phase = Phase.FINISH
					return
				var unit: Unit = units[cursor]
				if snapshot.teams[unit] == team:
					HqSupportNeedLayer._write_squad_support_need(map, support, snapshot.positions[unit], snapshot.support_units[unit]["need"])
			Phase.ROUTE_POINTS:
				if cursor >= route_points.size():
					route_points = route.get_point_ids()
					_next_phase()
					return
				var id: int = route_points[cursor]
				var source: AStar2D = sources[team]
				var position: Vector2 = source.get_point_position(id)
				var cell: Vector2i = ground.local_to_map(position)
				if map.is_playable_cell(cell):
					route.add_point(id, position)
					route.set_point_disabled(id, source.is_point_disabled(id))
					route_ids[cell] = id
			Phase.ROUTE_CONNECTIONS:
				if cursor >= route_points.size():
					snapshot.routes[team] = route
					snapshot.point_ids[team] = route_ids
					_next_phase()
					return
				var id: int = route_points[cursor]
				var connections: PackedInt64Array = sources[team].get_point_connections(id)
				snapshot.route_topology_key = hash([snapshot.route_topology_key, id, connections])
				for other: int in connections:
					if route.has_point(other):
						route.connect_points(id, other, false)
			Phase.FINISH:
				team_index += 1
				if team_index < teams.size():
					phase = Phase.CONFIGURE
					cursor = 0
					return
				var terrain: InfluenceMap = snapshot.maps[Globals.Team.ALLIES]
				snapshot.terrain_key = hash([ground.get_instance_id(), terrain.bounds, snapshot.route_topology_key,
					terrain.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER), terrain.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_MOVE_COST)])
				completed = true
		cursor += 1


static func begin_capture(version: int, objectives: Dictionary[int, Vector2i], knowledge_policy: int, weights: PackedFloat32Array) -> CaptureJob:
	var job: CaptureJob = CaptureJob.new()
	job.start(version, objectives, knowledge_policy, weights)
	return job


static func capture(version: int, objectives: Dictionary[int, Vector2i], knowledge_policy: int, weights: PackedFloat32Array) -> InfluenceSnapshot:
	var job: CaptureJob = begin_capture(version, objectives, knowledge_policy, weights)
	job.advance(-1)
	return job.snapshot


static func copy_routes(snapshot: InfluenceSnapshot, team: int, source: AStar2D) -> void:
	var graph: AStar2D = AStar2D.new()
	var ids: Dictionary = {}
	for id: int in source.get_point_ids():
		var position: Vector2 = source.get_point_position(id)
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(position)
		if not snapshot.maps[team].is_playable_cell(cell):
			continue
		graph.add_point(id, position)
		graph.set_point_disabled(id, source.is_point_disabled(id))
		ids[cell] = id
	for id: int in graph.get_point_ids():
		snapshot.route_topology_key = hash([snapshot.route_topology_key, id, source.get_point_connections(id)])
		for other: int in source.get_point_connections(id):
			if graph.has_point(other):
				graph.connect_points(id, other, false)
	snapshot.routes[team] = graph
	snapshot.point_ids[team] = ids


static func finish_routes(snapshot: InfluenceSnapshot) -> void:
	for team: int in snapshot.routes:
		var graph: AStar2D = snapshot.routes[team]
		var map: InfluenceMap = snapshot.maps[team]
		for cell: Vector2i in snapshot.point_ids[team]:
			graph.set_point_weight_scale(snapshot.point_ids[team][cell], 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell) + 4.0 * PositionFeatureEvaluator.risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell)))
