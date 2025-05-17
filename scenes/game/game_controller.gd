extends Node2D

@onready var input_mgr      = $InputManager
@onready var ground_layer   = $GroundLayer
@onready var unit_container = $UnitContainer
@onready var move_sys       = $MovementSystem
@onready var combat_sys     = $CombatSystem
@onready var los_renderer   = $LOSRenderer

var selected_unit: Node2D = null

func _ready():
	input_mgr.mouse_clicked.connect(_on_mouse_clicked)
	combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)

func _on_mouse_clicked(pos: Vector2):
	var map_hex = ground_layer.local_to_map(pos)
	var unit = _find_unit_at(map_hex)
	if unit and unit.team == turn_mgr.current_team and not unit.broken:
		_select_unit(unit)
	elif selected_unit:
		move_sys.request_move(selected_unit, map_hex)

func _on_turn_changed(new_team):
	selected_unit = null  # clear selection, UI will update

func _select_unit(unit):
	if selected_unit:
		selected_unit.deselect()
	selected_unit = unit
	unit.select()

func _find_unit_at(hex: Vector2i) -> Node2D:
	for u in unit_container.get_children():
		if u.current_hex == hex:
			return u
	return null
