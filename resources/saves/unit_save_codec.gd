extends RefCounted
class_name UnitSaveCodec

# Synchronous UnitSaveCodec operations; state and scene identity stay on the caller.


static func create_save_data(unit: Unit) -> UnitSaveData:
	var data: UnitSaveData = UnitSaveData.new()

	data.unit_scene_path = unit.scene_file_path
	data.team = unit.team
	data.casualty_records.assign(unit.casualty_records)

	data.soldiers.clear()
	
	var squad_loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	for soldier: Soldier in unit.squad_fire.soldiers:
		var soldier_data: SoldierLoadout = soldier.create_save_data()
		squad_loadout.soldiers.append(soldier_data)
	squad_loadout.squad_type = unit.squad_type
	squad_loadout.team = unit.team
	
	data.squad_loadout = squad_loadout
	
	#data.stress_fast = stress_controller.stress_fast
	#data.stress_slow = stress_controller.stress_slow
	#data.cohesion = cohesion
	#data.state = current_state

	return data


static func apply_save_data(unit: Unit, data: UnitSaveData) -> void:
	#id = data.unit_id
	unit.team = data.team

	unit.squad_fire.soldiers.clear()

	#for soldier_data: SoldierSaveData in data.soldiers:
		#var soldier: Soldier = Soldier.create_from_save_data(soldier_data, self, team)
	
	unit._setup_runtime_soldiers(data.squad_loadout)
	unit.casualty_records.assign(data.casualty_records)
	Globals.import_casualty_records(unit.casualty_records)
	
		#if soldier != null:
			#squad_fire.soldiers.append(soldier)

	#stress_controller.stress_fast = data.stress_fast
	#stress_controller.stress_slow = data.stress_slow
	#cohesion = data.cohesion
	#current_state = data.state

	#rebuild_after_load()
