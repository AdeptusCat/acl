extends Node2D

@onready var anim = $AnimationPlayer
@onready var sprite = $Sprite2D
@export var texture_success: Texture2D
@export var texture_failure: Texture2D

func start_success():
	sprite.texture = texture_success
	anim.play("flash")
	await anim.animation_finished
	queue_free()

func start_failure():
	sprite.texture = texture_failure
	anim.play("flash")
	await anim.animation_finished
	queue_free()
