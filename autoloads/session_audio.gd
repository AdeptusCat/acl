extends Node

const MASTER_BUS: String = "Master"
const MUSIC_BUS: String = "Music"

var master_db: float = 0.0
var master_linear: float = 1.0
var music_db: float = 0.0
var music_linear: float = 1.0
var updating_ui: bool = false

func _ready() -> void:
	var idx: int = AudioServer.get_bus_index(MASTER_BUS)
	master_db = AudioServer.get_bus_volume_db(idx)
	master_linear = db_to_linear(master_db)
	idx = AudioServer.get_bus_index(MUSIC_BUS)
	music_db = AudioServer.get_bus_volume_db(idx)
	music_linear = db_to_linear(music_db)

func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)

func linear_to_db(x: float) -> float:
	var clamped: float = clamp(x, 0.000001, 8.0) # avoid log(0)
	return 20.0 * log(clamped) / log(10.0)

func set_master_linear(x: float) -> void:
	master_linear = x
	master_db = linear_to_db(master_linear)
	var idx: int = AudioServer.get_bus_index(MASTER_BUS)
	AudioServer.set_bus_volume_db(idx, master_db)


func set_music_linear(x: float) -> void:
	music_linear = x
	music_db = linear_to_db(music_linear)
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	AudioServer.set_bus_volume_db(idx, music_db)


func sync_sliders(sliders: Array) -> void:
	updating_ui = true
	sliders[0].value = master_linear
	sliders[1].value = music_linear
	updating_ui = false
