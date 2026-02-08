extends PanelContainer

@onready var s1: Range = $FoldableContainer/VBoxContainer/VolumeSlider
@onready var s2: Range = $FoldableContainer/VBoxContainer/VolumeSlider2

func _ready() -> void:
	SessionAudio.sync_sliders([s1, s2])

func _on_volume_slider_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_master_linear(value)
	SessionAudio.sync_sliders([s1, s2])


func _on_volume_slider_2_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_music_linear(value)
	SessionAudio.sync_sliders([s1, s2])


func _on_foldable_container_folding_changed(_is_folded: bool) -> void:
	size.y = 0
