extends Node

var mission_time: float = 0

signal command_view_changed(enabled: bool)

# Selected relationships remain visible when the full command view is off.
var showCmdConnectivity: bool = false:
	set(value):
		if showCmdConnectivity == value:
			return
		showCmdConnectivity = value
		command_view_changed.emit(value)
