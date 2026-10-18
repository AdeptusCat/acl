extends Node

const WORLD: String = "res://scenes/world/world.tscn"

var _used_sources: Dictionary[int, bool] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var shared: TileSet = load(BuildingVariations.SHARED_TILE_SET) as TileSet
	BuildingVariations.install(shared)
	var world: Node = load(WORLD).instantiate()
	for map: Map in world.get_node("Maps").get_children():
		_replace_layer(map, shared, map.map_name.to_snake_case())
	_save_scene(world, WORLD)
	for scene: PackedScene in world.ALDERBROOK_CAMPAIGN.mission_maps:
		var map: Map = scene.instantiate() as Map
		_replace_layer(map, shared, (map.get_node("Scenarios").get_child(0) as Scenario).scenario_id)
		_save_scene(map, scene.resource_path)
		map.free()
	var approach: Map = world.WESTERN_APPROACH.instantiate() as Map
	_replace_layer(approach, shared, (approach.get_node("Scenarios").get_child(0) as Scenario).scenario_id)
	_save_scene(approach, world.WESTERN_APPROACH.resource_path)
	approach.free()
	var obsolete: Array[int] = []
	for index: int in range(shared.get_source_count()):
		var id: int = shared.get_source_id(index)
		var source: TileSetAtlasSource = shared.get_source(id) as TileSetAtlasSource
		if _used_sources.has(id) or source.texture.resource_path.begins_with(BuildingVariations.DIRECTORY):
			continue
		if source.texture.resource_path.begins_with("res://assets/tiles/buildings/") and str(source.get_tile_data(source.get_tile_id(0), 0).get_custom_data("name")).is_empty():
			obsolete.append(id)
	for id: int in obsolete:
		shared.remove_source(id)
	assert(ResourceSaver.save(shared, BuildingVariations.SHARED_TILE_SET) == OK)
	world.free()
	print("All eight building layers now reuse one scene and one tileset.")
	get_tree().quit()


func _replace_layer(map: Map, shared: TileSet, identity: String) -> void:
	var original: HexagonTileMapLayer = map.get_node("TileMapLayers/BuildingTileMapLayer") as HexagonTileMapLayer
	var layer: HexagonTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as HexagonTileMapLayer
	layer.tile_set = original.tile_set
	layer.tile_map_data = original.tile_map_data
	BuildingVariations.use_shared(layer, shared)
	BuildingVariations.apply(layer, identity)
	var parent: Node = original.get_parent()
	var owner: Node = original.owner
	var index: int = original.get_index()
	layer.z_index = original.z_index
	layer.visible = original.visible
	layer.transform = original.transform
	layer.pathfinding_enabled = original.pathfinding_enabled
	for key: StringName in original.get_meta_list():
		layer.set_meta(key, original.get_meta(key))
	parent.remove_child(original)
	parent.add_child(layer)
	parent.move_child(layer, index)
	layer.owner = owner
	for cell: Vector2i in layer.get_used_cells():
		_used_sources[layer.get_cell_source_id(cell)] = true
	original.free()


func _save_scene(node: Node, path: String) -> void:
	var original: String = FileAccess.get_file_as_string(path)
	var uid: int = ResourceLoader.get_resource_uid(path)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	if uid >= 0:
		assert(ResourceSaver.set_uid(path, uid) == OK)
	# Keep authored non-building bytes and inherit the catalog from the layer scene.
	var headings: RegEx = RegEx.new()
	assert(headings.compile('^\\[node name="([^"]+)"[^\\n]* parent="([^"]+)"') == OK)
	var cells: Dictionary[String, String] = {}
	var key: String = ""
	for line: String in original.split("\n"):
		var heading: RegExMatch = headings.search(line)
		if heading != null:
			key = heading.get_string(2) + "/" + heading.get_string(1)
		if line.begins_with("tile_map_data = ") and not key.ends_with("/BuildingTileMapLayer"):
			cells[key] = line
	var lines: PackedStringArray = PackedStringArray()
	key = ""
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var heading: RegExMatch = headings.search(line)
		if heading != null:
			key = heading.get_string(2) + "/" + heading.get_string(1)
		if line.begins_with('[ext_resource type="TileSet"') and line.contains(BuildingVariations.SHARED_TILE_SET):
			continue
		if line.begins_with("tile_set = ") and key.ends_with("/BuildingTileMapLayer"):
			continue
		if line.begins_with("tile_map_data = ") and cells.has(key):
			line = cells[key]
		lines.append(line)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
