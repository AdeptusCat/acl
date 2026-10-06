class_name SquadTacticalState
extends RefCounted

var squad: Unit = null
var hex: Vector2i = Vector2i.ZERO

var members_alive: int = 0
var original_size: int = 0

var combat_effectiveness: float = 1.0
var stress_effective: float = 0.0
var cohesion: float = 1.0

var morale_state: STATES.MoraleState = STATES.MoraleState.NORMAL

#var has_mg: bool = false
#var has_leader: bool = false
#var has_radio: bool = false

var current_role: int = PlatoonTypes.Role.NONE
var assigned_task_id: int = -1


func configure(
	p_squad: Unit,
	p_hex: Vector2i,
	p_members_alive: int,
	p_original_size: int,
	p_combat_effectiveness: float,
	p_stress_effective: float,
	p_cohesion: float,
	p_morale_state: STATES.MoraleState,
	#p_has_mg: bool,
	#p_has_leader: bool,
	#p_has_radio: bool
) -> void:
	squad = p_squad
	hex = p_hex
	members_alive = p_members_alive
	original_size = p_original_size
	combat_effectiveness = clampf(p_combat_effectiveness, 0.0, 1.0)
	stress_effective = clampf(p_stress_effective, 0.0, 100.0)
	cohesion = clampf(p_cohesion, 0.0, 1.0)

	morale_state = p_morale_state

	#has_mg = p_has_mg
	#has_leader = p_has_leader
	#has_radio = p_has_radio


func is_pinned() -> bool:
	return morale_state == STATES.MoraleState.PINNED


func is_panicking() -> bool:
	return morale_state == STATES.MoraleState.PANIC


func is_combat_ineffective() -> bool:
	return morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE


func can_fire() -> bool:
	if morale_state == STATES.MoraleState.PANIC:
		return false

	if morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		return false

	return true


func can_move_normally() -> bool:
	if morale_state == STATES.MoraleState.PINNED:
		return false

	if morale_state == STATES.MoraleState.PANIC:
		return false

	if morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		return false

	return true
