extends Node2D
@onready var tile_map = $TileMapLayer3
var grid := []

# setter / getter
func set_cell_data(cell: Vector2i, value):
	grid[cell.y][cell.x] = value

func get_cell_data(cell: Vector2i):
	if (cell.x < grid.size()):
		if(cell.y < grid[cell.x].size()):
			return grid[cell.y][cell.x]

func _ready() -> void:
	
	var mask: int = tile_map.tile_set.get_physics_layer_collision_layer(0)
	print(mask)
	
	var map3 = $TileMapLayer3
	var map4 = $TileMapLayer4
	
	for y in range(10):
		grid.append([])
		for x in range(10):
			grid[y].append(null)      # or a dict of per-cell properties
			var cell = Vector2(x, y)
			var props = {}

			var td3 = map3.get_cell_tile_data(cell)
			if td3 != null:
				props["elevation"] = td3.get_custom_data("elevation")

			var td4 = map4.get_cell_tile_data(cell)
			if td4 != null:
				props["cover"] = td4.get_custom_data("cover")

			if props.size() > 0:
				set_cell_data(cell, props)
	lol()

func lol():
	for x in range(10):
		for y in range(10):
			var data1 = $TileMapLayer3.get_cell_tile_data(Vector2(x, y))
			var data2 = $TileMapLayer3.get_cell_tile_data(Vector2(x, y))
	#var data1 = $TileMapLayer3.get_cell_tile_data(Vector2(0, -2))
	#var elev1  = data1.get_custom_data("elevation")
	#var data2 = $TileMapLayer4.get_cell_tile_data(Vector2(0, -2))
	#var cover2  = data2.get_custom_data("cover")
	#print(elev1)
	#print(cover2)
	# 1) get the TileMap and collision point from the raycast
	await get_tree().physics_frame    # wait for physics to run once
	$RayCast2D.force_raycast_update()
	if $RayCast2D.is_colliding():
		print("Hit this frame!")
	var tm   = $RayCast2D.get_collider()                  # the TileMap node
	var hitp = $RayCast2D.get_collision_point()           # in world coords
	print(tm)
	# 2) convert world → local → cell coords
	#var localp = tm.to_local(hitp)
	#var cell   = tm.local_to_map(localp)
	
	# 3) fetch the TileData and read your custom fields
	var data1 = $TileMapLayer3.get_cell_tile_data(Vector2(0, -2))
	var data2 = $TileMapLayer4.get_cell_tile_data(Vector2(0, -2))
	if data1:
		var elev  = data1.get_custom_data("elevation")     # int you set in the TileSet
		var terr  = data2.get_custom_data("cover")  # String you set       :contentReference[oaicite:0]{index=0}
		print(elev)
		print(terr)
	else:
		pass
		# empty cell or non-atlas source
		
#func _physics_process(delta):
	## position/cast_to already settled at start of frame
	## engine ran the cast for you
	#if $RayCast2D.is_colliding():
		#print("Hit this frame!")
		
func get_clicked_tile_power(tilemap, attribute):
	var clicked_cell = tilemap.local_to_map(tilemap.get_local_mouse_position())
	var data = tilemap.get_cell_tile_data(clicked_cell)
	print(get_cell_data(clicked_cell))
	if data:
		return data.get_custom_data(attribute)
	else:
		return null

#func _process(delta: float) -> void:
	#get_clicked_tile_power($TileMapLayer3 ,"elevation")
	#get_clicked_tile_power($TileMapLayer4 ,"cover")

var previous_mouse_pos: Vector2 =Vector2(0,0)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var mouse_pos: Vector2 = get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var space = get_world_2d().direct_space_state
		
		var query = PhysicsRayQueryParameters2D.create(previous_mouse_pos, mouse_pos, 1)
		var result = space.intersect_ray(query)
		if result != {}:
			print(result)
		#else:
			#print("l")

	previous_mouse_pos = mouse_pos
