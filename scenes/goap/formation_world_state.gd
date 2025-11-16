# formation_world_state.gd
class_name FormationWorldState
extends Resource

const GoapTypes = preload("res://scenes/goap/goap_types.gd")

var mission_mode: int = GoapTypes.FormationMissionMode.DEFEND

var line_established: bool = false
var fallback_line_available: bool = false
var reserve_present: bool = false
var base_of_fire_established: bool = false
var assault_element_ready: bool = false
var left_flank_exposed: bool = false
var right_flank_exposed: bool = false
var contact_uncertain: bool = true

var friendly_E_level: int = GoapTypes.WorldELevel.MED
var enemy_E_on_main_axis: int = GoapTypes.WorldELevel.MED
var casualty_level: int = GoapTypes.WorldELevel.LOW
var ammo_state_global: int = GoapTypes.WorldAmmoLevel.OK
var time_pressure_high: bool = false

var objective_held: bool = false
var objective_contested: bool = false
var objective_clear: bool = false
var route_to_objective_secure: bool = false
var probe_result: int = GoapTypes.WorldProbeResult.UNKNOWN

var has_enemy_contacts: bool = false

func clone() -> FormationWorldState:
	var s: FormationWorldState = FormationWorldState.new()
	s.mission_mode = mission_mode
	s.line_established = line_established
	s.fallback_line_available = fallback_line_available
	s.reserve_present = reserve_present
	s.base_of_fire_established = base_of_fire_established
	s.assault_element_ready = assault_element_ready
	s.left_flank_exposed = left_flank_exposed
	s.right_flank_exposed = right_flank_exposed
	s.contact_uncertain = contact_uncertain
	s.friendly_E_level = friendly_E_level
	s.enemy_E_on_main_axis = enemy_E_on_main_axis
	s.casualty_level = casualty_level
	s.ammo_state_global = ammo_state_global
	s.time_pressure_high = time_pressure_high
	s.objective_held = objective_held
	s.objective_contested = objective_contested
	s.objective_clear = objective_clear
	s.route_to_objective_secure = route_to_objective_secure
	s.probe_result = probe_result
	s.has_enemy_contacts = has_enemy_contacts
	return s
