extends Node2D

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D
@export var morale_popup_scene: PackedScene
@export var morale_flash_scene: PackedScene
@export var tracer_scene: PackedScene
@export var tracer_texture: Texture

# === Nodes ===
@onready var sprite_node: Sprite2D = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar
@onready var cover_label = $CoverLabel
@onready var broken_label = $BrokenLabel
@onready var unit_selected_sprite = $UnitSelectedSprite


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
	if cover_value > 0:
		cover_label.text = str(cover_value)
		cover_label.show()
	else:
		cover_label.hide()


func _on_morale_breaks():
	broken_label.visible = true
	show_failure()


func _on_morale_recovered():
	broken_label.visible = false
	show_success()


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


func _on_cover_updated(value: int) -> void:
	if cover_label:
		cover_label.text = str(value)


func show_failure():
	_spawn_popup("failure")
	_spawn_flash("failure")


func show_success():
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
	tracer.shoot(from_pos, to_pos)



func die():
	var tween = create_tween()
	tween.tween_property(sprite_node.material, "shader_parameter/dissolve_amount", 1.0, 0.6)
	await tween.finished
