@tool
extends EditorPlugin

const INSPECTOR: Script = preload("res://addons/offboard_battery_picker/inspector.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector = INSPECTOR.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	_inspector = null
