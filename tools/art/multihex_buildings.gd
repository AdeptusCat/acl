class_name MultihexBuildings
extends RefCounted

const DIRECTORY: String = "res://assets/tiles/buildings/multihex/"
const MANIFEST: String = "res://docs/art/multihex_buildings/export.json"
const ORIENTATION_COUNT: int = 6


static func catalog() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	return data["buildings"]


static func install(tiles: TileSet) -> void:
	_add_metadata(tiles)
	# Replace only our patterns, leaving any unrelated editor patterns intact.
	for index: int in range(tiles.get_patterns_count() - 1, -1, -1):
		if tiles.get_pattern(index).has_meta("multihex_building"):
			tiles.remove_pattern(index)
	for design: Dictionary in catalog():
		var source_id: int = _install_design(tiles, design)
		for orientation: int in range(ORIENTATION_COUNT):
			var pattern: TileMapPattern = TileMapPattern.new()
			var view: Dictionary = design["views"][orientation]
			for part: int in range(view["parts"].size()):
				var cell: Array = view["parts"][part]["cell"]
				pattern.set_cell(Vector2i(cell[0], cell[1]), source_id, Vector2i(orientation, part), 0)
			pattern.resource_name = str(design["label"]) + " - " + str(orientation * 60) + " degrees"
			pattern.set_meta("multihex_building", design["id"])
			pattern.set_meta("angle", orientation * 60)
			tiles.add_pattern(pattern)


static func pattern_for(tiles: TileSet, design: String, orientation: int) -> TileMapPattern:
	assert(orientation >= 0 and orientation < ORIENTATION_COUNT, "Building orientation must be 0 through 5")
	for index: int in range(tiles.get_patterns_count()):
		var pattern: TileMapPattern = tiles.get_pattern(index)
		if str(pattern.get_meta("multihex_building", "")) == design and int(pattern.get_meta("angle", -1)) == orientation * 60:
			return pattern
	return null


static func _add_metadata(tiles: TileSet) -> void:
	for entry: Array in [["building_id", TYPE_STRING], ["building_hexes", TYPE_INT], ["building_angle", TYPE_INT], ["building_part", TYPE_INT]]:
		if tiles.get_custom_data_layer_by_name(entry[0]) >= 0:
			continue
		var index: int = tiles.get_custom_data_layers_count()
		tiles.add_custom_data_layer()
		tiles.set_custom_data_layer_name(index, entry[0])
		tiles.set_custom_data_layer_type(index, entry[1])


static func _install_design(tiles: TileSet, design: Dictionary) -> int:
	var id: int = -1
	for index: int in range(tiles.get_source_count()):
		var candidate: int = tiles.get_source_id(index)
		var existing: TileSetAtlasSource = tiles.get_source(candidate) as TileSetAtlasSource
		if existing != null and existing.texture.resource_path == design["texture"]:
			id = candidate
			break
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = design["label"]
	source.texture = load(design["texture"]) as Texture2D
	var region: int = int(design["region_size"])
	source.texture_region_size = Vector2i(region, region)
	if id >= 0:
		source.resource_scene_unique_id = tiles.get_source(id).resource_scene_unique_id
		tiles.remove_source(id)
	id = tiles.add_source(source, id)
	var kind: String = "Stone Building"
	var cover: int = 3
	if design["material"] == "wood":
		kind = "Wood Building"
		cover = 2
	for orientation: int in range(ORIENTATION_COUNT):
		for part: int in range(int(design["hexes"])):
			var tile: Vector2i = Vector2i(orientation, part)
			source.create_tile(tile)
			var data: TileData = source.get_tile_data(tile, 0)
			var origin: Array = design["views"][orientation]["parts"][part]["texture_origin"]
			data.texture_origin = Vector2i(origin[0], origin[1])
			if part > 0:
				data.modulate = Color(1.0, 1.0, 1.0, 0.0)
			data.set_custom_data("name", kind)
			data.set_custom_data("cover", cover)
			data.set_custom_data("building_id", design["id"])
			data.set_custom_data("building_hexes", design["hexes"])
			data.set_custom_data("building_angle", orientation * 60)
			data.set_custom_data("building_part", part)
	return id
