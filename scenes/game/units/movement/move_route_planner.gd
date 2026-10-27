class_name MoveRoutePlanner
extends RefCounted

const RISK_WEIGHT: float = 4.0


class RouteGraph extends AStar2D:
	var movement: UnitMovement
	var cells: Dictionary[int, Vector2i] = {}
	var risks: Dictionary[Vector2i, float] = {}
	var edge_seconds: Dictionary[Vector2i, float] = {}
	var origin_id: int
	var origin_position: Vector2 = Vector2.INF

	func _compute_cost(from_id: int, to_id: int) -> float:
		var exposure: float = (risks[cells[from_id]] + risks[cells[to_id]]) * 0.5
		return crossing_seconds(from_id, to_id) * (1.0 + RISK_WEIGHT * exposure)

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
	cost = travel_seconds + RISK_WEIGHT * exposure_seconds
