class_name MoveRoutePlanner
extends RefCounted

const RISK_WEIGHT: float = 4.0
const COVER_WEIGHT: float = 2.0


static func crossing_cost(from_hex: Vector2i, to_hex: Vector2i, seconds: float, exposure: float) -> float:
	var record: Dictionary = LOSHelper.los_lookup.get(from_hex, {}).get(to_hex, {})
	var cover: float = maxf(0.0, float(record.get("target_cover", 0.0)))
	if is_instance_valid(LOSHelper.building_layer) and LOSHelper.building_layer.get_cell_source_id(to_hex) != -1:
		var tile: TileData = LOSHelper.building_layer.get_cell_tile_data(to_hex)
		var terrain_cover: float = float(LOSHelper.BUILDING_COVER)
		if tile != null and tile.has_custom_data("cover"):
			terrain_cover = float(tile.get_custom_data("cover"))
		cover = maxf(cover, terrain_cover)
	# Cover offsets slow terrain even without a known enemy; actual travel time stays unchanged.
	return seconds / (1.0 + COVER_WEIGHT * cover) + RISK_WEIGHT * seconds * exposure


class RouteGraph extends AStar2D:
	var movement: UnitMovement
	var cells: Dictionary[int, Vector2i] = {}
	var risks: Dictionary[Vector2i, float] = {}
	var edge_seconds: Dictionary[Vector2i, float] = {}
	var origin_id: int
	var origin_position: Vector2 = Vector2.INF

	func _compute_cost(from_id: int, to_id: int) -> float:
		var exposure: float = (risks[cells[from_id]] + risks[cells[to_id]]) * 0.5
		return MoveRoutePlanner.crossing_cost(cells[from_id], cells[to_id], crossing_seconds(from_id, to_id), exposure)

	func _estimate_cost(_from_id: int, _to_id: int) -> float:
		# Zero keeps the search exact for directed, time-weighted edges and a moving origin.
		return 0.0

	func crossing_seconds(from_id: int, to_id: int) -> float:
		var key: Vector2i = Vector2i(from_id, to_id)
		if not edge_seconds.has(key):
			var from_position: Vector2 = Vector2.INF
			if from_id == origin_id:
				from_position = origin_position
			edge_seconds[key] = movement.estimate_crossing_seconds(cells[from_id], cells[to_id], from_position)
		return edge_seconds[key]


var path: Array[Vector3i] = []
var travel_seconds: float = 0.0
var exposure_seconds: float = 0.0
var cost: float = 0.0


func evaluate_path(hexes: Array[Vector2i], team: int, movement: UnitMovement, contacts: Array[InfluenceContact], origin_position: Vector2 = Vector2.INF) -> void:
	path.clear()
	travel_seconds = 0.0
	exposure_seconds = 0.0
	cost = 0.0
	if hexes.is_empty() or not Globals.astars.has(team) or not is_instance_valid(LOSHelper.ground_layer):
		return
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var graph: AStar2D = Globals.astars[team]
	var previous_id: int = -1
	var risks: Dictionary[Vector2i, float] = {}
	for index: int in range(hexes.size()):
		var cell: Vector2i = hexes[index]
		var id: int = ground.pathfinding_get_point_id(cell)
		if not graph.has_point(id) or graph.is_point_disabled(id) or ground.local_to_map(graph.get_point_position(id)) != cell:
			path.clear()
			return
		if index > 0 and not graph.are_points_connected(previous_id, id, false):
			path.clear()
			return
		risks[cell] = ThreatMap.risk_at(cell, contacts, LOSHelper.los_lookup)
		path.append(ground.map_to_cube(cell))
		previous_id = id
		if index == 0:
			continue
		var from_position: Vector2 = Vector2.INF
		if index == 1:
			from_position = origin_position
		var seconds: float = movement.estimate_crossing_seconds(hexes[index - 1], cell, from_position)
		if not is_finite(seconds):
			path.clear()
			return
		travel_seconds += seconds
		exposure_seconds += seconds * (risks[hexes[index - 1]] + risks[cell]) * 0.5
		cost += crossing_cost(hexes[index - 1], cell, seconds, (risks[hexes[index - 1]] + risks[cell]) * 0.5)


func build(from_hex: Vector2i, to_hex: Vector2i, team: int, movement: UnitMovement, contacts: Array[InfluenceContact], origin_position: Vector2 = Vector2.INF) -> void:
	path.clear()
	travel_seconds = 0.0
	exposure_seconds = 0.0
	cost = 0.0
	if not is_instance_valid(LOSHelper.ground_layer) or not Globals.astars.has(team) or movement.move_speed <= 0.0:
		return
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var source: AStar2D = Globals.astars[team]
	var from_id: int = ground.pathfinding_get_point_id(from_hex)
	var to_id: int = ground.pathfinding_get_point_id(to_hex)
	if not source.has_point(from_id) or not source.has_point(to_id) or source.is_point_disabled(from_id) or source.is_point_disabled(to_id):
		return
	if ground.local_to_map(source.get_point_position(from_id)) != from_hex or ground.local_to_map(source.get_point_position(to_id)) != to_hex:
		return
	var graph: RouteGraph = RouteGraph.new()
	graph.movement = movement
	graph.origin_id = from_id
	graph.origin_position = origin_position
	for id: int in source.get_point_ids():
		var position: Vector2 = source.get_point_position(id)
		var cell: Vector2i = ground.local_to_map(position)
		graph.add_point(id, position)
		graph.set_point_disabled(id, source.is_point_disabled(id))
		graph.cells[id] = cell
		graph.risks[cell] = ThreatMap.risk_at(cell, contacts, LOSHelper.los_lookup)
	for id: int in source.get_point_ids():
		for neighbor: int in source.get_point_connections(id):
			graph.connect_points(id, neighbor, false)
	var ids: PackedInt64Array = graph.get_id_path(from_id, to_id)
	for index: int in range(ids.size()):
		var id: int = ids[index]
		path.append(ground.map_to_cube(graph.cells[id]))
		if index == 0:
			continue
		var previous: int = ids[index - 1]
		var seconds: float = graph.crossing_seconds(previous, id)
		travel_seconds += seconds
		exposure_seconds += seconds * (graph.risks[graph.cells[previous]] + graph.risks[graph.cells[id]]) * 0.5
		cost += graph._compute_cost(previous, id)
