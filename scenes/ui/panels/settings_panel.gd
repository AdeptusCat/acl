extends Control

@export var show_command_view: bool = true

const SPEAKER_ICON: Texture2D = preload("res://assets/ui/hud/speaker.svg")
const MUTED_SPEAKER_ICON: Texture2D = preload("res://assets/ui/hud/speaker_muted.svg")

const CONTROL_HINTS: Dictionary[String, String] = {
	"Left click": "Select hex / cycle squads",
	"Roster row": "Select and center squad",
	"Hold right click": "Open the order wheel",
	"Release right click": "Issue the selected order",
	"Esc / left click": "Cancel an open command wheel",
	"WASD / arrows": "Move the camera",
	"Mouse wheel": "Zoom the battlefield",
	"Esc": "Close the open panel",
}

@onready var mute_button: Button = $Toolbar/MuteButton
@onready var settings_button: Button = $Toolbar/SettingsButton
@onready var controls_button: Button = $Toolbar/ControlsButton
@onready var command_view_button: Button = $Toolbar/CommandViewButton
@onready var menu: PanelContainer = $Menu
@onready var controls_panel: PanelContainer = $Controls
@onready var menu_scroll: ScrollContainer = $Menu/Scroll
@onready var controls_scroll: ScrollContainer = $Controls/Scroll
@onready var s1: HSlider = $Menu/Scroll/Content/VolumeSlider
@onready var s2: HSlider = $Menu/Scroll/Content/VolumeSlider2
@onready var master_label: Label = $Menu/Scroll/Content/MasterLabel
@onready var music_label: Label = $Menu/Scroll/Content/MusicLabel
@onready var command_links: CheckBox = $Menu/Scroll/Content/ShowCmdConnectivity
@onready var capture_logs: CheckBox = $Menu/Scroll/Content/CaptureLogs
@onready var control_rows: VBoxContainer = $Controls/Scroll/Content/Rows
@onready var mode_selector: OptionButton = $Menu/Scroll/Content/WindowMode
@onready var resolution_selector: OptionButton = $Menu/Scroll/Content/WindowSize
@onready var scale_label: Label = $Menu/Scroll/Content/ScaleLabel
@onready var scale_slider: HSlider = $Menu/Scroll/Content/UIScale
@onready var hud_control: Control = get_parent() as Control

var _scale_dragging: bool = false


func _ready() -> void:
	command_view_button.visible = show_command_view
	command_links.visible = show_command_view
	mute_button.toggled.connect(_on_mute_toggled)
	SessionAudio.master_mute_changed.connect(_on_master_mute_changed)
	_on_master_mute_changed(SessionAudio.master_muted)
	settings_button.toggled.connect(_on_settings_toggled)
	controls_button.toggled.connect(_on_controls_toggled)
	$Menu/Scroll/Content/Heading/Close.pressed.connect(close_panels)
	$Controls/Scroll/Content/Heading/Close.pressed.connect(close_panels)
	s1.value_changed.connect(_on_volume_slider_value_changed)
	s2.value_changed.connect(_on_volume_slider_2_value_changed)
	command_links.toggled.connect(_on_check_box_toggled)
	capture_logs.toggled.connect(_on_capture_logs_toggled)
	SessionSettings.log_capture_changed.connect(_sync_log_capture)
	_sync_log_capture(SessionSettings.capture_logs)
	command_view_button.toggled.connect(_on_check_box_toggled)
	SessionSettings.command_view_changed.connect(_sync_command_view)
	_sync_command_view(SessionSettings.showCmdConnectivity)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()
	_build_controls()
	_build_display_settings()
	menu.minimum_size_changed.connect(_queue_fit)
	controls_panel.minimum_size_changed.connect(_queue_fit)
	hud_control.resized.connect(_queue_fit)
	close_panels()
	_queue_fit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not menu.visible and not controls_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panels()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var open_panel: Control = menu
		if controls_panel.visible:
			open_panel = controls_panel
		var toolbar: Control = $Toolbar
		var toolbar_point: Vector2 = toolbar.get_global_transform_with_canvas().affine_inverse() * event.position
		var panel_point: Vector2 = open_panel.get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, toolbar.size).has_point(toolbar_point) and not Rect2(Vector2.ZERO, open_panel.size).has_point(panel_point):
			close_panels()


func close_panels() -> void:
	_scale_dragging = false
	_sync_ui_scale()
	menu.hide()
	controls_panel.hide()
	for selector: OptionButton in [mode_selector, resolution_selector]:
		selector.get_popup().hide()
	settings_button.set_pressed_no_signal(false)
	controls_button.set_pressed_no_signal(false)


func _on_mute_toggled(muted: bool) -> void:
	SessionAudio.set_master_muted(muted)


func _on_master_mute_changed(muted: bool) -> void:
	mute_button.set_pressed_no_signal(muted)
	mute_button.icon = SPEAKER_ICON
	mute_button.tooltip_text = "Mute sound"
	if muted:
		mute_button.icon = MUTED_SPEAKER_ICON
		mute_button.tooltip_text = "Unmute sound"


func _on_settings_toggled(open: bool) -> void:
	close_panels()
	if open:
		SessionAudio.sync_sliders([s1, s2])
		_update_volume_labels()
		command_links.set_pressed_no_signal(SessionSettings.showCmdConnectivity)
		menu.show()
		settings_button.set_pressed_no_signal(true)
		_queue_fit()


func _on_controls_toggled(open: bool) -> void:
	close_panels()
	if open:
		controls_panel.show()
		controls_button.set_pressed_no_signal(true)
		_queue_fit()


