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


static func for_mode(p_mode: Mode) -> PositionProfile:
	var profile: PositionProfile = PositionProfile.new()
	profile.mode = p_mode
	if p_mode == Mode.SUPPORT_BY_FIRE:
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
	if unit.squad_type == Globals.SquadType.MG:
		role_fire_weight *= 1.7
	elif unit.squad_type == Globals.SquadType.MORTAR:
		role_fire_weight *= 1.3
		role_risk_weight *= 1.5
	elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		role_fire_weight = 0.0
		role_risk_weight *= 2.0
	return (features["cover"] * cover_weight - features["incoming"] * role_risk_weight
		- features["forecast"] * forecast_weight + features["firing"] * role_fire_weight
		+ features["objective_coverage"] * objective_weight + features["support"] * support_weight
		- features["travel"] * travel_weight - features["route_exposure"] * exposure_weight
		+ features["progress"] * progress_weight)
