@tool
extends EditorPlugin

var exporter: EditorExportPlugin = preload("res://addons/faction_resource_compatibility/export_plugin.gd").new()


func _enter_tree() -> void:
	add_export_plugin(exporter)


func _exit_tree() -> void:
	remove_export_plugin(exporter)
