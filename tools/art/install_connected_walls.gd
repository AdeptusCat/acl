extends Node


func _ready() -> void:
	var tiles: TileSet = load(ConnectedWalls.TILE_SET_PATH) as TileSet
	ConnectedWalls.install(tiles)
	assert(ResourceSaver.save(tiles, ConnectedWalls.TILE_SET_PATH) == OK)
	print("Installed 63 stone-wall and 63 hedge tiles along hex edges.")
	get_tree().quit()