func _build_controls() -> void:
	for binding: String in CONTROL_HINTS:
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		control_rows.add_child(row)
		var key: Label = Label.new()
		key.custom_minimum_size.x = 164.0
		key.text = binding
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_theme_color_override("font_color", Color(0.86, 0.73, 0.5))
		row.add_child(key)
		var action: Label = Label.new()
		action.text = CONTROL_HINTS[binding]
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(action)


func _queue_fit() -> void:
	_fit_panels.call_deferred()


func _fit_panels() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	for panel: PanelContainer in [menu, controls_panel]:
		var width: float = 344.0
		var scroll: ScrollContainer = menu_scroll
		if panel == controls_panel:
			width = 452.0
			scroll = controls_scroll
		panel.custom_minimum_size.x = minf(width, hud_control.size.x - 24.0)
		var margins: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
		var content: Control = scroll.get_child(0) as Control
		var available_height: float = maxf(0.0, hud_control.size.y - position.y - size.y - 20.0 - margins.y)
		scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, minf(available_height, hud_control.size.y * 0.65))
		panel.size = Vector2(panel.custom_minimum_size.x, panel.get_combined_minimum_size().y)
		panel.position = Vector2(size.x - panel.size.x, size.y + 8.0)


func _build_display_settings() -> void:
	mode_selector.add_item("Windowed", Window.MODE_WINDOWED)
	mode_selector.add_item("Fullscreen", Window.MODE_FULLSCREEN)
	for preset: Vector2i in DisplaySettings.WINDOW_PRESETS:
		resolution_selector.add_item("%d × %d" % [preset.x, preset.y])
	resolution_selector.add_item("Custom window size")
	scale_slider.min_value = DisplaySettings.MIN_UI_SCALE * 100.0
	scale_slider.max_value = DisplaySettings.MAX_UI_SCALE * 100.0
	scale_slider.step = DisplaySettings.UI_SCALE_STEP * 100.0
	mode_selector.item_selected.connect(_on_window_mode_selected)
	resolution_selector.item_selected.connect(_on_window_size_selected)
	scale_slider.value_changed.connect(_on_ui_scale_value_changed)
	scale_slider.drag_started.connect(_on_ui_scale_drag_started)
	scale_slider.drag_ended.connect(_on_ui_scale_drag_ended)
	DisplaySettings.settings_changed.connect(_sync_display_settings)
	_sync_display_settings()


func _sync_display_settings() -> void:
	mode_selector.select(mode_selector.get_item_index(DisplaySettings.window_mode))
	var preset_index: int = DisplaySettings.WINDOW_PRESETS.find(DisplaySettings.windowed_size)
	if preset_index < 0:
		preset_index = DisplaySettings.WINDOW_PRESETS.size()
	resolution_selector.set_item_text(DisplaySettings.WINDOW_PRESETS.size(), "%d × %d (custom)" % [DisplaySettings.windowed_size.x, DisplaySettings.windowed_size.y])
	resolution_selector.set_item_disabled(DisplaySettings.WINDOW_PRESETS.size(), true)
	resolution_selector.select(preset_index)
	resolution_selector.disabled = OS.has_feature("web") or DisplaySettings.window_mode != Window.MODE_WINDOWED
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(get_window().current_screen)
	for index: int in range(DisplaySettings.WINDOW_PRESETS.size()):
		var preset: Vector2i = DisplaySettings.WINDOW_PRESETS[index]
		resolution_selector.set_item_disabled(index, usable.has_area() and (preset.x > usable.size.x or preset.y > usable.size.y))
	if not _scale_dragging:
		_sync_ui_scale()
	_queue_fit()


func _sync_ui_scale() -> void:
	scale_slider.set_value_no_signal(DisplaySettings.ui_scale * 100.0)
	scale_label.text = "Interface size · %d%%" % roundi(scale_slider.value)


func _on_window_mode_selected(index: int) -> void:
	DisplaySettings.set_window_mode(mode_selector.get_item_id(index) as Window.Mode)


func _on_window_size_selected(index: int) -> void:
	if index < DisplaySettings.WINDOW_PRESETS.size():
		DisplaySettings.set_windowed_size(DisplaySettings.WINDOW_PRESETS[index])


func _on_ui_scale_value_changed(value: float) -> void:
	scale_label.text = "Interface size · %d%%" % roundi(value)
	# Apply after mouse input starts a drag, so the HUD stays still until release.
	_apply_ui_scale.call_deferred()


func _apply_ui_scale() -> void:
	if not _scale_dragging:
		DisplaySettings.set_ui_scale(scale_slider.value / 100.0)


func _on_ui_scale_drag_started() -> void:
	_scale_dragging = true


func _on_ui_scale_drag_ended(_value_changed: bool) -> void:
	_scale_dragging = false
	_apply_ui_scale()


func _update_volume_labels() -> void:
	master_label.text = "Master volume · %d%%" % roundi(s1.value * 100.0)
	music_label.text = "Music volume · %d%%" % roundi(s2.value * 100.0)

func _on_volume_slider_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_master_linear(value)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()


func _on_volume_slider_2_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_music_linear(value)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()


func _on_check_box_toggled(toggled_on: bool) -> void:
	SessionSettings.showCmdConnectivity = toggled_on


func _sync_command_view(enabled: bool) -> void:
	command_links.set_pressed_no_signal(enabled)
	command_view_button.set_pressed_no_signal(enabled)


func _on_capture_logs_toggled(enabled: bool) -> void:
	SessionSettings.capture_logs = enabled


func _sync_log_capture(enabled: bool) -> void:
	capture_logs.set_pressed_no_signal(enabled)
