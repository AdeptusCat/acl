@tool
class_name BuildingTileMapLayer
extends HexagonTileMapLayer

const EMPTY_CELL: Vector4i = Vector4i(-1, -1, -1, -1)

class Footprint:
	var key: String = ""
	var cells: Dictionary[Vector2i, Vector4i] = {}
	var seeds: Dictionary[Vector2i, Vector4i] = {}

var _previous_cells: Dictionary[Vector2i, Vector4i] = {}
var _previous_buildings: Dictionary[String, Footprint] = {}
var _synchronizing: bool = false
var _synchronization_queued: bool = false
var _previous_map_data: PackedByteArray = PackedByteArray()


func _enter_tree() -> void:
	super._enter_tree()
	changed.connect(_on_building_cells_changed)


func _exit_tree() -> void:
	changed.disconnect(_on_building_cells_changed)
	super._exit_tree()


func _ready() -> void:
	# Repair saved single-cell stamps before the map initializes terrain and LOS.
	synchronize_buildings()
	super._ready()


func _process(_delta: float) -> void:
	# Native cell edits do not reliably emit changed; also watch serialized cells.
	if tile_map_data != _previous_map_data:
		synchronize_buildings()


func place_multihex_building(anchor: Vector2i, design: String, orientation: int = 0) -> void:
	synchronize_buildings()
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(tile_set, design, orientation)
	assert(pattern != null, "Unknown multihex building design: " + design)
	set_pattern(anchor, pattern)
	synchronize_buildings()


func _on_building_cells_changed() -> void:
	if _synchronizing or _synchronization_queued:
		return
	# Native editor strokes and patterns can change several cells in one operation.
	_synchronization_queued = true
	synchronize_buildings.call_deferred()


func synchronize_buildings() -> void:
	_synchronization_queued = false
	if _synchronizing or tile_set == null:
		return
	_synchronizing = true
	var current: Dictionary[Vector2i, Vector4i] = _read_cells()
	var stamps: Dictionary[String, Footprint] = {}
	for cell: Vector2i in current:
		if current[cell] == _previous_cells.get(cell, EMPTY_CELL):
			continue
		var stamp: Footprint = _describe_building(cell, current[cell])
		if stamp == null:
			continue
		if not stamps.has(stamp.key):
			stamps[stamp.key] = stamp
		stamps[stamp.key].seeds[cell] = current[cell]
	# Erasing or replacing any member removes the remaining members of that building.
	for previous: Footprint in _previous_buildings.values():
		for cell: Vector2i in previous.cells:
			if current.get(cell, EMPTY_CELL) != previous.cells[cell]:
				_erase_building(previous)
				break
	var buildings: Dictionary[String, Footprint] = _collect_buildings(_read_cells())
	for stamp: Footprint in stamps.values():
		if not _has_seed(stamp):
			continue
		# Remove entire overlapping buildings, including cells outside the new stamp.
		for key: String in buildings.keys():
			if key != stamp.key and _overlaps(stamp, buildings[key]):
				_erase_building(buildings[key])
				buildings.erase(key)
		for cell: Vector2i in stamp.cells:
			var value: Vector4i = stamp.cells[cell]
			if _cell_value(cell) != value:
				set_cell(cell, value.x, Vector2i(value.y, value.z), value.w)
		buildings[stamp.key] = stamp
	_previous_cells = _read_cells()
	_previous_buildings = _collect_buildings(_previous_cells)
	_previous_map_data = tile_map_data
	_synchronizing = false


func get_building_cells(cell: Vector2i) -> Array[Vector2i]:
	var footprint: Footprint = _describe_building(cell, _cell_value(cell))
	if footprint == null:
		return [cell]
	return footprint.cells.keys()


func los_layout_signature() -> String:
	synchronize_buildings()
	if _previous_buildings.is_empty():
		return ""
	var cells: Array[Vector2i] = get_used_cells()
	cells.sort_custom(_cell_before)
	var layout: Array = [tile_set.tile_size, tile_set.tile_shape, tile_set.tile_layout, tile_set.tile_offset_axis]
	for cell: Vector2i in cells:
		var value: Vector4i = _cell_value(cell)
		var source: TileSetAtlasSource = tile_set.get_source(value.x) as TileSetAtlasSource
		var data: TileData = get_cell_tile_data(cell)
		layout.append([cell, value, source.texture.resource_path, data.texture_origin, data.get_custom_data("cover")])
	return JSON.stringify(layout).sha256_text()


func _read_cells() -> Dictionary[Vector2i, Vector4i]:
	var cells: Dictionary[Vector2i, Vector4i] = {}
	for cell: Vector2i in get_used_cells():
		cells[cell] = _cell_value(cell)
	return cells


func _cell_value(cell: Vector2i) -> Vector4i:
	var atlas: Vector2i = get_cell_atlas_coords(cell)
	return Vector4i(get_cell_source_id(cell), atlas.x, atlas.y, get_cell_alternative_tile(cell))


func _describe_building(cell: Vector2i, value: Vector4i) -> Footprint:
	if value.x < 0 or not tile_set.has_source(value.x):
		return null
	var data: TileData = get_cell_tile_data(cell)
	if data == null or not data.has_custom_data("building_hexes") or int(data.get_custom_data("building_hexes")) < 2:
		return null
	var source: TileSetAtlasSource = tile_set.get_source(value.x) as TileSetAtlasSource
	var center: Vector2 = map_to_local(cell) - Vector2(data.texture_origin)
	var footprint: Footprint = Footprint.new()
	footprint.key = "%d:%d:%d:%s" % [value.x, value.y, value.w, str(center)]
	for part: int in range(int(data.get_custom_data("building_hexes"))):
		var atlas: Vector2i = Vector2i(value.y, part)
		var part_data: TileData = source.get_tile_data(atlas, 0)
		# Pixel offsets preserve hex neighbors across even, odd and negative columns.
		var occupied: Vector2i = local_to_map(center + Vector2(part_data.texture_origin))
		footprint.cells[occupied] = Vector4i(value.x, atlas.x, atlas.y, value.w)
	return footprint


func _collect_buildings(cells: Dictionary[Vector2i, Vector4i]) -> Dictionary[String, Footprint]:
	var buildings: Dictionary[String, Footprint] = {}
	for cell: Vector2i in cells:
		var building: Footprint = _describe_building(cell, cells[cell])
		if building != null:
			buildings[building.key] = building
	return buildings


func _erase_building(building: Footprint) -> void:
	for cell: Vector2i in building.cells:
		if _cell_value(cell) == building.cells[cell]:
			erase_cell(cell)


func _has_seed(building: Footprint) -> bool:
	for cell: Vector2i in building.seeds:
		if _cell_value(cell) == building.seeds[cell]:
			return true
	return false


func _overlaps(first: Footprint, second: Footprint) -> bool:
	for cell: Vector2i in first.cells:
		if second.cells.has(cell):
			return true
	return false


static func _cell_before(first: Vector2i, second: Vector2i) -> bool:
	if first.x == second.x:
		return first.y < second.y
	return first.x < second.x
