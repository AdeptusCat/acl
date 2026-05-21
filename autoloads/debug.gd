extends Node

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
