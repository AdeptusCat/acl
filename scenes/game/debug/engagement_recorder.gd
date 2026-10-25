class_name EngagementRecorder
extends Node

const ROOT_DIRECTORY: String = "user://debug/engagements"
const SAMPLE_INTERVAL_S: float = 1.0
const RULE_SCRIPTS: Array[String] = [
	"res://scenes/game/units/combat/unit_stress_controller.gd",
	"res://scenes/game/units/combat/squad_fire_controller.gd",
	"res://scenes/game/units/combat/squad_hit_resolver.gd",
	"res://scenes/game/units/combat/unit_combat_stats.gd",
	"res://scenes/game/units/combat/unit_casualty_handler.gd",
	"res://ai/squad/squad_tactical_state.gd",
	"res://autoloads/unit_states.gd",
	"res://autoloads/rank_grades.gd",
	"res://scenes/game/units/unit.gd",
	"res://scenes/game/units/soldiers/soldier.gd",
	"res://scenes/game/units/command/command_connectivity.gd",
	"res://scenes/game/units/command/leader_aura.gd",
	"res://scenes/game/units/actions/squad_action_controller.gd",
]

var active: bool = false
var directory: String = ""
var _owner: WeakRef
var _events: FileAccess
var _snapshots: FileAccess
var _units: Dictionary[int, WeakRef] = {}
var _weapons: Dictionary[int, String] = {}
var _attention: Dictionary[int, Dictionary] = {}
var _pending_effects: Dictionary[int, Array] = {}
var _connections: Array[Dictionary] = []
var _sequence: int = 0
var _sample_count: int = 0
var _elapsed_s: float = 0.0
var _sample_elapsed_s: float = 0.0
var _started_physics_frame: int = 0
var _result: Dictionary = {}


func _debug_allowed() -> bool:
	return OS.is_debug_build() and not Engine.is_editor_hint()


