extends Node

signal ai_placement_visibility_changed(enabled: bool)
signal debug_text_visibility_changed(enabled: bool)

var show_ai_placement: bool = false:
	set(value):
		if show_ai_placement == value:
			return
		show_ai_placement = value
		ai_placement_visibility_changed.emit(value)
var show_debug_text: bool = false:
	set(value):
		if show_debug_text == value:
			return
		show_debug_text = value
		debug_text_visibility_changed.emit(value)

var enemy_selectable: bool = false
var no_damage: bool = false
var draw_thread_map: bool = false
var draw_thread_map_enemy: bool = false
var showEnemyCmdConnectivity: bool = false
var dont_fire_wepaons: bool = false
var show_los_lines: bool = false
var show_movement_lines: bool = false
var hide_fog_of_war: bool = false
var show_enemies: bool = false

var units_to_kill: Array[Unit] = []
var units_soldier_to_kill: Array[Unit] = []
var units_to_surrender: Array[Unit] = []

var influence_map_name: String = ""
var influence_map_team_name: String = ""
