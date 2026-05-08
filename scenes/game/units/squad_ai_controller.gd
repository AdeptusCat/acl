class_name SquadAiController
extends Node

#Squad Layer
#System: Behavior Tree + Utility AI
#Purpose: execute orders while reacting to danger

@export var decision_interval: float = 0.50

var unit: Unit = null
var current_order: AiOrder = null
var decision_timer: float = 0.0

var withdraw_active: bool = false

func setup(p_unit: Unit) -> void:
	unit = p_unit


func set_order(order: AiOrder) -> void:
	current_order = order


func _physics_process(delta: float) -> void:
	if unit == null:
		return

	decision_timer += delta

	if decision_timer >= decision_interval:
		decision_timer = 0.0
		_decision_tick()


func _decision_tick() -> void:
	if unit.stress_system.state == STATES.MoraleState.PANIC:
		#_retreat_to_cover()
		return
	
	if unit.stress_system.state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		#_withdraw_or_merge()
		return
	
	if unit.stress_system.state == STATES.MoraleState.PINNED:
		#_handle_pinned()
		return
	
	if unit.combat_stats.combat_effectiveness < 0.20:
		_withdraw_or_merge()
		return
	withdraw_active = false
	
	if unit.combat_stats.combat_effectiveness < 0.35:
		_rally_or_hold()
		return
	
	if current_order == null:
		#_hold_position()
		return
	
	_execute_order()


func _execute_order() -> void:
	if current_order.order_type == AiOrder.OrderType.HOLD:
		_hold_position()
	elif current_order.order_type == AiOrder.OrderType.MOVE_TO:
		_move_to_order_target()
	elif current_order.order_type == AiOrder.OrderType.SUPPRESS:
		_suppress_order_target()
	elif current_order.order_type == AiOrder.OrderType.ASSAULT:
		_assault_order_target()
	elif current_order.order_type == AiOrder.OrderType.WITHDRAW:
		_withdraw_to_order_target()
	elif current_order.order_type == AiOrder.OrderType.RALLY:
		_rally_or_hold()
	else:
		_hold_position()
	
	if not current_order.order_type == AiOrder.OrderType.WITHDRAW:
		withdraw_active = false


func _hold_position() -> void:
	unit.movement.stop()


func _move_to_order_target() -> void:
	if not current_order.allow_movement:
		return

	if unit.stress_system.state == STATES.MoraleState.PINNED:
		return

	unit.movement.move_to_hex(current_order.target_hex)


func _suppress_order_target() -> void:
	if current_order.target_unit != null:
		unit.squad_fire.set_target(current_order.target_unit)
		return


func _assault_order_target() -> void:
	if not current_order.allow_assault:
		_suppress_order_target()
		return

	if unit.combat_stats.combat_effectiveness < 0.60:
		_suppress_order_target()
		return
	
	#print(unit.stress_system.state)
	#print(STATES.MoraleState.NORMAL)
	#print(STATES.MoraleState.CAUTIOUS)
	#print(" #")
	if unit.stress_system.state != STATES.MoraleState.NORMAL and unit.stress_system.state != STATES.MoraleState.CAUTIOUS:
		_suppress_order_target()
		return

	unit.movement.move_to_hex(current_order.target_hex)


func _withdraw_to_order_target() -> void:
	#unit.squad_fire.set_target(null)
	if withdraw_active:
		return
	withdraw_active = true
	#var path: Array[Vector3i] = MovementSystem._compute_path(unit.current_hex, current_order.target_hex, unit.team)
	#unit.give_move_to_hex_order(current_order.target_hex, path, false)
	#unit.movement.move_to_hex(current_order.target_hex)
	unit.order(Globals.UnitCmd.MOVE, current_order.target_hex)


func _rally_or_hold() -> void:
	unit.movement.stop()


#func _retreat_to_cover() -> void:
	#unit.combat.clear_target()
#
	#var cover_hex: Vector2i = _find_nearest_cover_hex()
#
	#if cover_hex != Vector2i.ZERO:
		#unit.movement.move_to_hex(cover_hex)


func _withdraw_or_merge() -> void:
	if withdraw_active:
		return
	withdraw_active = true
	var known_enemies: Array[Unit] = []
	#var i: int = 0
	#while i < unit.units.size():
		#var u: Unit = unit.units[i]
		#if u.team != unit.team and u.surrendered == false:
			#known_enemies.append(u)
		#i += 1
	var visible_enemies1: Array = Globals.unit_visible_enemies.get(unit, [])
	for u in visible_enemies1: # unit.units:
		if u.team != unit.team and u.surrendered == false:
			known_enemies.append(u)
	
	var retreat_distance := 3
	var retreat_hex: Vector2i = unit.action_controller.compute_retreat_hex(unit.current_hex, known_enemies, retreat_distance)
	
	if retreat_hex != Vector2i.ZERO:
		#unit.movement.move_to_hex(retreat_hex)
		unit.order(Globals.UnitCmd.MOVE, retreat_hex)
		#var path: Array[Vector3i] = MovementSystem._compute_path(unit.current_hex, retreat_hex, unit.team)
		#unit.give_move_to_hex_order(retreat_hex, path, false)

	#var fallback_hex: Vector2i = _find_fallback_hex()
#
	#if fallback_hex != Vector2i.ZERO:
		#unit.movement.move_to_hex(fallback_hex)


func _handle_pinned() -> void:
	pass
