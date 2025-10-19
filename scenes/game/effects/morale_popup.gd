extends Node2D

@onready var anim = $AnimationPlayer
@onready var label = $PopupLabel

func start_success():
	$PopupLabel.show()
	$TextureRect.hide()
	label.text = "+OK"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_failure():
	$PopupLabel.show()
	$TextureRect.hide()
	label.text = "BROKEN"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_casualty():
	$PopupLabel.hide()
	$TextureRect.show()
	anim.play("popup")
	await anim.animation_finished
	queue_free()
