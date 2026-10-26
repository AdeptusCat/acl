extends Resource
class_name ReinforcementState

## Runtime data only; never written into the authored definition.
@export var reinforcement_id: String = ""
@export var rolled_arrival_seconds: float = 0.0
@export var player_estimate_seconds: float = 0.0
@export var arrival_by_unit: Dictionary[String, float] = {}
@export var arrived_unit_ids: PackedStringArray = []


static func roll(definition: ReinforcementDefinition, rng: RandomNumberGenerator) -> ReinforcementState:
	var state: ReinforcementState = ReinforcementState.new()
	state.reinforcement_id = definition.reinforcement_id
	state.rolled_arrival_seconds = definition.roll_arrival(rng)
	state.player_estimate_seconds = definition.player_estimate()
	var arrival: float = state.rolled_arrival_seconds
	for id: String in definition.unit_ids:
		if state.arrival_by_unit.has(id):
			continue
		state.arrival_by_unit[id] = arrival
		if definition.staggered:
			var minimum: float = maxf(0.0, definition.stagger_min_seconds)
			arrival += rng.randf_range(minimum, maxf(minimum, definition.stagger_max_seconds))
	return state
