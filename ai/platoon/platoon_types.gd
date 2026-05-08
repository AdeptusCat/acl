class_name PlatoonTypes
extends Resource

enum MissionType {
	NONE,
	ATTACK_OBJECTIVE,
	DEFEND_AREA,
	WITHDRAW
}

enum Phase {
	IDLE,
	PLANNING_ATTACK,
	APPROACH_TO_OBJECTIVE,
	RECON_OBJECTIVE,
	DEVELOP_CONTACT,
	SUPPRESS_OBJECTIVE,
	MANEUVER_TO_ASSAULT_POSITION,
	ASSAULT_OBJECTIVE,
	CONSOLIDATE_OBJECTIVE,
	REORGANIZE,
	WITHDRAW
}

enum Role {
	NONE,
	LEAD_PROBE,
	OVERWATCH,
	SUPPORT_BY_FIRE,
	ASSAULT,
	RESERVE,
	RALLY,
	SECURITY,
	WITHDRAWING
}

enum TaskType {
	NONE,
	MOVE_TO_HEX,
	OBSERVE_HEX,
	OVERWATCH_ZONE,
	SUPPORT_BY_FIRE,
	SUPPRESS_TRACK,
	MANEUVER_TO_HEX,
	ASSAULT_HEX,
	SECURE_HEX,
	RALLY_AT_HEX,
	WITHDRAW_TO_HEX
}

enum TrackSource {
	UNKNOWN,
	LOS,
	REPORT,
	INCOMING_FIRE,
	SOUND,
	LAST_KNOWN
}

enum ZoneReason {
	OBJECTIVE,
	COVER_NEAR_OBJECTIVE,
	OVERWATCH_TERRAIN,
	STALE_CONTACT,
	INCOMING_FIRE_DIRECTION,
	ROUTE_THREAT
}


static func role_to_string(role: int) -> String:
	match role:
		Role.NONE:
			return "NONE"
		Role.LEAD_PROBE:
			return "LEAD_PROBE"
		Role.OVERWATCH:
			return "OVERWATCH"
		Role.SUPPORT_BY_FIRE:
			return "SUPPORT_BY_FIRE"
		Role.ASSAULT:
			return "ASSAULT"
		Role.RESERVE:
			return "RESERVE"
		Role.RALLY:
			return "RALLY"
		Role.SECURITY:
			return "SECURITY"
		Role.WITHDRAWING:
			return "WITHDRAWING"
		_:
			return "UNKNOWN_ROLE"


static func task_type_to_string(task_type: int) -> String:
	match task_type:
		TaskType.NONE:
			return "NONE"
		TaskType.MOVE_TO_HEX:
			return "MOVE_TO_HEX"
		TaskType.OBSERVE_HEX:
			return "OBSERVE_HEX"
		TaskType.OVERWATCH_ZONE:
			return "OVERWATCH_ZONE"
		TaskType.SUPPORT_BY_FIRE:
			return "SUPPORT_BY_FIRE"
		TaskType.SUPPRESS_TRACK:
			return "SUPPRESS_TRACK"
		TaskType.MANEUVER_TO_HEX:
			return "MANEUVER_TO_HEX"
		TaskType.ASSAULT_HEX:
			return "ASSAULT_HEX"
		TaskType.SECURE_HEX:
			return "SECURE_HEX"
		TaskType.RALLY_AT_HEX:
			return "RALLY_AT_HEX"
		TaskType.WITHDRAW_TO_HEX:
			return "WITHDRAW_TO_HEX"
		_:
			return "UNKNOWN_TASK_TYPE"

static func mission_type_to_string(mission_type: int) -> String:
	match mission_type:
		MissionType.NONE:
			return "NONE"
		MissionType.ATTACK_OBJECTIVE:
			return "ATTACK_OBJECTIVE"
		MissionType.DEFEND_AREA:
			return "DEFEND_AREA"
		MissionType.WITHDRAW:
			return "WITHDRAW"
		_:
			return "UNKNOWN_MISSION_TYPE"


static func phase_to_string(phase: int) -> String:
	match phase:
		Phase.IDLE:
			return "IDLE"
		Phase.PLANNING_ATTACK:
			return "PLANNING_ATTACK"
		Phase.APPROACH_TO_OBJECTIVE:
			return "APPROACH_TO_OBJECTIVE"
		Phase.RECON_OBJECTIVE:
			return "RECON_OBJECTIVE"
		Phase.DEVELOP_CONTACT:
			return "DEVELOP_CONTACT"
		Phase.SUPPRESS_OBJECTIVE:
			return "SUPPRESS_OBJECTIVE"
		Phase.MANEUVER_TO_ASSAULT_POSITION:
			return "MANEUVER_TO_ASSAULT_POSITION"
		Phase.ASSAULT_OBJECTIVE:
			return "ASSAULT_OBJECTIVE"
		Phase.CONSOLIDATE_OBJECTIVE:
			return "CONSOLIDATE_OBJECTIVE"
		Phase.REORGANIZE:
			return "REORGANIZE"
		Phase.WITHDRAW:
			return "WITHDRAW"
		_:
			return "UNKNOWN_PHASE"
