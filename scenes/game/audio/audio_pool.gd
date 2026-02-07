# AudioPool.gd
extends Node2D
class_name AudioPool

@export var pool_size: int = 16
var pool: Array[AudioStreamPlayer2D] = []

func _ready() -> void:
	var i: int = 0
	while i < pool_size:
		var ap: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		ap.autoplay = false
		ap.stream_paused = true
		add_child(ap)
		pool.append(ap)
		i += 1

func _get_free_player() -> AudioStreamPlayer2D:
	for ap in pool:
		if not ap.playing:
			return ap
	# fallback: reuse first player (still safe)
	return pool[0]

func play_one_shot(stream: AudioStream, position: Vector2, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: String = "") -> void:
	var player: AudioStreamPlayer2D = _get_free_player()
	player.position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	if bus != "":
		player.bus = bus
	player.stream_paused = false
	player.play()
