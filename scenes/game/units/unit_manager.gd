# UnitManager.gd
extends Node2D

@export var ground_layer: HexagonTileMapLayer
@export var unit_scene: PackedScene

var team : int = 0

var units: Array[Node2D] = []
var selected_unit: Node2D = null
var current_team: int = 0  # 0 or 1
var los_enemy_lines: Array = []
# Maps a unit -> array of enemy units it currently sees
var unit_visible_enemies: Dictionary = {}

func set_input_enabled(enabled: bool):
	set_process_input(enabled)
	# Or enable/disable unit control scripts here

func _ready():
	for node in get_tree().get_nodes_in_group("units"):
		if node is Node2D:
			units.append(node)
			node.unit_died.connect(_on_unit_died)
			node.moved_to_hex.connect(_on_unit_moved)
			node.unit_arrived_at_hex.connect(_on_unit_arrived_at_hex)
			node.current_hex = ground_layer.local_to_map(node.global_position)

func _on_unit_died(unit):
	units.erase(unit)
	unit_visible_enemies.erase(unit)
	#unit.queue_free()


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		handle_mouse_click(event.position)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_SPACE:
		current_team = 1 if current_team == 0 else 0


func place_unit_at_mouse(unit_scene: PackedScene, mouse_pos: Vector2):
	var clicked_hex = ground_layer.local_to_map(mouse_pos)
	var snapped_position = ground_layer.map_to_local(clicked_hex)

	var unit : Unit = unit_scene.instantiate()
	unit.position = snapped_position
	unit.current_hex = clicked_hex
	unit.set_team(current_team)
	unit.ground_layer = ground_layer

	add_child(unit)
	unit.add_to_group("units")
	units.append(unit)

	# 🚀 Connect the move signal
	unit.moved_to_hex.connect(_on_unit_moved)
	unit.unit_died.connect(_on_unit_died)
	
	_on_unit_moved(unit, unit.current_hex)

func handle_mouse_click(mouse_pos: Vector2):
	var clicked_hex = ground_layer.local_to_map(mouse_pos)
	
	# Check if clicking on a unit
	for unit in units:
		if not unit.team == team:
			continue
		if ground_layer.local_to_map(unit.position) == clicked_hex:
			if selected_unit == unit and unit.current_hex == clicked_hex:
				selected_unit.deselect()
				selected_unit = null
				return
			else:
				if selected_unit == null and not unit.broken:
					select_unit(unit)
					return
	
	
	# If no unit clicked, try moving the selected unit
	if selected_unit != null and not selected_unit.broken:
		move_selected_unit_to(mouse_pos, clicked_hex, selected_unit.current_hex)
		

func select_unit(unit: Node2D):
	if selected_unit != null:
		selected_unit.deselect()

	selected_unit = unit
	selected_unit.select()

func move_selected_unit_to(target_pos, clicked_hex: Vector2i, current_hex: Vector2i):
	if selected_unit == null:
		return
	#selected_unit.move_to_hex(hex, ground_layer)
	#selected_unit.deselect()
	#selected_unit = null
	
	# 1) turn screen‐pos into map coords
	var local     = ground_layer.to_local(target_pos)
	var map_coord = ground_layer.local_to_map(local)

	# 2) ignore empty tiles
	if ground_layer.get_cell_source_id(map_coord) == -1:
		return

	# 3) ask A* for a path
	var from_id = ground_layer.pathfinding_get_point_id(current_hex)
	var to_id   = ground_layer.pathfinding_get_point_id(map_coord)
	var id_path = ground_layer.astar.get_id_path(from_id, to_id)

	# 4) convert to cube coords
	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var p = ground_layer.astar.get_point_position(pid)
		cube_path.append( ground_layer.local_to_cube(p) )

	if not selected_unit == null:
		# 5) hand it off and start walking
		selected_unit.movement.follow_cube_path(cube_path)
	if not selected_unit == null:
		selected_unit.deselect()
		selected_unit = null

