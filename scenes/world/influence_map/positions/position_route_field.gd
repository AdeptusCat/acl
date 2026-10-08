class_name PositionRouteField
extends RefCounted

# Budgeted weighted flood; retain exact nondominated exposure alternatives until targets settle.
var labels: Array[Dictionary] = []
var labels_by_cell: Dictionary[Vector2i, Array] = {}
var frontier: Array[int] = []
var completed: bool = false
var expanded_labels: int = 0
var _query: PositionQuery
var _graph: AStar2D
var _ids: Dictionary
var _targets: Dictionary[Vector2i, bool] = {}
var _settled: Dictionary[Vector2i, int] = {}
var _steps: Dictionary[Vector2i, Dictionary] = {}
var _edges: Dictionary[Vector2i, Array] = {}
var _requested: Dictionary[Vector2i, bool] = {}
var _origin: Vector2i
var _bound_mode: int = -1
var _bounds_prepared: bool = false
var _saved_search: Dictionary = {}


func build(query: PositionQuery) -> void:
	var targets: Array[Vector2i] = []
	for cell: Vector2i in query.snapshot.point_ids.get(query.team, {}):
		targets.append(cell)
	start(query, targets)
	advance(-1)


func start(query: PositionQuery, targets: Array[Vector2i]) -> void:
	labels.clear()
	labels_by_cell.clear()
	frontier.clear()
	_targets.clear()
	_settled.clear()
	_steps.clear()
	_edges.clear()
	_requested.clear()
	_saved_search.clear()
	_bounds_prepared = false
	expanded_labels = 0
	completed = true
	_query = query
	if not query.snapshot.routes.has(query.team):
		return
	_graph = query.snapshot.routes[query.team]
	_ids = query.snapshot.point_ids[query.team]
	if not _ids.has(query.unit.current_hex) or _graph.is_point_disabled(_ids[query.unit.current_hex]):
		return
	for cell: Vector2i in targets:
		if _ids.has(cell) and not _graph.is_point_disabled(_ids[cell]):
			_targets[cell] = true
	if _targets.is_empty():
		return
	_requested = _targets.duplicate()
	_origin = query.unit.current_hex
	completed = false
	_bound_mode = -1
	_begin_phase()


func _begin_phase() -> void:
	labels = []
	labels_by_cell = {}
	frontier = []
	_settled = {}
	_targets = _requested.duplicate()
	if _targets.is_empty():
		completed = true
		return
	_add_label({"cell": _origin, "parent": -1, "cost": 0.0, "exposure": 0.0, "open_exposure": 0.0, "active": true})


func _finish_bound() -> void:
	var budget: float = _query.profile.max_exposure_seconds
	if _bound_mode == 1:
		budget = _query.profile.max_open_exposure_seconds
	for cell: Vector2i in _requested.keys():
		if not _settled.has(cell) or labels[_settled[cell]]["cost"] > budget:
			_requested.erase(cell)
	if _bound_mode == 0 and not _requested.is_empty():
		_bound_mode = 1
		_begin_phase()
	else:
		_bound_mode = -1
		_targets = _requested
		labels = _saved_search["labels"]
		labels_by_cell = _saved_search["labels_by_cell"]
		frontier = _saved_search["frontier"]
		_settled = _saved_search["settled"]
		_requested = _saved_search["requested"]
		_saved_search.clear()
		if _targets.is_empty():
			completed = true


func advance(deadline_usec: int) -> void:
	while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		# Cheap searches finish directly; difficult searches rule out impossible remaining targets.
		if _bound_mode < 0 and not _bounds_prepared and expanded_labels >= 256 and not _query.snapshot.get_defensive_contacts(_query.team).is_empty():
			_bounds_prepared = true
			_saved_search = {"labels": labels, "labels_by_cell": labels_by_cell, "frontier": frontier, "settled": _settled, "requested": _requested}
			_requested = _targets.duplicate()
			_bound_mode = 0
			_begin_phase()
		if frontier.is_empty():
			if _bound_mode >= 0:
				_finish_bound()
				continue
			completed = true
			break
		var index: int = _pop()
		var label: Dictionary = labels[index]
		if not label["active"]:
			continue
		if not _settled.has(label["cell"]):
			_settled[label["cell"]] = index
			_targets.erase(label["cell"])
			if _targets.is_empty():
				if _bound_mode >= 0:
					_finish_bound()
					continue
				completed = true
				break
		expanded_labels += 1
		for edge: Dictionary in _neighbor_edges(label["cell"]):
			if _bound_mode >= 0:
				var cost: float = edge["exposure"]
				if _bound_mode == 1:
					cost = edge["open_exposure"]
				_add_label({"cell": edge["cell"], "parent": index, "cost": label["cost"] + cost, "exposure": 0.0, "open_exposure": 0.0, "active": true})
				continue
			var exposure: float = label["exposure"] + edge["exposure"]
			var open_exposure: float = label["open_exposure"] + edge["open_exposure"]
			if exposure > _query.profile.max_exposure_seconds or open_exposure > _query.profile.max_open_exposure_seconds:
				continue
			_add_label({"cell": edge["cell"], "parent": index, "cost": label["cost"] + edge["cost"], "exposure": exposure, "open_exposure": open_exposure, "active": true})


