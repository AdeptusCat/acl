# UnitMorale.gd
class_name UnitMorale
extends Node

# Dependencies
var unit: Node2D

# External variables (can be set externally or injected)
var morale: int = 7
var morale_meter_max: float = 100
var base_death_chance: float = 0.1
var broken_death_multiplier: float = 2.0
var recovery_time_max: float = 5.0

# Runtime state
var morale_meter_current: float = 0
var recovery_timer_current: float = 0.0

signal morale_updated(current: int, max: int)
signal morale_failure
signal morale_success
signal morale_recovered
signal morale_breaks


func _init(_unit: Node2D):
	unit = _unit

func receive_fire(incoming_firepower: int, is_moving: bool, terrain_defense_bonus: float):
	if not unit.alive or unit.surrendered:
		return

	if unit.broken:
		recovery_timer_current = 0.0

	var attack_roll = randi_range(2, 12)
	var morale_impact = incoming_firepower * 8

	if attack_roll <= 4:
		morale_impact *= 1.5
	elif attack_roll >= 10:
		morale_impact *= 0.5

	if terrain_defense_bonus > 0:
		morale_impact *= (1 / (terrain_defense_bonus * 2))

	if is_moving:
		morale_impact *= 1.25

	morale_meter_current += morale_impact
	morale_meter_current = min(morale_meter_current, morale_meter_max)

	morale_updated.emit(morale_meter_current, morale_meter_max)

	if morale_meter_current >= morale_meter_max:
		make_morale_check()


func make_morale_check():
	return
	var death_chance = base_death_chance
	if unit.broken:
		death_chance *= broken_death_multiplier

	if randf() < death_chance:
		#return # debug
		unit.die()
		return

	var roll = randi_range(2, 12)
	if roll > morale:
	#if true: # debug
		if unit.broken or unit.surrendered: 
			# otherwise the unit searches for another hex to retreat to, 
			# which would be fine, if the current hex wouldnt be the one where the rout started, 
			# think about it
			return
		unit.broken = true
		var visible_enemies: Array = Globals.unit_visible_enemies.get(get_parent(), [])
		morale_breaks.emit()
		unit._on_morale_failed(visible_enemies)
		recovery_timer_current = 0.0
	else:
		morale_meter_current = 0
		morale_updated.emit(morale_meter_current, morale_meter_max)
		morale_success.emit()



func _process_recovery(delta: float) -> void:
	if unit.broken and not unit.surrendered:
		recovery_timer_current += delta
		if recovery_timer_current >= recovery_time_max:
			_recover()
	else:
		if morale_meter_current > 0:
			
			var x : float = (delta * 2.0)
			morale_meter_current -= x
			morale_meter_current = max(morale_meter_current, 0.0)
			morale_updated.emit(morale_meter_current, morale_meter_max)

func _recover() -> void:
	unit.broken = false
	morale_meter_current = 0
	morale_updated.emit(morale_meter_current, morale_meter_max)
	morale_recovered.emit()
