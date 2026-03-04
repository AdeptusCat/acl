extends Node
class_name SoldierTask

enum SoldierAction {
	SETUP_WEAPON,
	ACQUIRE_TARGET,
	RELOAD,
	FIRE_WEAPON,
	ASSIST,
	CLOSE_COMBAT,
}

var type: SoldierAction
var task_name: String = ""
var done: bool = false
var start_time_s: float = 0.0:
	set(value):
		start_time_s = value
		remaining_time_s = value
	get:
		return start_time_s
var remaining_time_s: float = 0.0
var target_id: Unit = null

func _init(t: SoldierAction) -> void: # , r: float, tid: Unit = null
	type = t
	match type:
		SoldierAction.SETUP_WEAPON:
			task_name = "Setting Up"
		SoldierAction.ACQUIRE_TARGET:
			task_name = "Engaging Target"
		SoldierAction.RELOAD:
			task_name = "Reloading"
		SoldierAction.FIRE_WEAPON:
			task_name = "Fire Weapon"
		SoldierAction.ASSIST:
			task_name = "Assisting"
		SoldierAction.CLOSE_COMBAT:
			task_name = "In Close Combat"
	#remaining_time_s = r
	#target_id = tid
	#done = false
