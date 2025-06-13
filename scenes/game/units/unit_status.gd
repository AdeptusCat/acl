extends Control

@export var idle_ger: Texture2D
@export var idle_us: Texture2D
@export var moving_ger: Texture2D
@export var moving_us: Texture2D
@export var shooting_ger: Texture2D
@export var shooting_us: Texture2D
@export var pinned_ger: Texture2D
@export var pinned_us: Texture2D
@export var broken_ger: Texture2D
@export var broken_us: Texture2D


func set_status_image(team):
	if team == 0:
		$Idle.texture = idle_ger
		$Moving.texture = moving_ger
		$Shooting.texture = shooting_ger
		$Pinned.texture = pinned_ger
		$Broken.texture = broken_ger
	if team == 1:
		$Idle.texture = idle_us
		$Moving.texture = moving_us
		$Shooting.texture = shooting_us
		$Pinned.texture = pinned_us
		$Broken.texture = broken_us
