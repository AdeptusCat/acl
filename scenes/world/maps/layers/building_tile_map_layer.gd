@tool
class_name BuildingTileMapLayer
extends HexagonTileMapLayer


func place_multihex_building(anchor: Vector2i, design: String, orientation: int = 0) -> void:
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(tile_set, design, orientation)
	assert(pattern != null, "Unknown multihex building design: " + design)
	set_pattern(anchor, pattern)