func start_capture(controller: Node, root_directory: String = ROOT_DIRECTORY) -> bool:
	finish("replaced")
	if not _debug_allowed() or not is_instance_valid(controller):
		return false
	var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "-")
	# Crypto does not consume the gameplay random stream.
	directory = root_directory.path_join(stamp + "_" + Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_warning("Could not create engagement capture: " + directory)
		return false
	_events = FileAccess.open(directory.path_join("events.jsonl"), FileAccess.WRITE)
	_snapshots = FileAccess.open(directory.path_join("snapshots.jsonl"), FileAccess.WRITE)
	if _events == null or _snapshots == null:
		_abort("Could not open engagement capture streams")
		return false
	_owner = weakref(controller)
	_units.clear()
	_weapons.clear()
	_attention.clear()
	_pending_effects.clear()
	_sequence = 0
	_sample_count = 0
	_elapsed_s = 0.0
	_sample_elapsed_s = 0.0
	_started_physics_frame = Engine.get_physics_frames()
	_result.clear()
	active = true
	if not _save_json("metadata.json", _metadata()) or not _save_json("map.json", _map_snapshot()) or not _save_json("summary.json", {"schema_version": 1, "complete": false, "reason": "capturing"}):
		_abort("Could not save engagement capture metadata")
		return false
	_connect(controller, "tree_exiting", _on_owner_exiting)
	if controller.has_signal("show_winner"):
		_connect(controller, "show_winner", _on_result)
	record_event("session_started", {"battle_id": Globals.battle_id})
	_sample()
	_flush()
	print("Engagement capture: ", ProjectSettings.globalize_path(directory))
	return active


func _process(delta: float) -> void:
	if not active:
		return
	if not _debug_allowed():
		finish("debug_disabled")
		return
	_elapsed_s += delta
	_sample_elapsed_s += delta
	if _sample_elapsed_s >= SAMPLE_INTERVAL_S:
		_sample_elapsed_s = fmod(_sample_elapsed_s, SAMPLE_INTERVAL_S)
		_sample()
		_flush()


func _exit_tree() -> void:
	finish("application_exit")


func finish(reason: String) -> void:
	if active:
		_sample()
		record_event("session_finished", {"reason": reason})
		_flush()
		if active and not _save_json("summary.json", {"schema_version": 1, "complete": true, "reason": reason, "elapsed_s": _elapsed_s, "events": _sequence, "samples": _sample_count, "units": _units.size(), "result": _result}):
			push_warning("Could not finalize engagement capture summary: " + directory)
	active = false
	_disconnect_all()
	_close_streams()
	_units.clear()
	_attention.clear()
	_pending_effects.clear()
	_weapons.clear()
	_owner = null


func record_event(kind: String, data: Dictionary) -> int:
	if not active or not _debug_allowed():
		return -1
	_sequence += 1
	var row: Dictionary = {"schema_version": 1, "seq": _sequence, "time_s": _elapsed_s, "physics_frame": Engine.get_physics_frames() - _started_physics_frame, "type": kind, "data": data}
	_events.store_line(JSON.stringify(row))
	return _sequence


func tracks(unit: Unit) -> bool:
	if not active or not _debug_allowed() or not is_instance_valid(unit) or _owner == null:
		return false
	var host: Node = _owner.get_ref() as Node
	return is_instance_valid(host) and host.is_ancestor_of(unit)


func record_order(unit: Unit, command: int, target: Variant) -> void:
	if tracks(unit):
		_register(unit)
		record_event("order", {"unit": _unit_id(unit), "command": command, "target": _value(target)})


func record_shot(controller: SquadFireController, soldier: Soldier, rounds: int, cell: Vector2i, distance: int, cover: int, origin: Vector2, flight_s: float, grenade: bool) -> void:
	if not tracks(controller.unit):
		return
	_register(controller.unit)
	record_event("shot_committed", {"shooter": _unit_id(controller.unit), "soldier": soldier.id, "role": soldier.role, "weapon": _weapon_id(soldier.weapon), "rounds": rounds, "target_hex": _value(cell), "target": _value(controller.target_unit), "distance": distance, "cover": cover, "origin": _value(origin), "flight_s": flight_s, "grenade": grenade, "magazine_after": soldier.rounds_in_mag, "ammunition_after": str(soldier.weapon.ammunition), "rof_mult": soldier.rof_mult, "accuracy_mult": soldier.acc_mult})


func record_impact(controller: SquadFireController, target: Unit, weapon: WeaponSpec, context: Dictionary) -> void:
	if not tracks(target):
		return
	_register(target)
	if tracks(controller.unit):
		_register(controller.unit)
	var data: Dictionary = context.duplicate()
	data.shooter = _unit_id(controller.unit)
	data.target = _unit_id(target)
	data.weapon = _weapon_id(weapon)
	var sequence: int = record_event("impact_resolved", data)
	var key: int = target.get_instance_id()
	if not _pending_effects.has(key):
		_pending_effects[key] = []
	_pending_effects[key].append(sequence)


func begin_effect(unit: Unit, casualties: int, fast: float, slow: float, source: Node) -> Dictionary:
	if not tracks(unit):
		return {}
	_register(unit)
	var impact: int = -1
	var key: int = unit.get_instance_id()
	if _pending_effects.has(key) and not _pending_effects[key].is_empty():
		impact = int(_pending_effects[key].pop_front())
		if _pending_effects[key].is_empty():
			_pending_effects.erase(key)
	return {"unit": _unit_id(unit), "impact_seq": impact, "source": _source_id(source), "casualties_requested": casualties, "raw_fast": fast, "raw_slow": slow, "members_before": unit.members_alive, "stress_before": unit.stress_system.S_eff, "active": unit.is_active(), "no_damage": Debug.no_damage}


func finish_effect(unit: Unit, context: Dictionary, disposition: String) -> void:
	if context.is_empty() or not active:
		return
	context.disposition = disposition
	context.members_after = unit.members_alive
	context.stress_after = unit.stress_system.S_eff
	record_event("incoming_effect_applied", context)


func record_stress_gain(unit: Unit, fast: float, slow: float, before: Vector2, cause: String) -> void:
	if not tracks(unit):
		return
	_register(unit)
	var stress: StressController = unit.stress_system
	var gain: float = maxf(0.0, stress.S_eff - (before.x + before.y) * 0.5)
	if cause == "attention":
		var key: int = unit.get_instance_id()
		if not _attention.has(key):
			_attention[key] = {"raw_fast": 0.0, "raw_slow": 0.0, "effective_gain": 0.0}
		_attention[key].raw_fast = float(_attention[key].raw_fast) + fast
		_attention[key].raw_slow = float(_attention[key].raw_slow) + slow
		_attention[key].effective_gain = float(_attention[key].effective_gain) + gain
		return
	record_event("stress_gain", {"unit": _unit_id(unit), "cause": cause, "raw_fast": fast, "raw_slow": slow, "bins_before": _value(before), "bins_after": [stress.stress_fast, stress.stress_slow], "effective_gain": gain, "leadership": stress.leadership_bonus, "presence": stress.leader_presence_strength, "incoming_scale": stress.incoming_stress_scale})


func record_casualty(unit: Unit, soldier: Soldier, record: CasualtyRecord) -> void:
	if tracks(unit):
		_register(unit)
		record_event("casualty", {"unit": _unit_id(unit), "soldier": _soldier(soldier), "record_id": record.record_id})


func _sample() -> void:
	if not active:
		return
	for unit: Unit in Globals.get_units():
		if tracks(unit):
			_register(unit)
	var states: Array[Dictionary] = []
	for key: int in _units.keys():
		var unit: Unit = _units[key].get_ref() as Unit
		if not is_instance_valid(unit):
			record_event("unit_removed", {"unit": "u_%d" % key, "pending_impacts": _pending_effects.get(key, [])})
			_units.erase(key)
			_attention.erase(key)
			_pending_effects.erase(key)
			continue
		var state: Dictionary = _unit_snapshot(unit)
		state.attention_gain_since_sample = _attention.get(key, {})
		states.append(state)
	_attention.clear()
	_sample_count += 1
	_snapshots.store_line(JSON.stringify({"sample": _sample_count, "time_s": _elapsed_s, "physics_frame": Engine.get_physics_frames() - _started_physics_frame, "match": _match_state(), "debug": _debug_flags(), "units": states}))


func _register(unit: Unit) -> void:
	var key: int = unit.get_instance_id()
	if _units.has(key):
		return
	_units[key] = weakref(unit)
	_connect(unit, "unit_died", _on_unit_died)
	_connect(unit, "unit_exited", _on_unit_exited)
	_connect(unit, "unit_surrendered", _on_surrendered.bind(unit))
	_connect(unit, "soldiers_changed", _on_roster_changed.bind(unit))
	_connect(unit.stress_system, "state_changed", _on_morale_changed.bind(unit))
	_connect(unit.action_controller, "action_state_changed", _on_action_changed.bind(unit))
	record_event("unit_registered", {"state": _unit_snapshot(unit), "stress_tunables": _exports(unit.stress_system), "morale_recovery_factors": _value(unit.stress_system._state_mod_dict), "fire_tunables": _exports(unit.squad_fire), "combat_tunables": _exports(unit.combat_stats)})


func _unit_id(unit: Unit) -> String:
	if not is_instance_valid(unit):
		return ""
	return "u_%d" % unit.get_instance_id()


func _source_id(source: Node) -> String:
	if source is SquadFireController:
		return _unit_id((source as SquadFireController).unit)
	if source is Unit:
		return _unit_id(source as Unit)
	return ""


func _weapon_id(weapon: WeaponSpec) -> String:
	if weapon == null:
		return ""
	var key: int = weapon.get_instance_id()
	if not _weapons.has(key):
		var identifier: String = "w_%d" % _weapons.size()
		_weapons[key] = identifier
		record_event("weapon_registered", {"weapon": identifier, "resource": weapon.source_resource_path, "definition": _exports(weapon)})
	return _weapons[key]


func _soldier(soldier: Soldier) -> Dictionary:
	return {
		"id": soldier.id,
		"name": soldier.name,
		"role": soldier.role,
		"rank": soldier.rank_grade,
		"alive": soldier.is_alive,
		"weapon": _weapon_id(soldier.weapon),
		"magazine": soldier.rounds_in_mag,
		"ammunition": str(soldier.weapon.ammunition),
		"grenade_loaded": soldier.weapon.riflegrenade_loaded,
		"rof_mult": soldier.rof_mult,
		"acc_mult": soldier.acc_mult,
		"setup_remaining_s": soldier.setup_weapon_task.remaining_time_s,
		"reload_remaining_s": soldier.reload_task.remaining_time_s,
		"acquire_remaining_s": soldier.aquire_target_task.remaining_time_s,
		"setup_done": soldier.setup_weapon_task.done,
		"reload_done": soldier.reload_task.done,
		"acquire_done": soldier.aquire_target_task.done,
	}


func _unit_snapshot(unit: Unit) -> Dictionary:
	var roster: Array[Dictionary] = []
	for soldier: Soldier in unit.squad_fire.soldiers:
		roster.append(_soldier(soldier))
	var visible: Array[String] = []
	for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
		if is_instance_valid(enemy):
			visible.append(_unit_id(enemy))
	var tracks_seen: Array[Dictionary] = []
	for enemy: Unit in Globals.unit_enemy_tracks.get(unit, {}):
		var track: EnemyTrack = Globals.unit_enemy_tracks[unit][enemy] as EnemyTrack
		if is_instance_valid(enemy) and track != null:
			tracks_seen.append({"unit": _unit_id(enemy), "awareness": track.awareness, "hex": _value(track.last_known_hex), "position": _value(track.last_known_global_position)})
	var stress: StressController = unit.stress_system
	var attention: SquadTacticalState = unit.tactical_state
	return {
		"unit": _unit_id(unit),
		"name": str(unit.name),
		"team": unit.team,
		"company": unit.company,
		"platoon": unit.platoon,
		"squad": unit.squad,
		"squad_type": unit.squad_type,
		"loadout": unit.squad_loadout.resource_path,
		"hex": _value(unit.current_hex),
		"position": _value(unit.global_position),
		"cover": unit.current_cover_bonus,
		"terrain_defense": unit.terrain_defense_bonus,
		"active": unit.is_active(),
		"surrendered": unit.surrendered,
		"exited": unit.exited,
		"moving": unit.is_moving,
		"broken": unit.broken,
		"close_combat": unit.in_close_combat,
		"members": unit.members_alive,
		"original_size": unit.original_size,
		"casualties": unit.casualties_taken,
		"leader_alive": unit.embedded_leader_alive,
		"stress": {"effective": stress.S_eff, "fast": stress.stress_fast, "slow": stress.stress_slow, "morale": stress.state, "incoming_rate": stress.incoming_stress_rate, "actual_recovery_rate": stress.stress_recovery_rate, "capacity": stress.get_recovery_capacity(), "net_rate": stress.net_stress_rate, "balance_window_s": stress.balance_sample_duration_s, "pressure_rps": stress._last_pressure_rps, "under_fire_remaining_s": stress._under_fire_t, "casualty_shock": stress._casualty_recovery_shock, "casualty_shock_remaining_s": stress._casualty_recovery_t, "since_pinned_s": stress._since_pinned, "since_unpinned_s": stress._repin_since_unpin, "leadership_bonus": stress.leadership_bonus, "presence": stress.leader_presence_strength, "base_cohesion": stress.cohesion, "aura_cohesion_mult": stress._leadership_cohesion_mult},
		"attention": {"focus": _value(attention.focus_direction), "width": attention.attention_width, "quality": attention.attention_quality, "capacity": attention.attention_capacity, "demand": attention.total_directional_demand, "sectors": _value(attention.directional_demand), "incoming_sectors": _value(attention.incoming_fire_demand), "deficit": attention.attention_deficit, "overload_rate": attention.attention_stress_rate, "switching_rate": attention.switching_stress_rate, "switch_load": attention.attention_switch_load, "surprise": attention.last_attack_surprise, "crossfire": attention.multi_direction_pressure, "flanked": attention.flanked, "surrounded": attention.surrounded},
		"combat": {"cohesion": unit.combat_stats.cohesion_current, "cohesion_target": unit.combat_stats.cohesion_target, "effectiveness": unit.combat_stats.combat_effectiveness, "casualty_shock": unit.combat_stats.recent_casualty_shock},
		"command": {"hq": _unit_id(unit.command_squad), "link": unit.command_connectivity.command_link_strength, "presence": unit.command_connectivity.leader_presence_strength},
		"orders": {"attack_state": unit.attackState, "target": _unit_id(unit.squad_fire.target_unit), "target_hex": _value(unit.squad_fire.target_hex), "has_target": unit.squad_fire.has_target_hex, "action": unit.action_controller.action_state, "action_order": unit.action_controller.action_order_id, "objective_hex": _value(unit.action_controller.objective_hex), "move_target": _value(unit.movement.target_hex), "role": attention.current_role, "task_id": attention.assigned_task_id, "support_only": unit.ai_support_only},
		"visible_enemies": visible,
		"enemy_tracks": tracks_seen,
		"soldiers": roster,
	}


func _metadata() -> Dictionary:
	var rules: Dictionary = {}
	for path: String in RULE_SCRIPTS:
		rules[path] = "unavailable"
		if FileAccess.file_exists(path):
			rules[path] = FileAccess.get_sha256(path)
	var map_data: Dictionary = {}
	if is_instance_valid(Globals.map_chosen):
		map_data = {"name": Globals.map_chosen.map_name, "scene": Globals.map_chosen.scene_file_path, "los_resource": Globals.map_chosen.los_resource_path}
	var scenario_data: Dictionary = {}
	if is_instance_valid(Globals.scenario_chosen):
		scenario_data = {"scene": Globals.scenario_chosen.scene_file_path, "settings": _exports(Globals.scenario_chosen)}
	return {
		"schema_version": 1,
		"started_utc": Time.get_datetime_string_from_system(true),
		"battle_id": Globals.battle_id,
		"engine": Engine.get_version_info(),
		"debug_build": OS.is_debug_build(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"time_scale": Engine.time_scale,
		"player_team": Globals.team_player,
		"game_mode": Globals.game_mode,
		"map": map_data,
		"scenario": scenario_data,
		"rules_sha256": rules,
		"state_modifiers": _value(STATES.STATE_MOD),
		"rank_parameters": _value(RankGrades.GRADE_PARAMS),
		"debug": _debug_flags(),
		"snapshot_interval_s": SAMPLE_INTERVAL_S,
		"replay_guaranteed": false,
	}


func _map_snapshot() -> Dictionary:
	var layers: Array[Dictionary] = []
	for layer: TileMapLayer in [LOSHelper.ground_layer, LOSHelper.building_layer, LOSHelper.wall_layer, LOSHelper.terrain_layer, LOSHelper.road_layer]:
		if not is_instance_valid(layer) or layer.tile_set == null:
			continue
		var cells: Array[Dictionary] = []
		for cell: Vector2i in layer.get_used_cells():
			var custom: Dictionary = {}
			var tile: TileData = layer.get_cell_tile_data(cell)
			if tile != null:
				for index: int in range(layer.tile_set.get_custom_data_layers_count()):
					custom[layer.tile_set.get_custom_data_layer_name(index)] = _value(tile.get_custom_data_by_layer_id(index))
			cells.append({"hex": _value(cell), "source": layer.get_cell_source_id(cell), "atlas": _value(layer.get_cell_atlas_coords(cell)), "alternative": layer.get_cell_alternative_tile(cell), "data": custom})
		layers.append({"name": str(layer.name), "tileset": layer.tile_set.resource_path, "tile_size": _value(layer.tile_set.tile_size), "position": _value(layer.global_position), "cells": cells})
	return {"layers": layers}


func _exports(object: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in object.get_property_list():
		var usage: int = int(property.usage)
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR:
			result[str(property.name)] = _value(object.get(property.name))
	return result


func _value(value: Variant) -> Variant:
	if value is Unit:
		return _unit_id(value as Unit)
	if value is Resource:
		var resource: Resource = value as Resource
		return {"resource": resource.resource_path, "class": resource.get_class()}
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Vector3 or value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedStringArray or value is PackedByteArray:
		var array: Array = []
		for item: Variant in value:
			array.append(_value(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value:
			dictionary[str(key)] = _value(value[key])
		return dictionary
	if value is Object:
		return str(value)
	if value is float and not is_finite(value):
		return str(value)
	return value


func _match_state() -> Dictionary:
	var host: Node = _owner.get_ref() as Node
	if not is_instance_valid(host):
		return {}
	return {"time_left_s": host.get("time_left_seconds"), "timer_running": host.get("timer_running"), "ended": host.get("end_game_handled"), "continuing": host.get("continuing_after_end"), "time_scale": Engine.time_scale}


func _debug_flags() -> Dictionary:
	return {"no_damage": Debug.no_damage, "dont_fire_weapons": Debug.dont_fire_wepaons, "show_enemies": Debug.show_enemies, "hide_fog_of_war": Debug.hide_fog_of_war}


func _on_result(winner: int, outcome: int, timeout: bool) -> void:
	_result = {"winner": winner, "outcome": outcome, "timeout": timeout}
	record_event("match_result", _result)
	_sample()
	_flush()
	if active and not _save_json("summary.json", {"schema_version": 1, "complete": false, "reason": "result_shown_capture_continues", "elapsed_s": _elapsed_s, "events": _sequence, "samples": _sample_count, "result": _result}):
		_abort("Could not save engagement result summary")


func _on_owner_exiting() -> void:
	finish("map_closed")


func _on_unit_died(unit: Unit) -> void:
	record_event("unit_died", _unit_snapshot(unit))


func _on_unit_exited(unit: Unit) -> void:
	record_event("unit_exited", _unit_snapshot(unit))


func _on_surrendered(unit: Unit) -> void:
	record_event("unit_surrendered", _unit_snapshot(unit))


func _on_roster_changed(unit: Unit) -> void:
	record_event("roster_changed", _unit_snapshot(unit))


func _on_morale_changed(previous: int, next: int, unit: Unit) -> void:
	record_event("morale_changed", {"unit": _unit_id(unit), "previous": previous, "next": next, "state": _unit_snapshot(unit)})


func _on_action_changed(previous: int, next: int, unit: Unit) -> void:
	record_event("action_changed", {"unit": _unit_id(unit), "previous": previous, "next": next, "state": _unit_snapshot(unit)})


func _connect(object: Object, signal_name: StringName, callback: Callable) -> void:
	object.connect(signal_name, callback)
	_connections.append({"object": weakref(object), "signal": signal_name, "callback": callback})


func _disconnect_all() -> void:
	for connection: Dictionary in _connections:
		var object: Object = (connection.object as WeakRef).get_ref()
		if is_instance_valid(object) and object.is_connected(connection.signal, connection.callback):
			object.disconnect(connection.signal, connection.callback)
	_connections.clear()


func _save_json(filename: String, data: Dictionary) -> bool:
	var destination: String = directory.path_join(filename)
	var pending: String = destination + ".pending"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var success: bool = file.get_error() == OK
	file.close()
	if not success:
		return false
	return DirAccess.rename_absolute(pending, destination) == OK


func _flush() -> void:
	if not active:
		return
	_events.flush()
	_snapshots.flush()
	if _events.get_error() != OK or _snapshots.get_error() != OK:
		_abort("Could not flush engagement capture")


func _abort(message: String) -> void:
	active = false
	_disconnect_all()
	_close_streams()
	push_warning(message + ": " + directory)


func _close_streams() -> void:
	if _events != null:
		_events.close()
	if _snapshots != null:
		_snapshots.close()
	_events = null
	_snapshots = null
