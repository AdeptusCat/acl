extends Node
class_name SquadActionController

enum SquadActionState {
	NO_ORDER,
	MOVING_TO_POSITION,
	ESTABLISHING_POSITION,
	HOLDING_POSITION,
	ADVANCING,
	CROSSING_EXPOSED,
	LOCAL_FALLBACK,
	ROUTING,
	REGROUPING,
}

enum MoraleState {
	NORMAL,
	CAUTIOUS,
	PINNED,
	PANIC,
	COMBAT_INEFFECTIVE,
}

var objective_hex: Vector2i

var unit: Unit
var movement: UnitMovement
var squad_fire: SquadFireController
var stress: StressController
var ui: UnitUi
var combat: UnitCombat

var action_state: int = SquadActionState.NO_ORDER
var action_order_id: int = 0

var withdraw_hex: Vector2i = Vector2i.ZERO
var attack_hex: Vector2i = Vector2i.ZERO

var has_take_and_hold_flag: bool = false
var has_attack_flag: bool = false
var has_withdraw_flag: bool = false

var establishing_timer: Timer
var regroup_timer: Timer


signal action_state_changed(prev: int, next: int)


func init(p_unit: Unit, p_movement: UnitMovement, p_squad_fire: SquadFireController, p_stress: StressController, p_ui: UnitUi, p_combat: UnitCombat) -> void:
	unit = p_unit
	movement = p_movement
	squad_fire = p_squad_fire
	stress = p_stress
	ui = p_ui
	combat = p_combat
	
	establishing_timer = Timer.new()
	establishing_timer.one_shot = true
	establishing_timer.wait_time = 3.0
	add_child(establishing_timer)
	establishing_timer.timeout.connect(_on_establishing_timer_timeout)
	
	regroup_timer = Timer.new()
	regroup_timer.one_shot = true
	regroup_timer.wait_time = 5.0
	add_child(regroup_timer)
	regroup_timer.timeout.connect(_on_regroup_timer_timeout)


func _set_action_state(next: int) -> void:
	var prev: int = action_state
	if prev == next:
		return
	
	_exit_action_state(prev)
	action_state = next
	_enter_action_state(prev, next)
	action_state_changed.emit(prev, next)


func _exit_action_state(state: int) -> void:
	match state:
		SquadActionState.ESTABLISHING_POSITION:
			if establishing_timer.is_stopped() == false:
				establishing_timer.stop()
		SquadActionState.REGROUPING:
			if regroup_timer.is_stopped() == false:
				regroup_timer.stop()
		_:
			pass


func _enter_action_state(prev: int, state: int) -> void:
	match state:
		SquadActionState.NO_ORDER:
			_clear_order_context()
			movement.moving = false
			squad_fire.set_target_unit(null)
			squad_fire.set_target_hex(Vector2i.ZERO)
		
		SquadActionState.MOVING_TO_POSITION:
			pass
		
		SquadActionState.ESTABLISHING_POSITION:
			_start_establishing_timer()
		
		SquadActionState.HOLDING_POSITION:
			if attack_hex != Vector2i.ZERO:
				squad_fire.set_target_hex(attack_hex)
			else:
				#squad_fire.set_target_hex(Globals.objective_hexes[unit.team][0])
				squad_fire.set_target_hex(Vector2i.ZERO)
				
		
		SquadActionState.ADVANCING:
			pass
		
		SquadActionState.CROSSING_EXPOSED:
			pass
		
		SquadActionState.LOCAL_FALLBACK:
			pass
		
		SquadActionState.ROUTING:
			squad_fire.set_target_unit(null)
			squad_fire.set_target_hex(Vector2i.ZERO)
		
		SquadActionState.REGROUPING:
			movement.moving = false
			_start_regroup_timer()
		
		_:
			pass

# ----------------------------------------------------------------------
# ORDER API
# ----------------------------------------------------------------------

