extends Node

enum Tooltip {UNIT_TYPE, UNIT_STATUS, LEADERSHIP_BONUS, LOS_HINDRANCE, LOS_BLOCKED, LOS_WALL, COVER}

signal mouse_entered(tooltip: Tooltip)
signal mouse_exited
