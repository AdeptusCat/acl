extends Node

signal ui_scale_changed(value: float)
signal settings_changed

const DESIGN_SIZE: Vector2i = Vector2i(1280, 720)
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5]
const WINDOW_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1920, 1200),
	Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(3440, 1440),
]

var ui_scale: float = 1.0
var windowed_size: Vector2i = DESIGN_SIZE
var window_mode: Window.Mode = Window.MODE_WINDOWED
var preferences_path: String = "user://display.cfg"
var _resize_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resize_timer = Timer.new()
	_resize_timer.one_shot = true
	_resize_timer.wait_time = 0.3
	add_child(_resize_timer)
	_resize_timer.timeout.connect(_remember_window_size)
	get_window().min_size = DESIGN_SIZE
	get_window().unresizable = false
	# Regression runs must not read or overwrite the player's preferences.
	if DisplayServer.get_name() == "headless":
		preferences_path = ""
	else:
		load_preferences()
		_apply_window()
	get_window().size_changed.connect(_on_window_resized)
	get_window().close_requested.connect(_remember_window_size)


func set_ui_scale(value: float) -> void:
	if not UI_SCALES.has(value) or is_equal_approx(ui_scale, value):
		return
	ui_scale = value
	ui_scale_changed.emit(ui_scale)
	settings_changed.emit()
	save_preferences()


func set_window_mode(value: Window.Mode) -> void:
	if value != Window.MODE_WINDOWED and value != Window.MODE_FULLSCREEN:
		return
	if window_mode == value:
		return
	if get_window().mode == Window.MODE_WINDOWED:
		windowed_size = get_window().size.max(DESIGN_SIZE)
	window_mode = value
	_apply_window()
	settings_changed.emit()
	save_preferences()


func set_windowed_size(value: Vector2i) -> void:
	windowed_size = value.max(DESIGN_SIZE)
	if window_mode == Window.MODE_WINDOWED:
		_apply_window()
	settings_changed.emit()
	save_preferences()


func _apply_window() -> void:
	var window: Window = get_window()
	window.mode = window_mode
	if window_mode == Window.MODE_WINDOWED:
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		var target: Vector2i = windowed_size
		if usable.has_area():
			target = target.min(usable.size).max(DESIGN_SIZE)
		window.size = target
		windowed_size = target
		if usable.has_area():
			window.position = usable.position + (usable.size - target) / 2
	# Fullscreen uses the desktop video mode; never apply a window preset to it.


func _on_window_resized() -> void:
	_resize_timer.start()


func _remember_window_size() -> void:
	if get_window().mode != Window.MODE_WINDOWED or window_mode != Window.MODE_WINDOWED:
		return
	windowed_size = get_window().size.max(DESIGN_SIZE)
	settings_changed.emit()
	save_preferences()


func load_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(preferences_path) != OK:
		return
	var saved_scale: Variant = config.get_value("display", "ui_scale", 1.0)
	if (saved_scale is float or saved_scale is int) and UI_SCALES.has(float(saved_scale)):
		ui_scale = float(saved_scale)
	var saved_size: Variant = config.get_value("display", "windowed_size", DESIGN_SIZE)
	if saved_size is Vector2i:
		windowed_size = saved_size.max(DESIGN_SIZE)
	var saved_mode: Variant = config.get_value("display", "fullscreen", false)
	window_mode = Window.MODE_WINDOWED
	if saved_mode is bool and saved_mode:
		window_mode = Window.MODE_FULLSCREEN
	ui_scale_changed.emit(ui_scale)
	settings_changed.emit()


func save_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("display", "windowed_size", windowed_size)
	config.set_value("display", "fullscreen", window_mode == Window.MODE_FULLSCREEN)
	var error: Error = config.save(preferences_path)
	if error != OK:
		push_warning("Could not save display preferences: %s" % error_string(error))
