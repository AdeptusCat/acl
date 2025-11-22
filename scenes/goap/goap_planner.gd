# goap_planner.gd
class_name GoapPlanner
extends Resource

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
	if a.mission_mode != b.mission_mode:
		return false

	if a.base_of_fire_ready != b.base_of_fire_ready:
		return false
	if a.assault_element_ready != b.assault_element_ready:
		return false
	if a.fire_superiority != b.fire_superiority:
		return false
	if a.assault_plan_ready != b.assault_plan_ready:
		return false
	if a.enemy_holds_objective != b.enemy_holds_objective:
		return false
	if a.has_enemy_contacts != b.has_enemy_contacts:
		return false
	if a.objective_held != b.objective_held:
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
