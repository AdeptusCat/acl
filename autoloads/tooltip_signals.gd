extends Node

enum Tooltip {UNIT_TYPE, UNIT_STATUS, LEADERSHIP_BONUS}

signal mouse_entered(tooltip: Tooltip)
signal mouse_exited
