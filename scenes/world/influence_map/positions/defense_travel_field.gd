class_name DefenseTravelField
extends RefCounted

# Scalar terrain travel cost. This predicts approaches, independently of defender danger.
var distances: Dictionary[Vector2i, float] = {}
var next_cells: Dictionary[Vector2i, Vector2i] = {}
var completed: bool = false
var geometry: Dictionary
var reverse: bool = false
var cost_key: String = "costs"
var _heap: Array[Dictionary] = []


func start(area_geometry: Dictionary, source: Vector2i, reversed: bool = false) -> void:
	start_sources(area_geometry, [source], reversed)


func start_sources(area_geometry: Dictionary, sources: Array[Vector2i], reversed: bool = false, costs: String = "costs") -> void:
	distances.clear()
	next_cells.clear()
	_heap.clear()
	completed = false
	geometry = area_geometry
	reverse = reversed
	cost_key = costs
	for source: Vector2i in sources:
		if geometry["neighbors"].has(source):
			distances[source] = 0.0
			_push({"cell": source, "cost": 0.0})
	completed = _heap.is_empty()


func advance(deadline_usec: int) -> void:
	while not _heap.is_empty() and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		var item: Dictionary = _pop()
		var cell: Vector2i = item["cell"]
		var cost: float = item["cost"]
		if cost > distances.get(cell, INF):
			continue
		for neighbor: Vector2i in geometry["neighbors"][cell]:
			var destination: Vector2i = neighbor
			if reverse:
				destination = cell
			var next_cost: float = cost + geometry[cost_key][destination]
			if next_cost < distances.get(neighbor, INF):
				distances[neighbor] = next_cost
				next_cells[neighbor] = cell
				_push({"cell": neighbor, "cost": next_cost})
	completed = _heap.is_empty()


func _push(item: Dictionary) -> void:
	_heap.append(item)
	var index: int = _heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if _heap[parent]["cost"] <= item["cost"]:
			break
		_heap[index] = _heap[parent]
		index = parent
	_heap[index] = item


func _pop() -> Dictionary:
	var first: Dictionary = _heap[0]
	var last: Dictionary = _heap.pop_back()
	if not _heap.is_empty():
		var index: int = 0
		while index * 2 + 1 < _heap.size():
			var child: int = index * 2 + 1
			if child + 1 < _heap.size() and _heap[child + 1]["cost"] < _heap[child]["cost"]:
				child += 1
			if last["cost"] <= _heap[child]["cost"]:
				break
			_heap[index] = _heap[child]
			index = child
		_heap[index] = last
	return first
