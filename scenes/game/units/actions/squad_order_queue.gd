class_name SquadOrderQueue
extends Node

enum Kind { MOVE, WATCH, HOLD }

var unit: Unit
var current: Dictionary = {}
var pending: Array[Dictionary] = []
var failure: String = ""
var issuing: bool = false
var _order_id: int = -1


func available() -> bool:
	return is_instance_valid(unit) and unit.is_active() and not unit.surrendered and not unit.broken and not unit.in_close_combat


func can_append(kind: Kind) -> bool:
	if not available():
		return false
	var last: Dictionary = current
	if not pending.is_empty():
		last = pending.back()
	if not last.is_empty() and int(last["kind"]) in [Kind.WATCH, Kind.HOLD]:
		return false
	return kind in [Kind.MOVE, Kind.WATCH, Kind.HOLD]


func append(kind: Kind, target: Vector2i = Vector2i.ZERO) -> bool:
	if not can_append(kind):
		return false
	# Adopt an existing move when Shift is first used partway through a route.
	if current.is_empty() and unit.movement.is_moving:
		current = {"kind": Kind.MOVE, "target": unit.movement.target_hex}
		_order_id = unit.action_controller.action_order_id
	var entry: Dictionary = {"kind": kind, "target": target}
	pending.append(entry)
	set_process(true)
	return true


func cancel() -> void:
	if issuing:
		return
	if current.get("kind", -1) == Kind.WATCH:
		unit.clear_watch_order()
	current.clear()
	pending.clear()
	failure = ""
	set_process(false)


func remove(index: int) -> void:
	if index == 0 and not current.is_empty():
		cancel_current()
		return
	var offset: int = index
	if not current.is_empty():
		offset -= 1
	if offset >= 0 and offset < pending.size():
		pending.remove_at(offset)


func cancel_current() -> void:
	if current.get("kind", -1) == Kind.WATCH:
		unit.clear_watch_order()
	current.clear()
	failure = ""
	issuing = true
	unit.clear_orders()
	issuing = false
	set_process(true)


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not current.is_empty():
		result.append(current)
	result.append_array(pending)
	return result


func planned_origin() -> Vector2i:
	var origin: Vector2i = unit.current_hex
	if unit.movement.is_moving:
		origin = unit.movement.target_hex
	for entry: Dictionary in entries():
		if int(entry["kind"]) == Kind.MOVE:
			origin = entry["target"]
	return origin


static func describe(entry: Dictionary) -> String:
	var target: Vector2i = entry["target"]
	match int(entry["kind"]):
		Kind.MOVE:
			return "Move to (%d, %d)" % [target.x, target.y]
		Kind.WATCH:
			return "Watch toward (%d, %d)" % [target.x, target.y]
		Kind.HOLD:
			return "Hold position"
	return "Unknown order"


func status_text() -> String:
	if unit.stress_system.state == STATES.MoraleState.PINNED:
		return "Pinned"
	if not failure.is_empty():
		return failure
	if current.is_empty():
		return "Orders pending"
	return describe(current)


func _process(_delta: float) -> void:
	if not available():
		cancel()
		return
	if not current.is_empty() and _order_id != unit.action_controller.action_order_id:
		cancel()
		return
	if unit.stress_system.state == STATES.MoraleState.PINNED or not failure.is_empty():
		return
	if current.is_empty():
		if pending.is_empty():
			set_process(false)
			return
		current = pending.pop_front()
		_start_current()
		return
	match int(current["kind"]):
		Kind.MOVE:
			if unit.movement.is_moving:
				return
			if unit.current_hex == Vector2i(current["target"]):
				current = {}
			else:
				# Pinning clears the live path; resume the same order after recovery.
				_start_current()


func _start_current() -> void:
	issuing = true
	var target: Vector2i = current["target"]
	match int(current["kind"]):
		Kind.MOVE:
			if unit.current_hex != target or unit.position.distance_to(LOSHelper.ground_layer.map_to_local(target)) > 0.1:
				var path: Array[Vector3i] = MovementSystem._compute_path(unit.current_hex, target, unit.team, unit)
				if path.is_empty():
					failure = "No route to (%d, %d); remove this order to continue." % [target.x, target.y]
				else:
					unit.give_move_to_hex_order(target, path, false)
					MovementSystem.watch_move_order(unit, target)
		Kind.WATCH:
			_hold_position()
			var target_position: Vector2 = LOSHelper.ground_layer.to_global(LOSHelper.ground_layer.map_to_local(target))
			if not unit.set_watch_direction(target_position - unit.global_position):
				failure = "Cannot watch toward this hex; remove this order to continue."
		Kind.HOLD:
			_hold_position()
	_order_id = unit.action_controller.action_order_id
	issuing = false


func _hold_position() -> void:
	unit.setAttackState(Unit.AttackState.AUTO)
	unit.squad_fire.clear_target()
	unit.give_hold_order()
