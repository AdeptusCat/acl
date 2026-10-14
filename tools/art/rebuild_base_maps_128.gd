extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var path: String = "res://scenes/world/world.tscn"
	var resource_uid: int = ResourceLoader.get_resource_uid(path)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var world: Node = main.world
	world.fully_freed.disconnect(main._on_fully_freed)
	var maps: Array[Map] = []
	for map: Map in world.maps.get_children():
		if not map.campaign_name.is_empty():
			continue
		maps.append(map)
		if OS.get_cmdline_user_args().has("--los-only"):
			continue
		ConnectedTerrainBaker.bake(map.get_terrain_layer(), map.map_name.to_snake_case() + "_terrain")
		ConnectedTerrainBaker.bake(map.get_building_layer(), map.map_name.to_snake_case() + "_woods")
	if not OS.get_cmdline_user_args().has("--los-only"):
		var packed: PackedScene = PackedScene.new()
		assert(packed.pack(world) == OK)
		assert(ResourceSaver.save(packed, path) == OK)
		assert(ResourceSaver.set_uid(path, resource_uid) == OK)
	if OS.get_cmdline_user_args().has("--art-only"):
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	for map: Map in maps:
		print("Baking base map LOS: ", map.map_name)
		LOSHelper.bake_and_save_los_data(map)
		await get_tree().process_frame
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
