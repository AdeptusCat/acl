class_name DefenseDirector
extends Node

enum ObjectiveSource { AUTHORED, PLATOON_ANCHOR, SCENARIO_TARGET }

@export var objective_source: ObjectiveSource = ObjectiveSource.AUTHORED
@export var execution_intent: TacticalPositionExecutor.Intent = TacticalPositionExecutor.Intent.FROM_PROFILE
@export var position_mode: PositionProfile.Mode = PositionProfile.Mode.DEFEND
@export var geography: PositionQuery.Geography = PositionQuery.Geography.OBJECTIVE_OR_SECTOR
@export var defense_radius: int = 4
@export var movement_radius: int = 6

@export var objective_hex: Vector2i #= Vector2i(11,13)# Vector2i.ZERO
@export var sector_cells: Array[Vector2i] = [Vector2i(9,17), Vector2i(10,17), Vector2i(11,17), Vector2i(8,17)]
@export var fallback_hexes: Array[Vector2i] = [Vector2i(9,15)]

# Manually assigned in inspector for first version.
@export var manual_threat_axes: Array[ThreatAxis] = []

@export var platoon_ai: PlatoonAI = null



#func _ready() -> void:
	#assign_order_to_platoon()


func create_initial_order() -> MissionOrder:
	var order: MissionOrder = MissionOrder.new()

	order.mission_type = MissionOrder.MissionType.HOLD
	order.objective_hex = objective_hex
	order.position_mode = position_mode
	order.execution_intent = execution_intent
	order.geography = geography
	order.defense_radius = defense_radius
	order.movement_radius = movement_radius
	order.sector_cells = sector_cells
	order.fallback_hexes = fallback_hexes
	order.reserve_policy = MissionOrder.ReservePolicy.KEEP_ONE_SQUAD_IF_POSSIBLE
	order.threat_axes = _get_known_enemy_threat_axes()

	return order


func configure_for_match(active_units: Array[Unit]) -> void:
	if platoon_ai == null:
		return
	platoon_ai.bind_active_squads(active_units)
	if objective_source == ObjectiveSource.PLATOON_ANCHOR and not platoon_ai.squads.is_empty():
		objective_hex = platoon_ai.squads[0].current_hex
	elif objective_source == ObjectiveSource.SCENARIO_TARGET:
		var objectives: ObjectivesCollection = Globals.objectives.get(platoon_ai.team)
		if objectives != null and not objectives.objectives.is_empty():
			objective_hex = objectives.objectives[0].hex


func assign_order_to_platoon() -> void:
	if platoon_ai == null:
		return

	var order: MissionOrder = create_initial_order()
	platoon_ai.receive_mission_order(order)


func _get_known_enemy_threat_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = []

	for axis: ThreatAxis in manual_threat_axes:
		if axis == null:
			continue

		axis.recompute_score()

		if axis.is_valid_axis():
			axes.append(axis)

	return axes
