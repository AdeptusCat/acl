# UnitMorale.gd
class_name UnitMorale
extends Node

# Dependencies
var unit: Node2D

# External variables (can be set externally or injected)
var morale: int = 7
var morale_meter_max: int = 100
var base_death_chance: float = 0.1
var broken_death_multiplier: float = 2.0
var recovery_time_max: float = 5.0

# Runtime state
var morale_meter_current: int = 0
var recovery_timer_current: float = 0.0
var broken: bool = false
var alive: bool = true

# Node references (optional)
var morale_bar
var broken_label
var morale_popup_scene: PackedScene
var morale_flash_scene: PackedScene

var morale_ui : UnitMoraleUI

func _init(_unit: Node2D):
	unit = _unit

func receive_fire(incoming_firepower: int, is_moving: bool, terrain_defense_bonus: float):
	if not alive:
		return

	if broken:
		recovery_timer_current = 0.0

	unit.cover_label.text = str(terrain_defense_bonus)

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

	morale_meter_current += int(morale_impact)
	morale_meter_current = min(morale_meter_current, morale_meter_max)

	morale_ui.update_bar(morale_meter_current, morale_meter_max)

	if morale_meter_current >= morale_meter_max:
		make_morale_check()


func make_morale_check():
	var death_chance = base_death_chance
	if broken:
		death_chance *= broken_death_multiplier

	if randf() < death_chance:
		unit.die()
		return

	var roll = randi_range(2, 12)
	if roll > morale:
		if unit.selected:
			unit.get_parent().selected_unit = null
			unit.deselect()
		morale_ui.show_failure()
		unit._on_morale_failed(unit.get_visible_enemies())
		broken = true
		broken_label.visible = true
		recovery_timer_current = 0.0
	else:
		morale_meter_current = 0
		morale_ui.show_success()


func update_morale_bar():
	if morale_bar:
		var fill_ratio = float(morale_meter_current) / float(morale_meter_max)
		fill_ratio = clamp(fill_ratio, 0.0, 1.0)
		morale_bar.scale.x = fill_ratio

		if fill_ratio < 0.5:
			morale_bar.color = Color(0, 1, 0)
		elif fill_ratio < 0.8:
			morale_bar.color = Color(1, 1, 0)
		else:
			morale_bar.color = Color(1, 0, 0)


func _process_recovery(delta: float) -> void:
	recovery_timer_current += delta
	if recovery_timer_current >= recovery_time_max:
		_recover()


func _recover() -> void:
	broken = false
	if broken_label:
		broken_label.visible = false
	morale_meter_current = 0
	update_morale_bar()
	morale_ui.show_success()
