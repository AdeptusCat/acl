extends Node

@onready var ground    = $"../GroundLayer"
@onready var container = $"../UnitContainer"

func _ready():
	var input = $"../InputManager"
	input.connect("move_requested", self, "_on_move_requested")
	# listen when any unit lands
	for u in container.get_children():
		u.connect("unit_arrived_at_hex", self, "_on_arrived")

func _on_move_requested(_, to_hex):
	var sel = get_tree().get_root().find_node("SelectedUnit", true, false)
	if not sel: return
	var path = _compute_path(sel.current_hex, to_hex)
	sel.movement.follow_cube_path(path)

func _compute_path(from_h, to_h):
	var id1 = ground.pathfinding_get_point_id(from_h)
	var id2 = ground.pathfinding_get_point_id(to_h)
	var raw = ground.astar.get_id_path(id1, id2)
	return raw.map(func(pid): ground.local_to_cube( ground.astar.get_point_position(pid) ))

func _on_arrived(hex):
	_restack_in_hex(hex)

func _restack_in_hex(hex):
	var stack = container.get_children().filter(func(u): u.current_hex==hex and u.alive)
	# …same restack logic you had…
