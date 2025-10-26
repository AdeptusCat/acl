extends Label


func _on_mouse_entered() -> void:
	TooltipSignals.mouse_entered.emit(TooltipSignals.Tooltip.LEADERSHIP_BONUS)


func _on_mouse_exited() -> void:
	TooltipSignals.mouse_exited.emit()
