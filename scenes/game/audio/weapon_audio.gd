# WeaponAudio.gd
extends Node2D
class_name WeaponAudio

var audio_pool: AudioPool
@export var reverb_bus: String = "ReverbSend"
@export var snd_shot_default: AudioStream = null   
@export var snd_mg_loop_default: AudioStream = null   
@export var snd_mg_loop_decay_default: AudioStream = null   

var _mg_loops: Dictionary = {}         # owner_id:int -> AudioStreamPlayer2D
var _active: bool = true

func _enter_tree() -> void:
	var unit: Unit = get_parent() as Unit
	_active = is_instance_valid(unit) and unit.alive

func _ready() -> void:
	audio_pool = get_node("/root/Main/World/AudioPool") as AudioPool

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	_active = false
	for loop_player: Variant in _mg_loops.values():
		if is_instance_valid(loop_player):
			var player: AudioStreamPlayer2D = loop_player as AudioStreamPlayer2D
			player.stop()
			player.queue_free()
	_mg_loops.clear()

func _rand_pitch() -> float:
	# small random pitch variation
	var delta: float = (randf() - 0.5) * 0.06
	return 1.0 + delta

func play_shot(weapon_spec: WeaponSpec, _position: Vector2, is_distant: bool = false) -> void:
	if not _active:
		return
	#return
	if is_distant:
		if weapon_spec.snd_distant != null:
			var p: float = _rand_pitch()
			audio_pool.play_one_shot(weapon_spec.snd_distant, _position, -6.0, p, "SFX_Distant")
			return
	var shot: AudioStream = snd_shot_default
	var volume: float = weapon_spec.volume_db
	if weapon_spec.can_fire_riflegrenades and weapon_spec.riflegrenade_loaded:
		if weapon_spec.riflegrenade_shot != null:
			shot = weapon_spec.riflegrenade_shot
			volume = weapon_spec.riflegrenade_shot_volume_db
	elif weapon_spec.snd_shot != null:
		shot = weapon_spec.snd_shot
	audio_pool.play_one_shot(shot, _position, volume, _rand_pitch(), "SFX_Close")
	# mechanical click
	if weapon_spec.snd_mech != null:
		audio_pool.play_one_shot(weapon_spec.snd_mech, _position, -2.0, 1.0, "SFX_Close")

func play_shot_decay(weapon_spec: WeaponSpec, _position: Vector2, _is_distant: bool = false) -> void:
	if not _active:
		return
	#if is_distant:
		#if weapon_spec.snd_distant != null:
			#var p: float = _rand_pitch()
			#audio_pool.play_one_shot(weapon_spec.snd_distant, position, -6.0, p, "SFX_Distant")
			#return
	var decay: AudioStream = snd_mg_loop_decay_default
	if weapon_spec.snd_mg_loop_decay != null:
		decay = weapon_spec.snd_mg_loop_decay
	audio_pool.play_one_shot(decay, _position, weapon_spec.decay_volume_db, _rand_pitch(), "SFX_Close")


# For MG start/stop looped sound: keep a node per firing source
func start_mg_loop(owner_id: int, weapon_spec: WeaponSpec, position_node: Node2D) -> void:
	if not _active:
		return
	var existing: Variant = _mg_loops.get(owner_id, null)
	if is_instance_valid(existing):
		var current: AudioStreamPlayer2D = existing as AudioStreamPlayer2D
		if current.playing:
			return
		current.queue_free()
	_mg_loops.erase(owner_id)

	var ap: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	if weapon_spec.snd_mg_loop == null:
		ap.stream = snd_mg_loop_default
	else:
		ap.stream = weapon_spec.snd_mg_loop
	ap.bus = "SFX_Close"
	ap.autoplay = false
	position_node.add_child(ap)
	# The loop is already a child of the firing unit; applying its position again
	# moves the sound away from the weapon and changes distance attenuation.
	ap.position = Vector2.ZERO
	ap.volume_db = weapon_spec.volume_db
	ap.play()
	ap.name = "mg_loop_%s" % str(owner_id)
	_mg_loops[owner_id] = ap
	
	# watchdog: kill if somehow not stopped within N seconds
	var t: SceneTreeTimer = get_tree().create_timer(6.0)
	await t.timeout
	if is_instance_valid(ap) and is_instance_valid(position_node) and _mg_loops.get(owner_id, null) == ap:
		if ap.playing:
			stop_mg_loop(weapon_spec, position_node.position, owner_id, position_node)
			
	## watchdog: kill if somehow not stopped within N seconds
	#var timer: SceneTreeTimer = get_tree().create_timer(6.0)
	#timer.timeout.connect(func() -> void:
		#if is_instance_valid(ap):
			#if ap.playing:
				#stop_mg_loop(weapon_spec, position_node.position, owner_id, position_node)
	#)


func stop_mg_loop(weapon_spec: WeaponSpec, _position: Vector2, owner_id: int, _position_node: Node2D) -> void:
	var existing: Variant = _mg_loops.get(owner_id, null)
	_mg_loops.erase(owner_id)
	if not is_instance_valid(existing):
		return
	var ap: AudioStreamPlayer2D = existing as AudioStreamPlayer2D
	ap.stop()
	ap.queue_free()
	play_shot_decay(weapon_spec, _position)
