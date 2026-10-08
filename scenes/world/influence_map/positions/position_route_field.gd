class_name PositionRouteField
extends RefCounted

# Weighted flood with nondominated labels: a fast exposed path must not hide a slower safe one.
var labels: Array[Dictionary] = []
var labels_by_cell: Dictionary[Vector2i, Array] = {}
var frontier: Array[int] = []


func build(query: PositionQuery) -> void:
	labels.clear()
	labels_by_cell.clear()
	frontier.clear()
	if not query.snapshot.routes.has(query.team) or not query.snapshot.point_ids[query.team].has(query.unit.current_hex):
		return
	var graph: AStar2D = query.snapshot.routes[query.team]
	var ids: Dictionary = query.snapshot.point_ids[query.team]
	if graph.is_point_disabled(ids[query.unit.current_hex]):
		return
	var steps: Dictionary[Vector2i, Dictionary] = {}
	for cell: Vector2i in ids:
		steps[cell] = PositionFeatureEvaluator.route_step(query, cell)
	_add_label({"cell": query.unit.current_hex, "parent": -1, "cost": 0.0, "exposure": 0.0, "open_exposure": 0.0, "active": true})
	while not frontier.is_empty():
		var index: int = _pop()
		var label: Dictionary = labels[index]
		if not label["active"]:
			continue
		for neighbor: int in graph.get_point_connections(ids[label["cell"]]):
			if graph.is_point_disabled(neighbor):
				continue
			var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(neighbor))
			var step: Dictionary = steps[cell]
			if step["risk"] > query.profile.max_route_exposure or query.snapshot.maps[query.team].get_layer_value(InfluenceMap.Layer.NO_GO, cell) > 0.0:
				continue
			var seconds: float = PositionFeatureEvaluator.crossing_seconds(query, label["cell"], cell)
			if not is_finite(seconds):
				continue
			var exposure: float = label["exposure"] + seconds * step["risk"]
			var open_exposure: float = label["open_exposure"] + seconds * step["open_fire"]
			if exposure > query.profile.max_exposure_seconds or open_exposure > query.profile.max_open_exposure_seconds:
				continue
			var cost: float = label["cost"] + seconds * (1.0 + query.profile.exposure_weight * step["risk"] + query.profile.open_ground_weight * (1.0 - step["cover"]))
			_add_label({"cell": cell, "parent": index, "cost": cost, "exposure": exposure, "open_exposure": open_exposure, "active": true})


func path_to(cell: Vector2i) -> Array[Vector2i]:
	var best: int = -1
	for index: int in labels_by_cell.get(cell, []):
		if labels[index]["active"] and (best < 0 or labels[index]["cost"] < labels[best]["cost"]):
			best = index
	var path: Array[Vector2i] = []
	while best >= 0:
		path.append(labels[best]["cell"])
		best = labels[best]["parent"]
	path.reverse()
	return path


func _add_label(label: Dictionary) -> void:
	var cell: Vector2i = label["cell"]
	var existing: Array = labels_by_cell.get(cell, [])
	for index: int in existing:
		if labels[index]["active"] and _dominates(labels[index], label):
			return
	for index: int in existing:
		if labels[index]["active"] and _dominates(label, labels[index]):
			labels[index]["active"] = false
	var index: int = labels.size()
	labels.append(label)
	existing.append(index)
	labels_by_cell[cell] = existing
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


static func _dominates(first: Dictionary, second: Dictionary) -> bool:
	return first["cost"] <= second["cost"] + 0.000001 and first["exposure"] <= second["exposure"] + 0.000001 and first["open_exposure"] <= second["open_exposure"] + 0.000001


func _cheaper(first: int, second: int) -> bool:
	if is_equal_approx(labels[first]["cost"], labels[second]["cost"]):
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
