# SquadFireController.gd
extends Node
class_name SquadFireController

# Wiring
@export var unit: Unit
@export var combat: UnitCombat
@export var stress_controller: StressController

# Timing
@export var burst_window_s: float = 0.10      # batch rounds within this window per hex
@export var max_shots_per_tick: int = 128

# State influence (from your STATES table)
@export var state_acc_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.5, 0.0, 0.0])
@export var state_rof_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.85, 0.35, 0.0, 0.0])

# NEW: state influence on target acquisition time (Normal..CombatIneffective)
@export var state_acquire_mults: PackedFloat32Array = PackedFloat32Array([1.0, 1.15, 1.6, 9999.0, 9999.0])
# panic/CI effectively “never acquire”

# Crew-served behaviour
@export var crew_idle_to_loader: bool = true

# Soldiers
var soldiers: Array[Soldier] = []
var _now_s: float = 0.0
var _accum_window_s: float = 0.0

# Targeting
var target_hex: Vector2i
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int

signal fire_shot

func set_soldiers(list: Array[Soldier]) -> void:
	soldiers = list

func set_target_hex(hx: Vector2i) -> void:
	#if not target_hex == hx and not hx == Vector2i.ZERO:
	if not hx == Vector2i.ZERO:
		_prime_acquisition_for_new_target()
	target_hex = hx

func _physics_process(delta: float) -> void:
	_now_s += delta
	_accum_window_s += delta

	_update_state_multipliers()
	_tick_soldiers(delta)

	if _accum_window_s >= burst_window_s:
		_flush_burst_window()

func _update_state_multipliers() -> void:
	var state_idx: int = stress_controller.state
	var acc_mult: float = 1.0
	var rof_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acc_mults.size():
		acc_mult = state_acc_mults[state_idx]
	if state_idx >= 0 and state_idx < state_rof_mults.size():
		rof_mult = state_rof_mults[state_idx]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			s.acc_mult = acc_mult
			s.rof_mult = rof_mult
		i += 1

func _tick_soldiers(delta: float) -> void:
	var rounds_emitted: int = 0

	# count available crew for MGs
	var crew_available: int = _count_role(RankGrades.Role.LOADER)
	var gunners: Array[int] = _indices_with_role(RankGrades.Role.GUNNER)

	# handle gunners first (crew-served)
	var j: int = 0
	while j < gunners.size():
		var idx: int = gunners[j]
		var s: Soldier = soldiers[idx]
		if s.is_alive:
			rounds_emitted += _try_fire_soldier(s, true, crew_available)
			if rounds_emitted >= max_shots_per_tick:
				return
		j += 1

	# then everyone else
	var i: int = 0
	while i < soldiers.size():
		var s2: Soldier = soldiers[i]
		if s2.is_alive:
			if s2.role != RankGrades.Role.GUNNER:
				rounds_emitted += _try_fire_soldier(s2, false, 0)
				if rounds_emitted >= max_shots_per_tick:
					return
		i += 1

