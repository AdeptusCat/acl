@tool
extends Control

@export var idle_ger: Texture2D
@export var idle_leader_ger: Texture2D
@export var idle_us: Texture2D
@export var moving_ger: Texture2D
@export var moving_us: Texture2D
@export var routing_ger: Texture2D
@export var routing_us: Texture2D
@export var shooting_ger: Texture2D
@export var shooting_us: Texture2D
@export var pinned_ger: Texture2D
@export var pinned_us: Texture2D
@export var broken_ger: Texture2D
@export var broken_us: Texture2D
@export var surrendered_ger: Texture2D
@export var surrendered_us: Texture2D

func set_status_image(team, leader: bool = false):
	if team == 0:
		$Idle.texture = idle_ger
		$Moving.texture = moving_ger
		$Routing.texture = routing_ger
		$Shooting.texture = shooting_ger
		$Pinned.texture = pinned_ger
		$Broken.texture = broken_ger
		$Surrendered.texture = surrendered_ger
	if leader:
		$Idle.texture = idle_leader_ger
		$Moving.texture = idle_leader_ger
		$Routing.texture = idle_leader_ger
		$Shooting.texture = idle_leader_ger
		$Pinned.texture = idle_leader_ger
		$Broken.texture = idle_leader_ger
		$Surrendered.texture = idle_leader_ger
	if team == 1:
		$Idle.texture = idle_us
		$Moving.texture = moving_us
		$Routing.texture = routing_us
		$Shooting.texture = shooting_us
		$Pinned.texture = pinned_us
		$Broken.texture = broken_us
		$Surrendered.texture = surrendered_us
