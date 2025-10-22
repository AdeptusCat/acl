# Tracer.gd
extends Node2D

@export var speed := 600.0          # pixels/sec
@export var tracer_texture: Texture2D
@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var explosion_particles: CPUParticles2D = $CPUParticles2D2

var audio_pool: AudioPool

func _ready() -> void:
	audio_pool = get_node("/root/Main/World/AudioPool") as AudioPool
	# 1) assign your 16×3 PNG
	particles.texture = tracer_texture

	# 2) emit a single particle, no spread, no gravity
	particles.emission_shape         = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 20
	particles.amount                 = 1
	particles.one_shot               = true
	particles.initial_velocity_min   = speed
	particles.initial_velocity_max   = speed
	particles.spread                 = 0.0
	particles.gravity                = Vector2.ZERO

	# 3) always emit along +X in LOCAL space
	particles.direction              = Vector2(1, 0)

	# start off not emitting
	particles.emitting               = false
	
	


func shoot(from: Vector2, to: Vector2, weapon_spec: WeaponSpec, rilflegrenade: bool = false) -> void:
	if rilflegrenade:
		particles.modulate = Color(0.285, 0.107, 0.06, 1.0)
	# position & aim the entire Node2D so its local +X points at target:
	global_position  = from
	global_rotation  = (to - from).angle()
	var ang = (to - from).angle()
	particles.angle_min = -rad_to_deg(ang)
	particles.angle_max = -rad_to_deg(ang)
	var dist = from.distance_to(to)
	var life = dist / speed      # seconds
	if life <= 0:
		return
	particles.lifetime = life
	# restart & fire the one–shot particle
	particles.restart()
	particles.emitting = true

	# queue_free when it’s done
	await get_tree().create_timer(particles.lifetime).timeout
	
	if rilflegrenade:
		if weapon_spec.riflegrenade_hit != null:
			var p2: float = _rand_pitch()
			audio_pool.play_one_shot(weapon_spec.riflegrenade_hit, position, 6.0, p2, "SFX_Close")
		#var end_pos: Vector2 = predict_end_position(from, to, speed, particles.lifetime)
		var v: Vector2 = Vector2(
		randf_range(-16.0, 16.0),
		randf_range(-16.0, 16.0)
		)
		explosion_particles.global_position = to + v
		explosion_particles.emitting = true
		await get_tree().create_timer(explosion_particles.lifetime).timeout
	queue_free()

func _rand_pitch() -> float:
	# small random pitch variation
	var delta: float = (randf() - 0.5) * 0.06
	return 1.0 + delta

static func predict_end_position(
	from: Vector2,
	to: Vector2,
	_speed: float,
	lifetime: float
) -> Vector2:
	var dir: Vector2 = (to - from).normalized()
	var v0: Vector2 = dir * _speed
	var t: float = lifetime
	var p_local: Vector2 = v0 * t 

	return from + p_local
