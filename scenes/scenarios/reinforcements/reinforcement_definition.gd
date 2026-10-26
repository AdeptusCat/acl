@tool
extends Node
class_name ReinforcementDefinition

enum Distribution { NEAR_EXPECTED, UNIFORM }

@export_storage var reinforcement_id: String = ""
@export var display_name: String = "Reinforcements"
@export var team: Globals.Team = Globals.Team.AXIS
## References normal units under the mission's Units node, never scene paths.
@export var unit_ids: PackedStringArray = []
@export_group("Arrival")
@export_range(0.0, 86400.0, 1.0, "suffix:s") var expected_seconds: float = 900.0
@export_range(0.0, 86400.0, 1.0, "suffix:s") var variation_seconds: float = 240.0
@export var distribution: Distribution = Distribution.NEAR_EXPECTED
@export_group("Entry")
## Descriptive entry zone. Units always arrive at their individual authored map positions.
@export var entry_zone: String = ""
## Optional map marker identifying the entry location for authoring and player briefing.
@export_node_path("Node2D") var entry_location: NodePath
@export var staggered: bool = false
@export_range(0.0, 3600.0, 1.0, "suffix:s") var stagger_min_seconds: float = 2.0
@export_range(0.0, 3600.0, 1.0, "suffix:s") var stagger_max_seconds: float = 8.0
@export_group("Player Information")
@export var show_to_player: bool = true
@export_range(30.0, 600.0, 30.0, "suffix:s") var estimate_rounding_seconds: float = 60.0


func roll_arrival(rng: RandomNumberGenerator) -> float:
	var offset: float = rng.randf_range(-1.0, 1.0)
	if distribution == Distribution.NEAR_EXPECTED:
		offset = (offset + rng.randf_range(-1.0, 1.0)) * 0.5
	return maxf(0.0, expected_seconds + offset * maxf(0.0, variation_seconds))


func player_estimate() -> float:
	var rounding: float = maxf(30.0, estimate_rounding_seconds)
	return snappedf(maxf(0.0, expected_seconds), rounding)
