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
