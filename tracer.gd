# Tracer.gd
extends Node2D

@export var speed := 1200.0          # pixels/sec
@export var tracer_texture: Texture2D
@onready var particles: CPUParticles2D = $CPUParticles2D

func _ready():
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
	
	


func shoot(from: Vector2, to: Vector2) -> void:
	
	# position & aim the entire Node2D so its local +X points at target:
	global_position  = from
	global_rotation  = (to - from).angle()
	var ang = (to - from).angle()
	particles.angle_min = -rad_to_deg(ang)
	particles.angle_max = -rad_to_deg(ang)
	var dist = from.distance_to(to)
	var life = dist / speed      # seconds
	particles.lifetime = life
	# restart & fire the one–shot particle
	particles.restart()
	particles.emitting = true

	# queue_free when it’s done
	await get_tree().create_timer(particles.lifetime).timeout
	queue_free()
