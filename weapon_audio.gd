# WeaponAudio.gd
extends Node2D
class_name WeaponAudio

var audio_pool: AudioPool
@export var reverb_bus: String = "ReverbSend"
@export var snd_shot_default: AudioStream = null   
@export var snd_mg_loop_default: AudioStream = null   
@export var snd_mg_loop_decay_default: AudioStream = null   

var _mg_loops: Dictionary = {}         # owner_id:int -> AudioStreamPlayer2D

func _ready() -> void:
	audio_pool = get_node("/root/Main/World/AudioPool") as AudioPool

func _rand_pitch() -> float:
	# small random pitch variation
	var delta: float = (randf() - 0.5) * 0.06
	return 1.0 + delta

func play_shot(weapon_spec: WeaponSpec, position: Vector2, is_distant: bool = false) -> void:
	#return
	if is_distant:
		if weapon_spec.snd_distant != null:
			var p: float = _rand_pitch()
			audio_pool.play_one_shot(weapon_spec.snd_distant, position, -6.0, p, "SFX_Distant")
			return
	# close shot
	if weapon_spec.can_fire_riflegrenades:
		if weapon_spec.riflegrenade_shot != null:
			var p2: float = _rand_pitch()
			audio_pool.play_one_shot(weapon_spec.riflegrenade_shot, position, 6.0, p2, "SFX_Close")
		else:
			var p2: float = _rand_pitch()
			audio_pool.play_one_shot(snd_shot_default, position, -6.0, p2, "SFX_Close")
	else:
		if weapon_spec.snd_shot != null:
			var p2: float = _rand_pitch()
			audio_pool.play_one_shot(weapon_spec.snd_shot, position, -6.0, p2, "SFX_Close")
		else:
			var p2: float = _rand_pitch()
			audio_pool.play_one_shot(snd_shot_default, position, -6.0, p2, "SFX_Close")
	# mechanical click
	if weapon_spec.snd_mech != null:
		audio_pool.play_one_shot(weapon_spec.snd_mech, position, -2.0, 1.0, "SFX_Close")

func play_shot_decay(weapon_spec: WeaponSpec, position: Vector2, is_distant: bool = false) -> void:
	#if is_distant:
		#if weapon_spec.snd_distant != null:
			#var p: float = _rand_pitch()
			#audio_pool.play_one_shot(weapon_spec.snd_distant, position, -6.0, p, "SFX_Distant")
			#return
	# close shot
	if weapon_spec.snd_mg_loop_decay != null:
		var p2: float = _rand_pitch()
		audio_pool.play_one_shot(weapon_spec.snd_mg_loop_decay, position, 0.0, p2, "SFX_Close")
	else:
		var p2: float = _rand_pitch()
		audio_pool.play_one_shot(snd_mg_loop_decay_default, position, 0.0, p2, "SFX_Close")


# For MG start/stop looped sound: keep a node per firing source
func start_mg_loop(owner_id: int, weapon_spec: WeaponSpec, position_node: Node2D) -> void:
	var existing: Node = get_node_or_null("mg_loop_%s" % str(owner_id))
	
	if _mg_loops.has(owner_id):
		_mg_loops[owner_id].stop()
		_mg_loops[owner_id].queue_free()
	
	if existing != null:
		return
	
	var ap: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	if weapon_spec.snd_mg_loop == null:
		ap.stream = snd_mg_loop_default
	else:
		ap.stream = weapon_spec.snd_mg_loop
	ap.bus = "SFX_Close"
	ap.autoplay = false
	position_node.add_child(ap)
	ap.position = position_node.position
	ap.volume_db = weapon_spec.volume_db
	ap.play()
	ap.name = "mg_loop_%s" % str(owner_id)
	_mg_loops[owner_id] = ap
	
	# watchdog: kill if somehow not stopped within N seconds
	var t: SceneTreeTimer = get_tree().create_timer(6.0)
	await t.timeout
	if is_instance_valid(ap):
		if ap.playing:
			stop_mg_loop(weapon_spec, position_node.position, owner_id, position_node)
			
	## watchdog: kill if somehow not stopped within N seconds
	#var timer: SceneTreeTimer = get_tree().create_timer(6.0)
	#timer.timeout.connect(func() -> void:
		#if is_instance_valid(ap):
			#if ap.playing:
				#stop_mg_loop(weapon_spec, position_node.position, owner_id, position_node)
	#)


func stop_mg_loop(weapon_spec: WeaponSpec, position: Vector2, owner_id: int, position_node: Node2D) -> void:
	var ap: AudioStreamPlayer2D = _mg_loops.get(owner_id, null) as AudioStreamPlayer2D
	if ap != null and is_instance_valid(ap):
		ap.stop()
		ap.queue_free()
	_mg_loops.erase(owner_id)
	play_shot_decay(weapon_spec, position)
