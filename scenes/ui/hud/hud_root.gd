extends Control


func _ready() -> void:
	DisplaySettings.ui_scale_changed.connect(_on_ui_scale_changed)
	get_viewport().size_changed.connect(_fit_hud)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_hud()


func _on_ui_scale_changed(_value: float) -> void:
	_fit_hud()


func _fit_hud() -> void:
	var layer: CanvasLayer = get_parent() as CanvasLayer
	layer.scale = Vector2.ONE * DisplaySettings.ui_scale
	position = Vector2.ZERO
	size = get_viewport_rect().size / DisplaySettings.ui_scale
