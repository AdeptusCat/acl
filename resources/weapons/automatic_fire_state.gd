class_name AutomaticFireState
extends RefCounted

# Runtime state belongs to the physical gun, including every carried barrel.
# Heat is measured in equivalent rounds above ambient, not degrees Celsius.
var barrel_heat: Array[float] = [0.0]
var active_barrel: int = 0
var heat_locked: bool = false
var swap_barrel: int = -1
var swap_remaining_s: float = 0.0
var pause_remaining_s: float = 0.0
var rapid_credit_s: float = 0.0
var rapid_active: bool = false


func reset(weapon: WeaponSpec) -> void:
	barrel_heat.clear()
	for index: int in range(maxi(weapon.spare_barrels, 0) + 1):
		barrel_heat.append(0.0)
	active_barrel = 0
	heat_locked = false
	swap_barrel = -1
	swap_remaining_s = 0.0
	pause_remaining_s = 0.0
	rapid_credit_s = weapon.rapid_window_s
	rapid_active = false


func heat() -> float:
	return barrel_heat[active_barrel]


func advance(delta: float, weapon: WeaponSpec) -> void:
	var elapsed: float = maxf(delta, 0.0)
	for index: int in range(barrel_heat.size()):
		barrel_heat[index] = maxf(0.0, barrel_heat[index] - weapon.barrel_cooling_per_s * elapsed)
	pause_remaining_s = maxf(0.0, pause_remaining_s - elapsed)
	if rapid_active:
		rapid_credit_s = maxf(0.0, rapid_credit_s - elapsed)
		if rapid_credit_s <= 0.0:
			rapid_active = false
	else:
		rapid_credit_s = minf(weapon.rapid_window_s, rapid_credit_s + elapsed * weapon.rapid_window_s / maxf(weapon.rapid_recovery_s, 0.1))
	if heat_locked and heat() <= weapon.heat_resume:
		heat_locked = false


func record_round(weapon: WeaponSpec) -> void:
	barrel_heat[active_barrel] += weapon.heat_per_round
	if heat() >= weapon.heat_hard_limit:
		heat_locked = true
		rapid_active = false


func select_rapid(weapon: WeaponSpec, opportunity: bool) -> bool:
	if not opportunity or heat() >= weapon.heat_soft_limit or heat_locked:
		rapid_active = false
		return false
	if not rapid_active and rapid_credit_s >= weapon.rapid_window_s - 0.00001:
		rapid_active = true
		# A newly exposed target can interrupt an observation pause.
		pause_remaining_s = minf(pause_remaining_s, weapon.rapid_pause_s)
	return rapid_active


func finish_burst(weapon: WeaponSpec, rapid: bool, suppressed: bool, variation: float) -> void:
	var pause: float = weapon.sustained_pause_s
	if rapid:
		pause = weapon.rapid_pause_s
	elif suppressed:
		pause *= 1.75
	var hot: float = inverse_lerp(weapon.heat_soft_limit, weapon.heat_hard_limit, heat())
	pause *= lerpf(1.0, 3.0, clampf(hot, 0.0, 1.0))
	pause_remaining_s = maxf(pause_remaining_s, pause * variation)


func begin_barrel_change(weapon: WeaponSpec) -> bool:
	if swap_barrel >= 0 or heat() < weapon.heat_soft_limit or weapon.barrel_change_s <= 0.0:
		return false
	var coolest: int = -1
	for index: int in range(barrel_heat.size()):
		if index == active_barrel or barrel_heat[index] > weapon.heat_resume:
			continue
		if coolest < 0 or barrel_heat[index] < barrel_heat[coolest]:
			coolest = index
	if coolest < 0:
		return false
	swap_barrel = coolest
	swap_remaining_s = weapon.barrel_change_s
	return true


func advance_barrel_change(work: float, weapon: WeaponSpec) -> bool:
	if swap_barrel < 0:
		return false
	swap_remaining_s = maxf(0.0, swap_remaining_s - maxf(work, 0.0))
	if swap_remaining_s > 0.0:
		return false
	active_barrel = swap_barrel
	swap_barrel = -1
	heat_locked = heat() > weapon.heat_resume
	return true
