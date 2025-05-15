# UnitMoraleUI.gd
class_name UnitMoraleUI
extends Node

var unit: Node2D
var morale_bar: ColorRect
var broken_label: Label
var popup_scene: PackedScene
var flash_scene: PackedScene

func _init(_unit: Node2D):
	unit = _unit

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

func show_failure():
	_spawn_popup("failure")
	_spawn_flash("failure")

func show_success():
	_spawn_popup("success")
	_spawn_flash("success")

func set_broken_visible(visible: bool):
	if broken_label:
		broken_label.visible = visible

func _spawn_popup(type: String):
	var popup = popup_scene.instantiate()
	unit.get_parent().add_child(popup)
	popup.global_position = unit.global_position + Vector2(0, -20)
	if type == "failure":
		popup.start_failure()
	else:
		popup.start_success()

func _spawn_flash(type: String):
	var flash = flash_scene.instantiate()
	unit.get_parent().add_child(flash)
	flash.global_position = unit.global_position
	if type == "failure":
		flash.start_failure()
	else:
		flash.start_success()
