class_name MissionOrder
extends RefCounted

enum MissionType {
	HOLD,
	DELAY,
	SCREEN,
	RESERVE,
	BLOCK,
	SUPPORT_BY_FIRE,
}

enum ReservePolicy {
	NONE,
	KEEP_ONE_SQUAD_IF_POSSIBLE,
	KEEP_HQ_NEAR_OBJECTIVE,
}

var mission_type: MissionType = MissionType.HOLD
var objective_hex: Vector2i = Vector2i.ZERO
var sector_cells: Array[Vector2i] = []
var fallback_hexes: Array[Vector2i] = []
var threat_axes: Array[ThreatAxis] = []
var reserve_policy: ReservePolicy = ReservePolicy.KEEP_ONE_SQUAD_IF_POSSIBLE

# Position advice is independent of execution intent.
var execution_intent: TacticalPositionExecutor.Intent = TacticalPositionExecutor.Intent.FROM_PROFILE
var position_mode: PositionProfile.Mode = PositionProfile.Mode.DEFEND
var geography: PositionQuery.Geography = PositionQuery.Geography.OBJECTIVE_OR_SECTOR
var defense_radius: int = 4
# Automatic objective-or-sector missions may use covered firing positions farther out.
var defense_area_radius: int = 8
var approach_analysis_radius: int = 12
var movement_radius: int = 6
var defense_responsibility: PositionQuery.Responsibility = PositionQuery.Responsibility.AUTO
var exposure_budget_seconds: float = 6.0
var open_crossing_budget_seconds: float = 2.0


func copy() -> MissionOrder:
	var result: MissionOrder = MissionOrder.new()
	result.mission_type = mission_type
	result.objective_hex = objective_hex
	result.sector_cells = sector_cells.duplicate()
	result.fallback_hexes = fallback_hexes.duplicate()
	result.threat_axes = threat_axes.duplicate()
	result.reserve_policy = reserve_policy
	result.execution_intent = execution_intent
	result.position_mode = position_mode
	result.geography = geography
	result.defense_radius = defense_radius
	result.defense_area_radius = defense_area_radius
	result.approach_analysis_radius = approach_analysis_radius
	result.movement_radius = movement_radius
	result.defense_responsibility = defense_responsibility
	result.exposure_budget_seconds = exposure_budget_seconds
	result.open_crossing_budget_seconds = open_crossing_budget_seconds
	return result
