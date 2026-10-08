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
