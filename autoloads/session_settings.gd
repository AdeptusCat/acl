extends Node

var mission_time: float = 0

signal command_view_changed(enabled: bool)
signal log_capture_changed(enabled: bool)

var preferences_path: String = "user://settings.cfg"
var capture_logs: bool = false:
	set(value):
		if capture_logs == value:
			return
		capture_logs = value
		save_preferences()
		log_capture_changed.emit(value)

# Selected relationships remain visible when the full command view is off.
var showCmdConnectivity: bool = false:
	set(value):
		if showCmdConnectivity == value:
			return
		showCmdConnectivity = value
		command_view_changed.emit(value)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Headless regressions must not read or overwrite player preferences.
	if DisplayServer.get_name() == "headless":
		preferences_path = ""
	else:
		load_preferences()


func load_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(preferences_path) != OK:
		return
	var saved: Variant = config.get_value("logging", "capture_logs", false)
	if saved is bool:
		capture_logs = saved
	else:
		capture_logs = false


func save_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("logging", "capture_logs", capture_logs)
	var error: Error = config.save(preferences_path)
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))