func step_data(cell: Vector2i) -> Dictionary:
	if not _steps.has(cell):
		_steps[cell] = PositionFeatureEvaluator.route_step(_query, cell)
	return _steps[cell]


func _neighbor_edges(from: Vector2i) -> Array:
	if _edges.has(from):
		return _edges[from]
	var edges: Array[Dictionary] = []
	for neighbor: int in _graph.get_point_connections(_ids[from]):
		if _graph.is_point_disabled(neighbor):
			continue
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(_graph.get_point_position(neighbor))
		var step: Dictionary = step_data(cell)
		if step["risk"] > _query.profile.max_route_exposure or _query.snapshot.maps[_query.team].get_layer_value(InfluenceMap.Layer.NO_GO, cell) > 0.0:
			continue
		var seconds: float = PositionFeatureEvaluator.crossing_seconds(_query, from, cell)
		if not is_finite(seconds):
			continue
		edges.append({"cell": cell, "exposure": seconds * step["risk"], "open_exposure": seconds * step["open_fire"],
			"cost": seconds * (1.0 + _query.profile.exposure_weight * step["risk"] + _query.profile.open_ground_weight * (1.0 - step["cover"]))})
	_edges[from] = edges
	return edges


func path_to(cell: Vector2i) -> Array[Vector2i]:
	var best: int = _settled.get(cell, -1)
	var path: Array[Vector2i] = []
	while best >= 0:
		path.append(labels[best]["cell"])
		best = labels[best]["parent"]
	path.reverse()
	return path


func release_query() -> void:
	_query = null


func _add_label(label: Dictionary) -> void:
	var cell: Vector2i = label["cell"]
	var existing: Array = labels_by_cell.get(cell, [])
	for index: int in existing:
		if _dominates(labels[index], label):
			return
	var remaining: Array[int] = []
	for index: int in existing:
		if _dominates(label, labels[index]):
			labels[index]["active"] = false
		else:
			remaining.append(index)
	var index: int = labels.size()
	labels.append(label)
	remaining.append(index)
	labels_by_cell[cell] = remaining
	frontier.append(index)
	var child: int = frontier.size() - 1
	while child > 0:
		var parent: int = (child - 1) / 2
		if not _cheaper(frontier[child], frontier[parent]):
			break
		var swapped: int = frontier[parent]
		frontier[parent] = frontier[child]
		frontier[child] = swapped
		child = parent


func _dominates(first: Dictionary, second: Dictionary) -> bool:
	if _bound_mode >= 0:
		return first["cost"] <= second["cost"]
	return first["cost"] <= second["cost"] + 0.000001 and first["exposure"] <= second["exposure"] + 0.000001 and first["open_exposure"] <= second["open_exposure"] + 0.000001


func _cheaper(first: int, second: int) -> bool:
	if labels[first]["cost"] == labels[second]["cost"]:
		return first < second
	return labels[first]["cost"] < labels[second]["cost"]


func _pop() -> int:
	var index: int = frontier[0]
	var last: int = frontier.pop_back()
	if frontier.is_empty():
		return index
	frontier[0] = last
	var parent: int = 0
	while parent * 2 + 1 < frontier.size():
		var child: int = parent * 2 + 1
		if child + 1 < frontier.size() and _cheaper(frontier[child + 1], frontier[child]):
			child += 1
		if not _cheaper(frontier[child], frontier[parent]):
			break
		var swapped: int = frontier[parent]
		frontier[parent] = frontier[child]
		frontier[child] = swapped
		parent = child
	return index
