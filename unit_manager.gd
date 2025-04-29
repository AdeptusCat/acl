# UnitManager.gd
extends Node2D

@export var ground_layer: TileMapLayer
@export var unit_scene: PackedScene
@export var hexmap: HexagonTileMapLayer  # drag your HexagonTileMapLayer node here


var units: Array[Node2D] = []
var selected_unit: Node2D = null
var current_team: int = 0  # 0 or 1
var los_enemy_lines: Array = []
# Maps a unit -> array of enemy units it currently sees
var unit_visible_enemies: Dictionary = {}

func _ready():
	for node in get_tree().get_nodes_in_group("units"):
		if node is Node2D:
			units.append(node)
			node.unit_died.connect(_on_unit_died)

func _on_unit_died(unit):
	units.erase(unit)
	unit_visible_enemies.erase(unit)
	unit.queue_free()
	
func _input(event):
	if Input.is_action_just_pressed("LEFT"): # and event.button_index == MouseButton.LEFT
		handle_mouse_click(event.position)
	if Input.is_action_just_pressed("RIGHT"):
		place_unit_at_mouse(unit_scene, event.position)
	if Input.is_action_just_pressed("SPACE"):
		current_team = 1 if current_team == 0 else 0


func place_unit_at_mouse(unit_scene: PackedScene, mouse_pos: Vector2):
	var clicked_hex = ground_layer.local_to_map(mouse_pos)
	var snapped_position = ground_layer.map_to_local(clicked_hex)

	var unit = unit_scene.instantiate()
	unit.position = snapped_position
	unit.current_hex = clicked_hex
	unit.set_team(current_team)
	unit.hexmap = hexmap

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
		if ground_layer.local_to_map(unit.position) == clicked_hex:
			if selected_unit == unit and unit.current_hex == clicked_hex:
				selected_unit.deselect()
				selected_unit = null
				return
			else:
				if selected_unit == null:
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
	var local     = hexmap.to_local(target_pos)
	var map_coord = hexmap.local_to_map(local)

	# 2) ignore empty tiles
	if hexmap.get_cell_source_id(map_coord) == -1:
		return

	# 3) ask A* for a path
	var from_id = hexmap.pathfinding_get_point_id(current_hex)
	var to_id   = hexmap.pathfinding_get_point_id(map_coord)
	var id_path = hexmap.astar.get_id_path(from_id, to_id)

	# 4) convert to cube coords
	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var p = hexmap.astar.get_point_position(pid)
		cube_path.append( hexmap.local_to_cube(p) )

	# 5) hand it off and start walking
	selected_unit.follow_cube_path(cube_path)
	
	selected_unit.deselect()
	selected_unit = null




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
			if not enemy_unit.moving:
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
