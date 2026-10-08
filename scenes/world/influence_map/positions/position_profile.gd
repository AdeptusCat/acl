class_name PositionProfile
extends Resource

enum Mode { LEGACY_DEFENSE, DEFEND, SUPPORT_BY_FIRE, ADVANCE, ASSAULT }

@export var mode: Mode = Mode.DEFEND
@export var max_incoming_risk: float = 0.8
@export var max_route_exposure: float = 0.8
@export var cover_weight: float = 2.0
@export var incoming_weight: float = 3.0
@export var forecast_weight: float = 1.0
@export var firing_weight: float = 1.2
@export var objective_weight: float = 2.0
@export var support_weight: float = 0.3
@export var travel_weight: float = 0.08
@export var exposure_weight: float = 2.0
@export var progress_weight: float = 0.0
@export var improvement_absolute: float = 0.15
@export var improvement_relative: float = 0.1
@export var minimum_cover: float = 0.0
@export var open_ground_weight: float = 0.0
@export var commitment_seconds: float = 0.0
@export var max_exposure_seconds: float = INF
@export var max_open_exposure_seconds: float = INF
@export var forecast_route_weight: float = 1.0
@export var interposition_weight: float = 0.0
@export var blocking_weight: float = 0.0
@export var proximity_weight: float = 0.0
@export var hold_effectiveness: float = 0.45
@export var withdrawal_effectiveness: float = 0.35
@export var interdiction_weight: float = 6.0
@export var area_interposition_weight: float = 1.5
@export var area_objective_weight: float = 1.5
@export var area_blocking_weight: float = 2.0
@export var reserve_readiness_weight: float = 4.0
@export var establishment_seconds: float = 3.0


static func for_mode(p_mode: Mode) -> PositionProfile:
	var profile: PositionProfile = PositionProfile.new()
	profile.mode = p_mode
	if p_mode == Mode.DEFEND:
		profile.minimum_cover = 0.1
		profile.max_incoming_risk = 0.9
		profile.max_route_exposure = 0.98
		profile.max_exposure_seconds = 6.0
		profile.max_open_exposure_seconds = 2.0
		profile.forecast_route_weight = 0.25
		profile.cover_weight = 2.0
		profile.objective_weight = 4.0
		profile.interposition_weight = 5.0
		profile.blocking_weight = 4.0
		profile.proximity_weight = 0.4
		profile.travel_weight = 0.12
		profile.exposure_weight = 0.5
		profile.open_ground_weight = 1.0
		profile.improvement_absolute = 0.35
		profile.improvement_relative = 0.2
		profile.commitment_seconds = 8.0
	elif p_mode == Mode.SUPPORT_BY_FIRE:
		profile.firing_weight = 3.0
		profile.objective_weight = 0.0
	elif p_mode == Mode.ADVANCE:
		profile.progress_weight = 4.0
		profile.objective_weight = 0.0
		profile.firing_weight = 0.5
	elif p_mode == Mode.ASSAULT:
		profile.progress_weight = 6.0
		profile.objective_weight = 0.0
		profile.max_incoming_risk = 0.9
		profile.max_route_exposure = 0.9
		profile.cover_weight = 0.8
		profile.travel_weight = 0.03
	return profile


func score(features: Dictionary, unit: Unit) -> float:
	if mode == Mode.LEGACY_DEFENSE:
		return features.get("legacy", 0.0)
	var role_fire_weight: float = firing_weight
	var role_risk_weight: float = incoming_weight
	var position_weight: float = interposition_weight
	var area_bonus: float = 0.0
	var capture_weight: float = objective_weight
	var coverage_weight: float = blocking_weight
	if mode == Mode.DEFEND and features.has("interdiction"):
		position_weight = area_interposition_weight
		capture_weight = area_objective_weight
		coverage_weight = area_blocking_weight
		area_bonus = features["interdiction"] * interdiction_weight
		if unit.squad_type == Globals.SquadType.MG:
			area_bonus *= 1.7
		elif unit.squad_type == Globals.SquadType.MORTAR:
			area_bonus *= 1.3
		elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			area_bonus = 0.0
		if features.get("responsibility") == "reserve":
			area_bonus = features["reserve_readiness"] * reserve_readiness_weight
			position_weight = 0.0
			coverage_weight = 0.0
			capture_weight = 0.5
		var deadline: float = features.get("arrival_seconds", INF)
		var response: float = features.get("route_seconds", 0.0) + establishment_seconds
		if is_finite(deadline) and response > deadline:
			area_bonus -= minf(3.0, (response - deadline) / 4.0)
	if unit.squad_type == Globals.SquadType.MG:
		role_fire_weight *= 1.7
	elif unit.squad_type == Globals.SquadType.MORTAR:
		role_fire_weight *= 1.3
		role_risk_weight *= 1.5
	elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		role_fire_weight = 0.0
		role_risk_weight *= 2.0
	if features.get("withdrawal", false):
		role_risk_weight *= 2.0
		position_weight *= 0.2
	var route_cost: float = features["route_exposure"]
	if mode == Mode.DEFEND:
		route_cost = features.get("exposure_seconds", route_cost)
	return (features["cover"] * cover_weight - features["incoming"] * role_risk_weight
		- features["forecast"] * forecast_weight + features["firing"] * role_fire_weight
		+ features["objective_coverage"] * capture_weight + features["support"] * support_weight
		- features["travel"] * travel_weight - route_cost * exposure_weight
		- features.get("open_ground", 0.0) * open_ground_weight
		+ features.get("interposition", 0.0) * position_weight + features.get("blocking", 0.0) * coverage_weight + area_bonus
		- features.get("contact_pressure", 0.0) * proximity_weight
		+ features["progress"] * progress_weight)
