class_name PlatoonAiController
extends Node

#Platoon Layer
#System: FSM + HTN-style phase planner + Utility AI
#Purpose: run attack/defense phases and assign squad roles

enum PlatoonMission {
	NONE,
	ATTACK_OBJECTIVE,
	DEFEND_OBJECTIVE,
	WITHDRAW,
	RALLY
}

@export var decision_interval: float = 1.0

@export var squads: Array[Unit] = []
@export var mission: PlatoonMission = PlatoonMission.NONE
@export var objective_hex: Vector2i = Vector2i.ZERO
@export var fallback_hex: Vector2i = Vector2i.ZERO
var decision_timer: float = 0.0


func setup(p_units: Array[Unit]) -> void:
	squads = p_units


func _physics_process(delta: float) -> void:
	decision_timer += delta

	if decision_timer >= decision_interval:
		decision_timer = 0.0
		_decision_tick()


func _decision_tick() -> void:
	var average_e: float = _get_average_combat_effectiveness()

	if average_e < 0.30:
		_assign_withdraw_orders()
		return

	if average_e < 0.45:
		_assign_rally_or_defend_orders()
		return

	if mission == PlatoonMission.ATTACK_OBJECTIVE:
		_assign_attack_orders()
	elif mission == PlatoonMission.DEFEND_OBJECTIVE:
		_assign_defend_orders()
	elif mission == PlatoonMission.WITHDRAW:
		_assign_withdraw_orders()
	elif mission == PlatoonMission.RALLY:
		_assign_rally_or_defend_orders()


func _get_average_combat_effectiveness() -> float:
	var weighted_sum: float = 0.0
	var total_weight: float = 0.0

	for squad: Unit in squads:
		var weight: float = float(squad.original_size)

		#if squad.split_size > 0:
			#weight = float(squad.split_size)

		if weight < 1.0:
			weight = 1.0

		weighted_sum += squad.combat_stats.combat_effectiveness * weight
		total_weight += weight

	if total_weight <= 0.0:
		return 0.0

	var value: float = weighted_sum / total_weight
	return clampf(value, 0.0, 1.0)


func _assign_attack_orders() -> void:
	var sorted_squads: Array[Unit] = squads.duplicate()
	sorted_squads.sort_custom(_sort_by_e_descending)

	var index: int = 0

	for squad: Unit in sorted_squads:
		var order: AiOrder = AiOrder.new()

		if index == 0:
			order.order_type = AiOrder.OrderType.ASSAULT
			order.target_hex = objective_hex
			order.allow_assault = true
		elif index == 1:
			order.order_type = AiOrder.OrderType.SUPPRESS
			order.target_hex = objective_hex
			order.allow_movement = false
		else:
			order.order_type = AiOrder.OrderType.HOLD
			order.target_hex = squad.hex

		_set_squad_order(squad, order)
		index += 1


func _sort_by_e_descending(a: Unit, b: Unit) -> bool:
	var a_e: float = a.combat_stats.combat_effectiveness
	var b_e: float = b.combat_stats.combat_effectiveness

	return a_e > b_e


func _assign_defend_orders() -> void:
	for squad: Unit in squads:
		var order: AiOrder = AiOrder.new()
		order.order_type = AiOrder.OrderType.HOLD
		order.target_hex = squad.hex
		order.allow_fire = true
		order.allow_movement = false

		_set_squad_order(squad, order)


func _assign_rally_or_defend_orders() -> void:
	for squad: Unit in squads:
		var order: AiOrder = AiOrder.new()

		if squad.combat_stats.combat_effectiveness < 0.35:
			order.order_type = AiOrder.OrderType.RALLY
			order.target_hex = fallback_hex
			order.allow_fire = true
			order.allow_movement = true
		else:
			order.order_type = AiOrder.OrderType.HOLD
			order.target_hex = squad.current_hex
			order.allow_fire = true
			order.allow_movement = false

		_set_squad_order(squad, order)


func _assign_withdraw_orders() -> void:
	for squad: Unit in squads:
		var order: AiOrder = AiOrder.new()
		order.order_type = AiOrder.OrderType.WITHDRAW
		order.target_hex = fallback_hex
		order.allow_fire = false
		order.allow_movement = true

		_set_squad_order(squad, order)


func _set_squad_order(squad: Unit, order: AiOrder) -> void:
	if squad.squad_ai_controller == null:
		return

	squad.squad_ai_controller.set_order(order)
