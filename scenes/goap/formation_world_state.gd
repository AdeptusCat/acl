# formation_world_state.gd
class_name FormationWorldState
extends Resource

var mission_mode: int = GoapTypes.FormationMissionMode.DEFEND

#var line_established: bool = false
#var fallback_line_available: bool = false
#var reserve_present: bool = false
#var base_of_fire_established: bool = false
#var assault_element_ready: bool = false
#var left_flank_exposed: bool = false
#var right_flank_exposed: bool = false
#var contact_uncertain: bool = true
#
#var friendly_E_level: int = GoapTypes.WorldELevel.MED
#var enemy_E_on_main_axis: int = GoapTypes.WorldELevel.MED
#var casualty_level: int = GoapTypes.WorldELevel.LOW
#var ammo_state_global: int = GoapTypes.WorldAmmoLevel.OK
#var time_pressure_high: bool = false
#
#var objective_held: bool = false
#var objective_contested: bool = false
#var objective_clear: bool = false
#var route_to_objective_secure: bool = false
#var probe_result: int = GoapTypes.WorldProbeResult.UNKNOWN

var objective_held: bool = false
var enemy_holds_objective: bool = false
var base_of_fire_ready: bool = false
var assault_element_ready: bool = false
var fire_superiority: bool = true
var assault_plan_ready: bool = false
var has_enemy_contacts: bool = false


func clone() -> FormationWorldState:
	var s: FormationWorldState = FormationWorldState.new()
	s.mission_mode = mission_mode
	s.objective_held = objective_held
	s.enemy_holds_objective = enemy_holds_objective
	s.assault_plan_ready = assault_plan_ready
	s.has_enemy_contacts = has_enemy_contacts
	s.base_of_fire_ready = base_of_fire_ready
	s.assault_element_ready = assault_element_ready
	s.fire_superiority = fire_superiority
	return s
