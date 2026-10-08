class_name InfluenceSnapshotBuilder
extends RefCounted


static func capture(version: int, objectives: Dictionary[int, Vector2i], knowledge_policy: int, weights: PackedFloat32Array) -> InfluenceSnapshot:
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.version = version
	snapshot.captured_at = float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	snapshot.objectives = objectives.duplicate()
	snapshot.los = LOSHelper.los_lookup
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var cells: Array[Vector2i] = ground.get_used_cells()
	for unit: Unit in Globals.get_units():
		if InfluenceUnitQuery.is_valid_living_unit(unit):
			snapshot.positions[unit] = unit.current_hex
			snapshot.teams[unit] = unit.team
	for team: int in [Globals.Team.ALLIES, Globals.Team.AXIS]:
		var map: InfluenceMap = InfluenceMap.new()
		map.configure(ground.get_used_rect())
		map.configure_composite_weights(weights, 0.0, 0.0, 20.0)
		snapshot.maps[team] = map
		snapshot.contacts[team] = InfluenceUnitQuery.capture_contacts(team, knowledge_policy)
		for cell: Vector2i in cells:
			map.playable_cells[cell] = true
			var cover: float = 0.0
			if is_instance_valid(LOSHelper.building_layer):
				cover = float(LOSHelper.is_sample_point_in_building(ground.map_to_local(cell)))
			map.set_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell, clampf(cover / 3.0, 0.0, 1.0))
			map.set_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell, minf(cover, 1.0))
		for unit: Unit in snapshot.positions:
			if snapshot.teams[unit] == team:
				map.stamp_radius(InfluenceMap.Layer.UNIT_INFLUENCE, snapshot.positions[unit], 5, 5.0, InfluenceMap.WriteMode.ADD, InfluenceMap.FalloffMode.LINEAR)
				map.stamp_radius(InfluenceMap.Layer.FRIENDLY_SUPPORT, snapshot.positions[unit], 5, InfluenceUnitQuery.get_unit_effectiveness(unit), InfluenceMap.WriteMode.ADD, InfluenceMap.FalloffMode.LINEAR)
		for contact: InfluenceContact in snapshot.get_contacts(team):
			map.stamp_radius(InfluenceMap.Layer.UNIT_INFLUENCE, contact.hex, 5, 5.0 * contact.confidence, InfluenceMap.WriteMode.SUBTRACT, InfluenceMap.FalloffMode.LINEAR)
			map.set_layer_value(InfluenceMap.Layer.KNOWN_ENEMY_POSITION, contact.hex, contact.confidence)
		var squads: Array[Unit] = InfluenceUnitQuery.get_config_units(team, "")
		map.set_layer_data_copy(InfluenceMap.Layer.HQ_SUPPORT_NEED, HqSupportNeedLayer.build_squad_support_need_layer(map, squads))
		var source: AStar2D = Globals.astars.get(team, ground.astar)
		if source != null:
			copy_routes(snapshot, team, source)
	var map: InfluenceMap = snapshot.maps[Globals.Team.ALLIES]
	snapshot.terrain_key = hash([ground.get_instance_id(), map.bounds, snapshot.route_topology_key,
		map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER), map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_MOVE_COST)])
	return snapshot


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
