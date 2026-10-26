extends Node
class_name MatchReinforcementController

signal unit_arrived(unit: Unit)

var elapsed_seconds: float = 0.0
var states: Array[ReinforcementState] = []
var definitions: Array[ReinforcementDefinition] = []
var pending: Dictionary[String, Unit] = {}
var _controller: Node2D
var _holding: Node2D


func prepare(controller: Node2D, scenario: Scenario) -> void:
	add_to_group("reinforcement_runtime")
	_controller = controller
	definitions = scenario.get_reinforcements()
	_holding = Node2D.new()
	_holding.name = "PendingUnits"
	_holding.process_mode = Node.PROCESS_MODE_DISABLED
	_holding.hide()
	add_child(_holding)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var claimed: Dictionary[String, bool] = {}
	var roster: Dictionary[String, Unit] = {}
	for node: Node in scenario.get_units():
		var unit: Unit = node as Unit
		if unit == null or unit.map_unit_id.is_empty():
			continue
		if roster.has(unit.map_unit_id):
			push_error("Duplicate map unit ID: %s" % unit.map_unit_id)
			continue
		roster[unit.map_unit_id] = unit
	for definition: ReinforcementDefinition in definitions:
		var state: ReinforcementState = ReinforcementState.roll(definition, rng)
		states.append(state)
		for id: String in state.arrival_by_unit.keys():
			if claimed.has(id) or not roster.has(id) or roster[id].team != definition.team:
				state.arrival_by_unit.erase(id)
				push_warning("Invalid or already assigned reinforcement unit: %s" % id)
				continue
			claimed[id] = true
			var unit: Unit = roster[id]
			pending[id] = unit
			unit.add_to_group("pending_reinforcements")
			unit.reparent(_holding)


func advance(delta: float) -> void:
	elapsed_seconds += maxf(0.0, delta)
	for state: ReinforcementState in states:
		for id: String in state.arrival_by_unit:
			if not pending.has(id) or state.arrived_unit_ids.has(id):
				continue
			if elapsed_seconds < state.arrival_by_unit[id]:
				continue
			var unit: Unit = pending[id]
			pending.erase(id)
			state.arrived_unit_ids.append(id)
			unit.remove_from_group("pending_reinforcements")
			MatchUnitSpawner.activate_authored_unit(_controller, unit)
			unit_arrived.emit(unit)


func save_to(data: MatchSaveData) -> void:
	data.reinforcement_elapsed_seconds = elapsed_seconds
	data.reinforcement_states.clear()
	for state: ReinforcementState in states:
		data.reinforcement_states.append(state.duplicate(true) as ReinforcementState)


## Restore after prepare, alongside the active-unit save restoration. Never reroll arrivals.
func restore_from(data: MatchSaveData) -> void:
	elapsed_seconds = data.reinforcement_elapsed_seconds
	states.clear()
	for state: ReinforcementState in data.reinforcement_states:
		states.append(state.duplicate(true) as ReinforcementState)
		for id: String in state.arrived_unit_ids:
			if pending.has(id):
				pending[id].queue_free()
				pending.erase(id)


func player_briefing(team: Globals.Team) -> String:
	var lines: PackedStringArray = []
	for definition: ReinforcementDefinition in definitions:
		if definition.team != team or not definition.show_to_player:
			continue
		var state: ReinforcementState = null
		for candidate: ReinforcementState in states:
			if candidate.reinforcement_id == definition.reinforcement_id:
				state = candidate
				break
		if state == null or state.arrival_by_unit.is_empty():
			continue
		var remaining: int = 0
		for id: String in state.arrival_by_unit:
			if pending.has(id):
				remaining += 1
		var status: String = "Arrived"
		if remaining > 0:
			var estimate: float = maxf(0.0, state.player_estimate_seconds - elapsed_seconds)
			status = "Expected soon"
			if estimate >= 60.0:
				status = "Expected in about %d min" % maxi(1, roundi(estimate / 60.0))
			if not state.arrived_unit_ids.is_empty():
				status = "Arriving · %d squads remaining" % remaining
		var location: String = definition.entry_zone
		if location.is_empty() and not definition.entry_location.is_empty():
			var marker: Node = definition.get_node_or_null(definition.entry_location)
			if marker != null:
				location = str(marker.name)
		var line: String = "%s: %s" % [definition.display_name, status]
		if not location.is_empty():
			line += " · " + location
		lines.append(line)
	return "\n".join(lines)
