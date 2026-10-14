extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tiles: TileSet = load(BuildingVariations.SHARED_TILE_SET) as TileSet
	MultihexBuildings.install(tiles)
	assert(ResourceSaver.save(tiles, BuildingVariations.SHARED_TILE_SET) == OK)
	var count: int = MultihexBuildings.catalog().size()
	print("Installed ", count, " multihex designs and ", count * 6, " rotated patterns in the shared building layer.")
	get_tree().quit()
