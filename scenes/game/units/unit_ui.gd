@tool
extends Node2D

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D
@export var morale_popup_scene: PackedScene
@export var morale_flash_scene: PackedScene
@export var tracer_scene: PackedScene
@export var tracer_texture: Texture
@export var cover_icon_scene: PackedScene

# === Nodes ===
@onready var sprite_node: Sprite2D = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar
@onready var cover_label = $CoverLabel
@onready var cover_container = $Cover
@onready var broken_label = $BrokenLabel
@onready var unit_selected_sprite = $UnitSelectedSprite
@onready var unit_status_control = $UnitStatus
@onready var broken_texture_rect = $UnitStatus/Broken
@onready var moving_texture_rect = $UnitStatus/Moving
@onready var shooting_texture_rect = $UnitStatus/Shooting
@onready var pinned_texture_rect = $UnitStatus/Pinned
@onready var idle_texture_rect = $UnitStatus/Idle

func select():
	unit_selected_sprite.visible = true


func deselect():
	unit_selected_sprite.visible = false


func update_team_sprite(team : int):
	if not sprite_node:
		return
	match team:
		0:
			sprite_node.texture = sprite_team_0
		1:
			sprite_node.texture = sprite_team_1


func set_cover(cover_value: int) -> void:
	for child in cover_container.get_children():
		child.queue_free()
	for cover in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)


func _on_unit_arrived_at_hex(hex):
	pass


func _on_started_moving():
	for child in unit_status_control.get_children():
		child.visible = false
	moving_texture_rect.visible = true


func _on_stopped_moving():
	for child in unit_status_control.get_children():
		child.visible = false
	if get_parent().broken == true:
		broken_texture_rect.visible = true
	else:
		idle_texture_rect.visible = true


func _on_morale_breaks():
	#broken_label.visible = true
	show_failure()
	for child in unit_status_control.get_children():
		child.visible = false
	broken_texture_rect.visible = true


func _on_morale_recovered():
	#broken_label.visible = false
	show_success()
	for child in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true


func _on_morale_updated(current, max):
	update_bar(current, max)


func _on_morale_failure():
	show_failure()


func _on_morale_success():
	show_success()


func update_bar(current: int, max: int):
	if morale_bar:
		var ratio = clamp(float(current) / float(max), 0.0, 1.0)
		morale_bar.scale.x = ratio

		if ratio < 0.5:
			morale_bar.color = Color(0, 1, 0)
		elif ratio < 0.8:
			morale_bar.color = Color(1, 1, 0)
		else:
			morale_bar.color = Color(1, 0, 0)


func _on_cover_updated(cover_value: int) -> void:
	for child in cover_container.get_children():
		child.queue_free()
	for cover in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)


func show_failure():
	_spawn_popup("failure")
	_spawn_flash("failure")


func show_success():
	update_bar(0, 100)
	_spawn_popup("success")
	_spawn_flash("success")


func _spawn_popup(type: String):
	var popup = morale_popup_scene.instantiate()
	add_child(popup)
	popup.position = position + Vector2(0, -20)
	if type == "failure":
		popup.start_failure()
	else:
		popup.start_success()



func _spawn_flash(type: String):
	var flash = morale_flash_scene.instantiate()
	add_child(flash)
	flash.position = position
	if type == "failure":
		flash.start_failure()
	else:
		flash.start_success()


func shoot(from_pos: Vector2, to_pos):
	var tracer = tracer_scene.instantiate() as Node2D
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot(from_pos, to_pos)
	for child in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true


func die():
	var tween = create_tween()
	tween.tween_property(sprite_node.material, "shader_parameter/dissolve_amount", 1.0, 0.6)
	await tween.finished