func _restack_units_in_hex(hex: Vector2i):
	# collect alive units in this hex
	var stack := []
	for u in units:
		if u.alive and u.current_hex == hex:
			stack.append(u)

	var count = stack.size()
	if count == 0:
		return

	var base_pos = ground_layer.map_to_local(hex)

	if count == 1:
		# single‐unit stays centered
		stack[0].position = base_pos
		stack[0].z_index   = 0
	else:
		# spacing in pixels between each sprite
		var spacing = 16
		# center_index so that the whole column is centered on base_pos.y
		var center_index = (count - 1) / 2.0
		for i in range(count):
			var u = stack[i]
			# compute Y offset: units above get negative y, below get positive y
			var y_off = (i - center_index) * spacing
			u.position = base_pos + Vector2(0, y_off)
			u.z_index  = i   # draw in order, top to bottom


func _restack_units():
	# 1) Group units by their current_hex
	var groups := {}
	for u in units:
		if not u.alive:
			continue
		var h = u.current_hex
		if not groups.has(h):
			groups[h] = []
		groups[h].append(u)

	# 2) For each hex, if there’s 1 unit keep it centered;
	#    if >1, spread them in a little circle.
	var center_offset = Vector2.ZERO
	for h in groups.keys():
		var group = groups[h]
		var base_pos = ground_layer.map_to_local(h)
		var cnt = group.size()

		if cnt == 1:
			group[0].position = base_pos
			group[0].z_index   = 0
		else:
			# radius in pixels you want units spread around
			var radius = 16  
			for i in range(cnt):
				# evenly space them in a circle
				var angle = TAU * i / cnt  # TAU = 2*PI
				var offset = Vector2(cos(angle), sin(angle)) * radius
				var u = group[i]
				u.position = base_pos + offset
				# Optional: layer them so they don’t z-fight
				u.z_index = i

func _on_unit_arrived_at_hex(hex):
	_restack_units_in_hex(hex)


func _on_unit_moved(unit, vector):
	if not unit.alive:
		return
	
	var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])

	# Clear old visibility info for this unit
	unit_visible_enemies[unit] = []

	for enemy_unit in units:
		if enemy_unit == unit:
			continue
		if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
			draw_los_to_enemy(unit.current_hex, enemy_unit.current_hex)
			if not unit_visible_enemies.has(unit):
				continue
			unit_visible_enemies[unit].append(enemy_unit)

			# Fire immediately if stationary (optional fast reaction shot)
			if not enemy_unit.movement.moving:
				var distance = enemy_unit.current_hex.distance_to(unit.current_hex)
				# safely grab the inner dict for this shooter-hex
				var cover_map = LOSHelper.los_lookup.get(enemy_unit.current_hex, null)
				var targetCover 
				if cover_map and cover_map.has(unit.current_hex):
					var data        = cover_map[unit.current_hex]
					targetCover = data["target_cover"]
				else:
					targetCover = 0  # no LOS or no cover entry

				# now display it
				unit.set_cover(targetCover)
				enemy_unit.fire_at(unit, distance, targetCover)

	# 🔥 Update LOS for all units too (global re-check)
	update_all_unit_visibilities()

func update_all_unit_visibilities():
	for unit in units:
		if not unit.alive:
			continue
		var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])
		unit_visible_enemies[unit] = []

		for enemy_unit in units:
			if enemy_unit == unit or not enemy_unit.alive:
				continue
			if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
				unit_visible_enemies[unit].append(enemy_unit)
				
func draw_los_to_enemy(from_hex: Vector2i, to_hex: Vector2i):
	var from_pos = ground_layer.map_to_local(from_hex)
	var to_pos = ground_layer.map_to_local(to_hex)

	los_enemy_lines.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 2.0  # Line fades out over 2 seconds
	})

	queue_redraw()

func _draw():
	# 🔥 New: Draw blue lines to visible enemies
	for los_data in los_enemy_lines:
		draw_line(los_data["from"], los_data["to"], Color(0, 0, 1), 2.0)

func _process(delta):
	for line in los_enemy_lines:
		line["timer"] += delta

	# Remove fully expired lines
	los_enemy_lines = los_enemy_lines.filter(func(line):
		return line["timer"] < line["duration"]
	)

	queue_redraw()  # Always request redraw if lines change
