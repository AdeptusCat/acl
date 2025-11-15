# goap_planner.gd
class_name GoapPlanner
extends Resource

const GoapGoal = preload("res://scenes/goap/goap_goal.gd")
const GoapAction = preload("res://scenes/goap/goap_action.gd")
const FormationWorldState = preload("res://scenes/goap/formation_world_state.gd")

class NodeState:
	var state: FormationWorldState
	var parent: NodeState = null
	var action: GoapAction = null
	var g_cost: float = 0.0

func _find_lowest_cost(open_list: Array[NodeState]) -> int:
	var best_index: int = 0
	var best_cost: float = open_list[0].g_cost
	var i: int = 1
	var size: int = open_list.size()
	while i < size:
		var n: NodeState = open_list[i]
		if n.g_cost < best_cost:
			best_cost = n.g_cost
			best_index = i
		i += 1
	return best_index

func _state_equals(a: FormationWorldState, b: FormationWorldState) -> bool:
	if a.line_established != b.line_established:
		return false
	if a.fallback_line_available != b.fallback_line_available:
		return false
	if a.reserve_present != b.reserve_present:
		return false
	if a.base_of_fire_established != b.base_of_fire_established:
		return false
	if a.assault_element_ready != b.assault_element_ready:
		return false
	if a.left_flank_exposed != b.left_flank_exposed:
		return false
	if a.right_flank_exposed != b.right_flank_exposed:
		return false
	if a.contact_uncertain != b.contact_uncertain:
		return false
	if a.friendly_E_level != b.friendly_E_level:
		return false
	if a.enemy_E_on_main_axis != b.enemy_E_on_main_axis:
		return false
	if a.casualty_level != b.casualty_level:
		return false
	if a.ammo_state_global != b.ammo_state_global:
		return false
	if a.time_pressure_high != b.time_pressure_high:
		return false
	if a.objective_held != b.objective_held:
		return false
	if a.objective_contested != b.objective_contested:
		return false
	if a.objective_clear != b.objective_clear:
		return false
	if a.route_to_objective_secure != b.route_to_objective_secure:
		return false
	if a.probe_result != b.probe_result:
		return false
	return true

func plan(start_state: FormationWorldState, goal: GoapGoal, actions: Array[GoapAction]) -> Array[GoapAction]:
	var open_list: Array[NodeState] = []
	var closed_list: Array[FormationWorldState] = []

	var start_node: NodeState = NodeState.new()
	start_node.state = start_state.clone()
	start_node.parent = null
	start_node.action = null
	start_node.g_cost = 0.0
	open_list.append(start_node)

	while open_list.size() > 0:
		var current_index: int = _find_lowest_cost(open_list)
		var current_node: NodeState = open_list[current_index]
		open_list.remove_at(current_index)
		closed_list.append(current_node.state)

		if goal.is_satisfied(current_node.state):
			return _reconstruct_plan(current_node)

		for action in actions:
			var act: GoapAction = action
			if not act.are_preconditions_met(current_node.state):
				continue

			var new_state: FormationWorldState = act.apply_effects(current_node.state)
			var skip: bool = false
			for seen_state in closed_list:
				if _state_equals(seen_state, new_state):
					skip = true
					break
			if skip:
				continue

			var child: NodeState = NodeState.new()
			child.state = new_state
			child.parent = current_node
			child.action = act
			child.g_cost = current_node.g_cost + act.get_cost(current_node.state)
			open_list.append(child)

	return []

func _reconstruct_plan(node: NodeState) -> Array[GoapAction]:
	var result: Array[GoapAction] = []
	var current: NodeState = node
	while current != null and current.action != null:
		result.push_front(current.action)
		current = current.parent
	return result
