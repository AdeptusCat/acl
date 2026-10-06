extends Node2D

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $PopupLabel

func start_success() -> void:
	$PopupLabel.show()
	$TextureRect.hide()
	label.text = "+OK"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_broken() -> void:
	$PopupLabel.show()
	$TextureRect.hide()
	label.text = "BROKEN"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_pinned() -> void:
	$PopupLabel.show()
	$TextureRect.hide()
	label.text = "PINNED"
	anim.play("popup")
	await anim.animation_finished
	queue_free()

func start_casualty() -> void:
	$PopupLabel.hide()
	$TextureRect.show()
	anim.play("popup")
	await anim.animation_finished
	queue_free()
