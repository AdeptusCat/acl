@tool
class_name WallTileMapLayer
extends HexagonTileMapLayer


func paint_edges(cells: Array[Vector2i], kind: int, mask: int) -> void:
	assert(kind >= 0 and kind < 2, "Barrier kind must be stone (0) or hedge (1)")
	assert(mask > 0 and mask < 64, "A barrier must occupy at least one hex edge")
	var source: int = ConnectedWalls.source_for(tile_set, kind)
	assert(source >= 0, "The wall layer requires the shared connected-wall tileset")
	for cell: Vector2i in cells:
		set_cell(cell, source, ConnectedWalls.atlas_coords(mask), 0)


func edit_edge(cell: Vector2i, side: int, kind: int, erase: bool = false) -> void:
	assert(side >= 0 and side < 6, "Hex edge must be 0 through 5")
	var mask: int = get_edge_mask(cell)
	if erase:
		if not mask & (1 << side):
			return
		mask &= ~(1 << side)
		if mask == 0:
			erase_cell(cell)
			return
		var current: TileSetAtlasSource = tile_set.get_source(get_cell_source_id(cell)) as TileSetAtlasSource
		kind = 0
		if "hedge" in current.texture.resource_path:
			kind = 1
	else:
		mask |= 1 << side
	paint_edges([cell], kind, mask)


func get_edge_mask(cell: Vector2i) -> int:
	var data: TileData = get_cell_tile_data(cell)
	var mask: int = ConnectedWalls.edge_mask(data)
	var id: int = get_cell_source_id(cell)
	if mask != 0 or id < 0 or id >= ConnectedWalls.LEGACY_MASKS.size():
		return mask
	# Some old hedge sprites lack directional metadata; retain their visible sides
	# when the edge brush edits them, without changing untouched legacy cells.
	var physical: int = ConnectedWalls.LEGACY_MASKS[id]
	for side: int in range(6):
		if not physical & (1 << side):
			continue
		var transformed: int = side
		if data.flip_h:
			transformed = (6 - transformed) % 6
		if data.flip_v:
			transformed = posmod(3 - transformed, 6)
		mask |= 1 << transformed
	return mask


func los_layout_signature() -> String:
	var cells: Array[Vector2i] = get_used_cells()
	if cells.is_empty():
		return ""
	cells.sort()
	var layout: Array = [tile_set.tile_size, tile_set.tile_layout, tile_set.tile_offset_axis]
	for cell: Vector2i in cells:
		var data: TileData = get_cell_tile_data(cell)
		layout.append([cell, ConnectedWalls.edge_mask(data), data.get_custom_data("cover")])
	return JSON.stringify(layout).sha256_text()
