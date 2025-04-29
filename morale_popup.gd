extends Node2D

@onready var anim = $AnimationPlayer
@onready var label = $PopupLabel

func start_success():
	label.text = "+OK"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_failure():
	label.text = "BROKEN"
	anim.play("popup")
	await anim.animation_finished
	queue_free()
