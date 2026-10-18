extends Label


func _on_mouse_entered() -> void:
	TooltipSignals.mouse_entered.emit(TooltipSignals.Tooltip.UNIT_TYPE)


func _on_mouse_exited() -> void:
	TooltipSignals.mouse_exited.emit()
