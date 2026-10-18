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
	var hud_scale: float = DisplaySettings.get_hud_scale()
	layer.scale = Vector2.ONE * hud_scale
	position = Vector2.ZERO
	size = get_viewport_rect().size / hud_scale
