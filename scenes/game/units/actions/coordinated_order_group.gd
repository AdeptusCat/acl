class_name CoordinatedOrderGroup
extends RefCounted

static var _next_number: int = 1
var number: int
var members: Array[WeakRef] = []
var released: bool = false
var armed: bool = false


func _init() -> void:
	number = _next_number
	_next_number += 1


func add_member(queue: SquadOrderQueue) -> void:
	members.append(weakref(queue))


func status() -> Dictionary:
	var total: int = 0
	var ready: int = 0
	var blockers: PackedStringArray = []
	for reference: WeakRef in members:
		var queue: SquadOrderQueue = reference.get_ref() as SquadOrderQueue
		if queue == null or not queue.available() or not queue.contains_group(self):
			continue
		total += 1
		if queue.waiting_for(self):
			ready += 1
		else:
			var reason: String = "Orders pending"
			if queue.unit.stress_system.state == STATES.MoraleState.PINNED:
				reason = "Pinned"
			elif not queue.failure.is_empty():
				reason = queue.failure
			elif not queue.current.is_empty():
				reason = SquadOrderQueue.describe(queue.current)
			blockers.append(queue.unit.get_hud_name() + ": " + reason)
	return {"ready": ready, "total": total, "blockers": blockers}


func try_release() -> bool:
	if released:
		return true
	if not armed:
		return false
	var state: Dictionary = status()
	if int(state["ready"]) == int(state["total"]):
		released = true
	return released
