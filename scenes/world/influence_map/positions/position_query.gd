class_name PositionQuery
extends RefCounted

enum Geography { OBJECTIVE_RADIUS, SECTOR_ONLY, OBJECTIVE_OR_SECTOR }
enum Responsibility { AUTO, OCCUPY, GUARD, COVER_APPROACH }

var unit: Unit = null
var team: int = -1
var objective_hex: Vector2i = Vector2i.ZERO
var profile: PositionProfile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
var snapshot: InfluenceSnapshot = null
var forecast_data: PackedFloat32Array = PackedFloat32Array()
var route_field: PositionRouteField = null
var defense_approaches: Array[Dictionary] = []
var defense_responsibility: Responsibility = Responsibility.AUTO
var withdrawal_requested: bool = false
var geography: Geography = Geography.OBJECTIVE_OR_SECTOR
var defense_radius: int = 4
var movement_radius: int = 6
var sector_cells: Array[Vector2i] = []
var fallback_hexes: Array[Vector2i] = []
var reservations: Dictionary = {}
var has_accepted_target: bool = false
var accepted_target: Vector2i = Vector2i.ZERO
var accepted_context: String = ""
var accepted_at: float = -INF
var axis: ThreatAxis = null
var include_score_map: bool = true
var max_alternatives: int = 5
var destination_features: Dictionary[Vector2i, Dictionary] = {}
var firing_targets: Array[Vector2i] = []
var firing_targets_prepared: bool = false
var firepower_by_unit: Dictionary[Unit, Dictionary] = {}
var origin_hex: Vector2i = Vector2i.ZERO
var defense_area: DefenseAreaAssessment
var use_defense_area: bool = true
var area_job: DefenseAreaJob
var assigned_sector: int = -1
var assigned_branch: String = ""
var reserve_position: bool = false
var reserve_responses: Dictionary[String, Dictionary] = {}
var reserve_reason: String = ""
var reserve_response_context: String = ""
var required_crossing_branch: String = ""
var reserve_response_limits: Dictionary[String, float] = {}
var relocation_allowed: bool = true
var sector_features: Dictionary[Unit, Dictionary] = {}
var support_fire_by_branch: Dictionary[String, Dictionary] = {}
var established_screen: Dictionary[String, Dictionary] = {}
var support_targets: Dictionary[Unit, Dictionary] = {}
var support_radius: int = 2


func reset_evaluation() -> void:
	route_field = null
	origin_hex = unit.current_hex
	destination_features.clear()
	firing_targets.clear()
	firing_targets_prepared = false
	firepower_by_unit.clear()
	sector_features.clear()
	support_fire_by_branch.clear()
	established_screen.clear()


func defense_crossing_seconds() -> float:
	return InfluenceUnitQuery.captured_crossing_seconds(unit)


func firepower_at_range(friendly: Unit, distance: int) -> float:
	if not firepower_by_unit.has(friendly):
		firepower_by_unit[friendly] = {}
	if not firepower_by_unit[friendly].has(distance):
		firepower_by_unit[friendly][distance] = InfluenceUnitQuery.get_firepower_at_range(friendly, distance)
	return firepower_by_unit[friendly][distance]


func context_key() -> String:
	if profile.mode == PositionProfile.Mode.HQ_SUPPORT:
		# Stress changes affect utility, without resetting a stable support position every snapshot.
		return str([team, profile.mode, support_targets.keys(), support_radius, movement_radius])
	var axis_key: String = ""
	# Axis observations can change without changing the defensive mission.
	if axis != null and profile.mode != PositionProfile.Mode.DEFEND:
		axis_key = axis.axis_name
	var withdrawing: bool = false
	if profile.mode == PositionProfile.Mode.DEFEND and is_instance_valid(unit):
		withdrawing = withdrawal_requested or InfluenceUnitQuery.get_unit_effectiveness(unit) < profile.withdrawal_effectiveness
	var response_capability: String = ""
	if reserve_position and not reserve_responses.is_empty():
		response_capability = DefenseReadinessJob.capability_key(unit)
	return str([team, objective_hex, profile.mode, axis_key, geography, defense_radius, movement_radius, sector_cells, fallback_hexes, defense_responsibility, withdrawing, assigned_sector, assigned_branch, reserve_position, use_defense_area, profile.defensive_mount, response_capability, required_crossing_branch])
