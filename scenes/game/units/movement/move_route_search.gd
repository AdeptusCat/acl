class_name MoveRouteSearch
extends RefCounted

# Search backward from the destination so movement during the search cannot stale its origin.
enum Phase { POINTS, EDGES, SEARCH }

var completed: bool = false
var phase: Phase = Phase.POINTS
var contacts: Array[InfluenceContact] = []
var movement: UnitMovement
var team: int
var destination: Vector2i
var _source: AStar2D
var _points: PackedInt64Array = PackedInt64Array()
var _cursor: int = 0
var _cells: Dictionary[int, Vector2i] = {}
var _ids: Dictionary[Vector2i, int] = {}
var _risks: Dictionary[int, float] = {}
var _incoming: Dictionary[int, Array] = {}
var _costs: Dictionary[int, float] = {}
var _next: Dictionary[int, int] = {}
var _frontier: Array[Dictionary] = []
var _goal: int = -1


func start(owner: UnitMovement, target: Vector2i, captured: Array[InfluenceContact]) -> void:
	movement = owner
	team = owner.unit.team
	destination = target
	contacts = captured
	_source = Globals.astars.get(team)
	if _source == null:
		completed = true
		return
	_points = _source.get_point_ids()


func advance(deadline_usec: int) -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		completed = true
	while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		match phase:
			Phase.POINTS:
				if _cursor >= _points.size():
					phase = Phase.EDGES
					_cursor = 0
					continue
				var id: int = _points[_cursor]
				_cursor += 1
				if _source.is_point_disabled(id):
					continue
				var cell: Vector2i = LOSHelper.ground_layer.local_to_map(_source.get_point_position(id))
				_cells[id] = cell
				_ids[cell] = id
				_risks[id] = ThreatMap.risk_at(cell, contacts, LOSHelper.los_lookup)
				_incoming[id] = []
			Phase.EDGES:
				if _cursor >= _points.size():
					_goal = _ids.get(destination, -1)
					if _goal < 0:
						completed = true
						continue
					_costs[_goal] = 0.0
					_push(_goal, 0.0)
					phase = Phase.SEARCH
					continue
				var id: int = _points[_cursor]
				_cursor += 1
				if not _cells.has(id):
					continue
				for neighbor: int in _source.get_point_connections(id):
					if not _cells.has(neighbor):
						continue
					var seconds: float = movement.estimate_crossing_seconds(_cells[id], _cells[neighbor])
					if not is_finite(seconds):
						continue
					var risk: float = (_risks[id] + _risks[neighbor]) * 0.5
					_incoming[neighbor].append({"from": id, "cost": MoveRoutePlanner.crossing_cost(_cells[id], _cells[neighbor], seconds, risk)})
			Phase.SEARCH:
				if _frontier.is_empty():
					completed = true
					continue
				var current: Dictionary = _pop()
				var id: int = current["id"]
				if current["cost"] > _costs[id]:
					continue
				for edge: Dictionary in _incoming[id]:
					var previous: int = edge["from"]
					var cost: float = current["cost"] + edge["cost"]
					if cost >= _costs.get(previous, INF):
						continue
					_costs[previous] = cost
					_next[previous] = id
					_push(previous, cost)


func path_from(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not completed or not _ids.has(cell) or not _costs.has(_ids[cell]):
		return result
	var id: int = _ids[cell]
	for index: int in range(_cells.size()):
		result.append(_cells[id])
		if id == _goal:
			return result
		if not _next.has(id):
			return []
		id = _next[id]
	return []


func _push(id: int, cost: float) -> void:
	_frontier.append({"id": id, "cost": cost})
	var child: int = _frontier.size() - 1
	while child > 0:
		var parent: int = (child - 1) / 2
		if _frontier[parent]["cost"] <= cost:
			break
		var swapped: Dictionary = _frontier[parent]
		_frontier[parent] = _frontier[child]
		_frontier[child] = swapped
		child = parent


func _pop() -> Dictionary:
	var result: Dictionary = _frontier[0]
	var last: Dictionary = _frontier.pop_back()
	if _frontier.is_empty():
		return result
	_frontier[0] = last
	var parent: int = 0
	while parent * 2 + 1 < _frontier.size():
		var child: int = parent * 2 + 1
		if child + 1 < _frontier.size() and _frontier[child + 1]["cost"] < _frontier[child]["cost"]:
			child += 1
		if _frontier[parent]["cost"] <= _frontier[child]["cost"]:
			break
		var swapped: Dictionary = _frontier[parent]
		_frontier[parent] = _frontier[child]
		_frontier[child] = swapped
		parent = child
	return result