func give_defend_area_order(target_hex: Vector2i, path: Array[Vector3i]) -> void:
	action_order_id += 1
	
	objective_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = true
	has_attack_flag = false
	has_withdraw_flag = false
	
	_start_move_on_path(path)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_move_to_hex_order(target_hex: Vector2i, path: Array[Vector3i], take_and_hold: bool) -> void:
	action_order_id += 1
	
	objective_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = take_and_hold
	has_attack_flag = false
	has_withdraw_flag = false
	
	_start_move_on_path(path)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_attack_hex_order(target_hex: Vector2i, covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	action_order_id += 1
	
	objective_hex = target_hex
	attack_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	
	has_attack_flag = true
	has_withdraw_flag = false
	has_take_and_hold_flag = true
	
	_start_attack_covered_phase(covered_path, exposed_segment)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_withdraw_to_hex_order(target_hex: Vector2i, path: Array[Vector3i]) -> void:
	action_order_id += 1
	
	withdraw_hex = target_hex
	objective_hex = target_hex
	attack_hex = Vector2i.ZERO
	
	has_withdraw_flag = true
	has_attack_flag = false
	has_take_and_hold_flag = true
	
	_set_action_state(SquadActionState.LOCAL_FALLBACK)
	_start_move_on_path(path)


func give_hold_order() -> void:
	action_order_id += 1
	
	objective_hex = unit.current_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = true
	has_attack_flag = false
	has_withdraw_flag = false
	
	movement.moving = false
	_set_action_state(SquadActionState.HOLDING_POSITION)


func clear_orders() -> void:
	action_order_id += 1
	_set_action_state(SquadActionState.NO_ORDER)

# ----------------------------------------------------------------------
# MOVEMENT HELPERS
# ----------------------------------------------------------------------

func _start_move_on_path(path: Array[Vector3i]) -> void:
	if path.is_empty():
		_set_action_state(SquadActionState.NO_ORDER)
		return
	
	#movement.set_path(path)
	movement.follow_cube_path(path)
	#movement.start()


func _start_attack_covered_phase(covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	movement.set_attack_paths(covered_path, exposed_segment)
	movement.start_covered_phase()


func _start_establishing_timer() -> void:
	if establishing_timer.is_stopped() == false:
		establishing_timer.stop()
	establishing_timer.start()


func _start_regroup_timer() -> void:
	if regroup_timer.is_stopped() == false:
		regroup_timer.stop()
	regroup_timer.start()


func _clear_order_context() -> void:
	objective_hex = Vector2i.ZERO
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = false
	has_attack_flag = false
	has_withdraw_flag = false


func _order_still_valid() -> bool:
	var valid: bool = true
	return valid

# ----------------------------------------------------------------------
# EVENTS FROM UNIT / MOVEMENT
# ----------------------------------------------------------------------

func on_started_moving() -> void:
	if action_state == SquadActionState.NO_ORDER or action_state == SquadActionState.HOLDING_POSITION:
		_set_action_state(SquadActionState.MOVING_TO_POSITION)


func on_stopped_moving() -> void:
	match action_state:
		SquadActionState.MOVING_TO_POSITION, SquadActionState.CROSSING_EXPOSED:
			if unit.current_hex == objective_hex:
				_set_action_state(SquadActionState.ESTABLISHING_POSITION)
			else:
				_set_action_state(SquadActionState.HOLDING_POSITION)
		SquadActionState.ROUTING:
			pass
		SquadActionState.LOCAL_FALLBACK:
			if unit.current_hex == withdraw_hex:
				_set_action_state(SquadActionState.ESTABLISHING_POSITION)
			else:
				_set_action_state(SquadActionState.HOLDING_POSITION)
		_:
			pass


func on_reached_hex(hex: Vector2i) -> void:
	if hex == objective_hex:
		if action_state == SquadActionState.MOVING_TO_POSITION or action_state == SquadActionState.CROSSING_EXPOSED:
			_set_action_state(SquadActionState.ESTABLISHING_POSITION)


func on_retreat_complete(retreat_hex: Vector2i) -> void:
	if action_state == SquadActionState.ROUTING:
		_set_action_state(SquadActionState.REGROUPING)

# ----------------------------------------------------------------------
# TIMERS
# ----------------------------------------------------------------------

func _on_establishing_timer_timeout() -> void:
	if action_state == SquadActionState.ESTABLISHING_POSITION:
		_set_action_state(SquadActionState.HOLDING_POSITION)


func _on_regroup_timer_timeout() -> void:
	if action_state != SquadActionState.REGROUPING:
		return
	
	if _order_still_valid():
		_set_action_state(SquadActionState.HOLDING_POSITION)
	else:
		_set_action_state(SquadActionState.NO_ORDER)

# ----------------------------------------------------------------------
# MORALE INTEGRATION
# ----------------------------------------------------------------------

func on_morale_state_changed(prev: int, next: int) -> void:
	ui.state_changed(next)
	combat.current_state = next
	
	var rof_mult: float = 1.0
	if next == MoraleState.NORMAL:
		rof_mult = 1.0
	elif next == MoraleState.CAUTIOUS:
		rof_mult = 0.75
	elif next == MoraleState.PINNED:
		rof_mult = 0.5
	elif next == MoraleState.PANIC:
		rof_mult = 0.0
	elif next == MoraleState.COMBAT_INEFFECTIVE:
		rof_mult = 0.0
	
	if rof_mult < 0.05:
		rof_mult = 0.05
	
	combat.seconds_per_volley = combat.base_seconds_per_volley / rof_mult
	
	if next == MoraleState.PANIC:
		if action_state != SquadActionState.ROUTING:
			_start_rout()
			_set_action_state(SquadActionState.ROUTING)
		return
	
	if next == MoraleState.PINNED:
		if action_state == SquadActionState.MOVING_TO_POSITION or action_state == SquadActionState.CROSSING_EXPOSED or action_state == SquadActionState.ADVANCING:
			movement.stop()
			_set_action_state(SquadActionState.HOLDING_POSITION)


func _start_rout() -> void:
	var known_enemies: Array[Unit] = []
	#var i: int = 0
	#while i < unit.units.size():
		#var u: Unit = unit.units[i]
		#if u.team != unit.team and u.surrendered == false:
			#known_enemies.append(u)
		#i += 1
	var visible_enemies1: Array = Globals.unit_visible_enemies.get(unit, [])
	for u in visible_enemies1: # unit.units:
		if u.team != unit.team and u.surrendered == false:
			known_enemies.append(u)
	movement.rout(unit.current_hex, known_enemies, unit.retreat_distance)


func on_rout_safe_and_morale_recovered() -> void:
	if action_state == SquadActionState.ROUTING:
		movement.stop()
		_set_action_state(SquadActionState.REGROUPING)
