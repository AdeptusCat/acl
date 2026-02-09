extends Node
class_name SoldierTask

enum SoldierAction {
	SETUP_WEAPON,
	ACQUIRE_TARGET,
	RELOAD,
	FIRE_WEAPON
}

var type: SoldierAction
var done: bool = false
var remaining_time_s: float = 0.0
var target_id: Unit = null

func _init(t: SoldierAction) -> void: # , r: float, tid: Unit = null
	type = t
	#remaining_time_s = r
	#target_id = tid
	#done = false
