extends Node2D

@onready var input_mgr      = $"../InputManager"
@onready var ground_layer   = $"../GroundTileMapLayer"
@onready var unit_container = $"../UnitContainer"
@onready var move_sys       = $"../MovementSystem"
@onready var combat_sys     = $"../CombatSystem"
@onready var los_renderer   = $"../LOSRenderer"

var current_team: int = 0
var selected_unit: Node2D = null
var units: Array[Node2D] = []
var unit_visible_enemies: Dictionary

func _ready():
	input_mgr.mouse_button_left_pressed.connect(_on_mouse_button_left_pressed)
	input_mgr.key_space_pressed.connect(_on_key_space_pressed)
	#combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)
	for child in $"../UnitManager".get_children():
		child.unit_arrived_at_hex.connect(move_sys._on_arrived)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Node2D:
			units.append(unit)
			unit.unit_died.connect(_on_unit_died)
			unit.moved_to_hex.connect(combat_sys._on_unit_moved)
			unit.unit_arrived_at_hex.connect(move_sys._on_arrived)
			unit.current_hex = ground_layer.local_to_map(unit.global_position)
			unit.deselect_unit.connect(_deselect_unit)
			
	combat_sys.unit_visible_enemies = unit_visible_enemies
	combat_sys.units = units
	move_sys.unit_visible_enemies = unit_visible_enemies
	move_sys.units = units
	combat_sys.draw_los_to_enemy.connect(los_renderer._on_draw_los_to_enemy)
	
	
func _on_mouse_button_left_pressed(event_pos: Vector2):
	var map_hex = ground_layer.local_to_map(event_pos)
	var unit = _find_unit_at(map_hex)
	if unit and unit.team == current_team and not unit.broken:
		_select_unit(unit)
	elif selected_unit:
		move_sys._on_move_requested(selected_unit, map_hex)
		_deselect_unit(selected_unit)


func _on_key_space_pressed(event_pos: Vector2):
	pass


func _select_unit(unit):
	if selected_unit:
		selected_unit.deselect()
	selected_unit = unit
	unit.select()


func _deselect_unit(unit):
	if selected_unit == unit:
		selected_unit.deselect()
		selected_unit = null


func _find_unit_at(hex: Vector2i) -> Node2D:
	for u in unit_container.get_children():
		if u.current_hex == hex:
			return u
	return null


func _on_unit_died(unit):
	units.erase(unit)
	unit_visible_enemies.erase(unit)
	#unit.queue_free()
