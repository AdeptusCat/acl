@tool
extends Node2D
class_name Unit

# === Exported ===
@export var snap_to_grid := true
@export var ground_map: HexagonTileMapLayer
@export var firepower: int = 4
@export var range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false
@export var morale_meter_max: int = 100
@export var base_death_chance: float = 0.1
@export var broken_death_multiplier: float = 2.0
@export var recovery_time_max: float = 5.0
@export var team: int = 0
@export var retreat_distance := 3
@export var retreat_speed := 100.0
@export var fire_rate: float = 1.5


# === Runtime State ===
var morale_meter_current: int = 0
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var alive: bool = true
var broken: bool = false
var recovery_timer_current: float = 0.0
var current_cover_bonus: int = 0
var current_hex: Vector2i
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var move_speed: float = 100.0
var retreat_target_hex: Vector2i = Vector2i()


# === Signals ===
signal moved_to_hex(new_hex: Vector2i)
signal unit_arrived_at_hex(new_hex: Vector2i)
signal unit_died(unit)
signal retreat_complete(retreat_hex: Vector2i)
signal cover_updated(value: float)
signal deselect_unit(unit)

# === Nodes ===
@onready var ui := $UnitUi


# === Classes ===
@onready var morale_system := UnitMorale.new(self)
#@onready var morale_ui := UnitMoraleUI.new(self)
@onready var movement := UnitMovement.new(self)
@onready var combat := UnitCombat.new()


# === Ready ===
func _ready():
	update_team_sprite(team)
	connect("retreat_complete", _on_retreat_complete)
	morale_system.morale_breaks.connect(_on_morale_breaks)
	morale_system.morale_recovered.connect(_on_morale_recovered)
	#morale_system.unit_recovers.connect(_on_unit_recovers)
	
	morale_system.morale_updated.connect(ui._on_morale_updated)
	morale_system.morale_failure.connect(ui._on_morale_failure)
	morale_system.morale_success.connect(ui._on_morale_success)
	morale_system.morale_recovered.connect(ui._on_morale_recovered)
	morale_system.morale_breaks.connect(ui._on_morale_breaks)
	cover_updated.connect(ui._on_cover_updated)
	
	unit_arrived_at_hex.connect(ui._on_unit_arrived_at_hex)
	movement.started_moving.connect(ui._on_started_moving)
	movement.stopped_moving.connect(ui._on_stopped_moving)
	#morale_system.morale_recovered.connect(ui._on_morale_recovered)
	
	combat.shoot.connect(ui.shoot)
	
	movement.ground_map = ground_map

	movement.started_moving.connect(_on_started_moving)
	movement.stopped_moving.connect(_on_stopped_moving)
	add_child(combat)


func _on_started_moving():
	moving = true


func _on_stopped_moving():
	moving = false


func _on_morale_breaks():
	if selected:
		deselect_unit.emit(self)
		deselect()
	broken = true


func _on_morale_recovered():
	broken = false


# === Process Loop ===
func _process(delta):
	if Engine.is_editor_hint() and snap_to_grid:
		if ground_map == null:
			return
		snap_to_hex()
		var map_coords = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)
		current_hex = map_coords
		set_team(team)
		return

	if not alive:
		return

	morale_system._process_recovery(delta)
	
	movement.process(delta)


# === Utility ===
func snap_to_hex():
	if ground_map:
		var map_coords = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)


func select():
	ui.select()
	selected = true


func deselect():
	ui.deselect()
	selected = false


func set_cover(cover_value: int) -> void:
	ui.set_cover(cover_value)


func get_visible_enemies(unit_visible_enemies: Dictionary) -> Array:
	return unit_visible_enemies.get(self, [])


func set_team(new_team: int):
	team = new_team
	update_team_sprite(team)


func update_team_sprite(team: int):
	ui.update_team_sprite(team)


func fire_at(target: Node2D, distance_in_hexes: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
	if not alive:
		return
	combat.fire_at(self, target, current_hex, distance_in_hexes, terrain_defense_bonus, firepower, range, unit_visible_enemies, fire_rate, )


func receive_fire(incoming_firepower: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
	morale_system.receive_fire(incoming_firepower, movement.moving, terrain_defense_bonus, unit_visible_enemies)
	cover_updated.emit(int(terrain_defense_bonus))


func die():
	alive = false
	emit_signal("unit_died", self)
	await ui.die()
	queue_free()


func _on_morale_failed(known_enemies: Array) -> void:
	movement.rout(current_hex, known_enemies, retreat_distance)


func _on_retreat_complete(retreat_hex) -> void:
	movement.moving = false
	current_hex = retreat_hex
	emit_signal("moved_to_hex", self, current_hex)