func _try_fire_soldier(s: Soldier, is_crew_served: bool, crew_available: int) -> int:
	if target_hex == Vector2i.ZERO:
		return 0
	
	# acquisition gate: don’t shoot until settled on the new target
	if _now_s < s.acquire_ready_s:
		return 0
	
	if s.jammed:
		# simple unjam: use reload time as clear jam delay
		if s.next_ready_s <= _now_s:
			s.jammed = false
			s.next_ready_s = _now_s + s.weapon.reload_s
		return 0

	if s.next_ready_s > _now_s:
		return 0

	# check crew requirement
	var crew_mult: float = 1.0
	if is_crew_served:
		if s.weapon.crew_required > 1:
			var ok: bool = crew_available >= (s.weapon.crew_required - 1)
			if not ok:
				crew_mult = s.weapon.undercrew_penalty_mult

	# determine burst size for this weapon
	var shots: int = s.weapon.burst_rounds
	if shots < 1:
		shots = 1
	if shots > s.rounds_in_mag:
		shots = s.rounds_in_mag

	if shots <= 0:
		# reload
		s.next_ready_s = _now_s + s.weapon.reload_s
		s.rounds_in_mag = s.weapon.mag_capacity
		return 0

	# emit shots immediately into current window
	_add_rounds_to_hex(target_hex, shots)
	fire_shot.emit()

	# apply jam chance
	var k: int = 0
	var jammed_now: bool = false
	while k < shots:
		var r: float = randf()
		if r < s.weapon.jam_per_shot:
			jammed_now = true
		k += 1
	if jammed_now:
		s.jammed = true

	# spend ammo
	s.rounds_in_mag -= shots
	
	# cadence to next burst (respect soldier’s rof and crew)
	var rps: float = s.weapon.rpm / 60.0
	if rps < 1.0:
		rps = 1.0
	var fire_time_s: float = float(shots) / rps
	var pause_s: float = s.weapon.burst_pause_s
	var total_cadence_s: float = (fire_time_s + pause_s) * s.rof_mult * crew_mult

	# keep a little persistent desync in the rhythm
	var phase_bump: float = s.cadence_phase_s * 0.20  # small influence after first burst
	s.next_ready_s = _now_s + total_cadence_s + phase_bump
	
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]
	var settle_s: float = _calc_acquire_delay(s) * acquire_mult
	s.next_ready_s += settle_s
	
	var delta: float = s.next_ready_s - _now_s
	return shots

func _add_rounds_to_hex(hx: Vector2i, n: int) -> void:
	var cur: int = 0
	if _pending_rounds_by_hex.has(hx):
		cur = int(_pending_rounds_by_hex[hx])
	_pending_rounds_by_hex[hx] = cur + n

func _flush_burst_window() -> void:
	_accum_window_s = 0.0
	for hx in _pending_rounds_by_hex.keys():
		var rounds: int = int(_pending_rounds_by_hex[hx])
		if rounds > 0:
			_emit_burst_to_combat(hx, rounds)
	_pending_rounds_by_hex.clear()

func _emit_burst_to_combat(hx: Vector2i, rounds: int) -> void:
	if combat == null:
		return
	# Call your existing burst/volley entrypoint.
	# Expectation from earlier: resolve TOTAL rounds once per volley for that hex.
	if combat.has_method("fire_burst_total_rounds"):
		combat.call("fire_burst_total_rounds", unit, hx, rounds)
		return
	# Fallback: if you only have fire_at(), you can adapt it or add a proper method.


func _count_role(role: int) -> int:
	var c: int = 0
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				c += 1
		i += 1
	return c

func _indices_with_role(role: int) -> Array[int]:
	var res: Array[int] = []
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				res.append(i)
		i += 1
	return res


func _prime_acquisition_for_new_target() -> void:
	# called whenever target_hex changes
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			#var changed: bool = s.last_target_hex != target_hex
			#if changed:
			var settle_s: float = _calc_acquire_delay(s) * acquire_mult
			# add the soldier's fixed cadence phase so first bursts don’t sync
			settle_s += s.cadence_phase_s
			s.acquire_ready_s = _now_s + settle_s
			s.last_target_hex = target_hex
			# ensure we don’t fire before we’ve acquired, even if next_ready_s was in the past
			if s.next_ready_s < s.acquire_ready_s:
				s.next_ready_s = s.acquire_ready_s
		i += 1


func _calc_acquire_delay(s: Soldier) -> float:
	# prefer weapon raise/aim timings if available; else use soldier base
	var base: float = s.base_acquire_s
	if s.weapon != null:
		var has_raise: bool = s.weapon.raise_s > 0.0
		var has_aim: bool = s.weapon.aim_s > 0.0
		if has_raise or has_aim:
			base = s.weapon.raise_s + s.weapon.aim_s
	# add a random bit per target switch
	var jitter: float = randf_range(0.0, s.aim_jitter_s)
	return base + jitter
