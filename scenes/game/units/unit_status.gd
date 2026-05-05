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

@export var idle_mg_ger: Texture2D
@export var shooting_mg_ger: Texture2D

@export var idle_antitank_ger: Texture2D
@export var shooting_antitank_ger: Texture2D

@export var idle_mortar_ger: Texture2D
@export var shooting_mortar_ger: Texture2D

@export var idle_mg_us: Texture2D
@export var shooting_mg_us: Texture2D

@export var idle_antitank_us: Texture2D
@export var shooting_antitank_us: Texture2D

@export var idle_mortar_us: Texture2D
@export var shooting_mortar_us: Texture2D

func set_status_image(team, _squad_type: Globals.SquadType):
	if team == 0:
		$Idle.texture = idle_ger
		$Moving.texture = moving_ger
		$Routing.texture = routing_ger
		$Shooting.texture = shooting_ger
		$Pinned.texture = pinned_ger
		$Broken.texture = broken_ger
		$Surrendered.texture = surrendered_ger
		match _squad_type:
			Globals.SquadType.MG:
				$Idle.texture = idle_mg_ger
				$Shooting.texture = shooting_mg_ger
			Globals.SquadType.ANTITANK:
				$Idle.texture = idle_antitank_ger
				$Shooting.texture = shooting_antitank_ger
			Globals.SquadType.MORTAR:
				$Idle.texture = idle_mortar_ger
				$Shooting.texture = shooting_mortar_ger
	if team == 1:
		$Idle.texture = idle_us
		$Moving.texture = moving_us
		$Routing.texture = routing_us
		$Shooting.texture = shooting_us
		$Pinned.texture = pinned_us
		$Broken.texture = broken_us
		$Surrendered.texture = surrendered_us
		match _squad_type:
			Globals.SquadType.MG:
				$Idle.texture = idle_mg_us
				$Shooting.texture = shooting_mg_us
			Globals.SquadType.ANTITANK:
				$Idle.texture = idle_antitank_us
				$Shooting.texture = shooting_antitank_us
			Globals.SquadType.MORTAR:
				$Idle.texture = idle_mortar_us
				$Shooting.texture = shooting_mortar_us
