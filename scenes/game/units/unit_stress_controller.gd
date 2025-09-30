# stress_controller.gd (replaces unit_morale.gd)
class_name StressController
extends Node

enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

@export var half_life_fast := 4.0    # seconds
@export var half_life_slow := 28.0   # seconds
@export var w_fast := 0.6
@export var w_slow := 0.4
@export var refractory_s := 1.2      # no flips for this long after a change
@export var leadership_bonus := 0.0  # 0..1, from leader presence/quality
@export var cohesion := 1.0          # 0..1, formation tightness / dispersion

var stress_fast := 0.0
var stress_slow := 0.0
var S_eff := 0.0
var state := MoraleState.NORMAL
var _since_change := 999.0

# thresholds are *rates* turned into per-tick probs; tune these
@export var pin_threshold := 35.0
@export var panic_threshold := 65.0
@export var recovery_bias := 0.85    # easier to slip back upward when leadership/cover good

signal state_changed

func _physics_process(delta:float) -> void:
	# decay (exponential via half-life)
	var kf = pow(0.5, delta/half_life_fast)
	var ks = pow(0.5, delta/half_life_slow)
	stress_fast *= kf
	stress_slow *= ks

	# effective stress with leadership & cohesion softening
	var softener = 1.0 - clamp(0.5*leadership_bonus + 0.3*cohesion, 0.0, 0.6)
	S_eff = (w_fast*stress_fast + w_slow*stress_slow) * softener

	_since_change += delta
	_maybe_transition(delta)

func apply_stress(df:float, ds:float) -> void:
	stress_fast += df
	stress_slow += ds

func on_casualty_event(n:int, leader_down:bool=false) -> void:
	# casualty shock
	stress_fast += 18.0 * n
	stress_slow += 6.0 * n
	if leader_down:
		stress_fast += 22.0
		stress_slow += 10.0

func _maybe_transition(delta:float) -> void:
	if _since_change < refractory_s:
		return

	var roll := randf()

	match state:
		MoraleState.NORMAL:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.6, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff >= pin_threshold and roll < _rate_to_prob(0.45, delta):
				_set_state(MoraleState.PINNED)
			elif S_eff >= pin_threshold*0.7 and roll < _rate_to_prob(0.3, delta):
				_set_state(MoraleState.CAUTIOUS)

		MoraleState.CAUTIOUS:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.5, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff < pin_threshold*0.6 and roll < _rate_to_prob(0.35*recovery_bias, delta):
				_set_state(MoraleState.NORMAL)
			elif S_eff >= pin_threshold and roll < _rate_to_prob(0.4, delta):
				_set_state(MoraleState.PINNED)

		MoraleState.PINNED:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.45, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff < pin_threshold*0.6 and roll < _rate_to_prob(0.25*recovery_bias, delta):
				_set_state(MoraleState.CAUTIOUS)

		MoraleState.PANIC:
			# recover if stress drops and leadership/cohesion help
			if S_eff < pin_threshold*0.7 and roll < _rate_to_prob(0.18*recovery_bias, delta):
				_set_state(MoraleState.CAUTIOUS)

func _rate_to_prob(rate_per_sec:float, dt:float) -> float:
	# converts continuous-time hazard rate to per-tick probability
	return 1.0 - exp(-max(rate_per_sec, 0.0) * dt)

func _set_state(next:int) -> void:
	if next == state:
		return
	var prev := state
	state = next
	_since_change = 0.0
	state_changed.emit(prev, next)
	#get_parent().emit_signal("state_changed", prev, next)
