extends Node2D

#@onready var listener: AudioListener2D = $Camera2D/AudioListener2D
@onready var src_left: AudioStreamPlayer2D = $SrcLeft
@onready var src_right: AudioStreamPlayer2D = $SrcRight

func _ready() -> void:
	#if listener != null:
		#listener.make_current()

	# Ensure clean settings
	_configure(src_left)
	_configure(src_right)

	# Put one source left, one right of listener
	$SrcLeft.position = Vector2(-300.0, 0.0)
	$SrcRight.position = Vector2(300.0, 0.0)
	#test_clicks()

func _configure(p: AudioStreamPlayer2D) -> void:
	p.bus = "Master"            # move to your SFX bus after testing
	p.attenuation = 1.0
	p.max_distance = 2000.0
	#p.unit_size = 1.0
	p.panning_strength = 1.0

func test_clicks() -> void:
	# Play short mono clicks to verify panning
	src_left.play()
	await get_tree().create_timer(0.4).timeout
	src_right.play()
