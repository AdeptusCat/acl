extends PanelContainer

@export var soldier_detail_label_scene: PackedScene
@export var soldier_detail_progress_bar_scene: PackedScene

@onready var unit_grid_container: GridContainer = $MarginContainer/SoldiersContainer/UnitGridContainer
@onready var soldiers_grid_container: GridContainer = $MarginContainer/SoldiersContainer/FoldableContainer/SoldiersGridContainer
@onready var unit_status_label: Label = $MarginContainer/SoldiersContainer/UnitGridContainer/UnitStatus
@onready var unit_type_label: Label = $MarginContainer/SoldiersContainer/UnitGridContainer/UnitType
@onready var leadership_bonud_label: Label = $MarginContainer/SoldiersContainer/UnitGridContainer/LeadershipBonus
@onready var panel: PanelContainer = self
@onready var kill_button: Button = $MarginContainer/SoldiersContainer/UnitGridContainer/Kill


var opacity_tween: Tween = null

enum Entry { NAME, ROLE, RANK, WEAPON, TASK, PROGRESS_BAR }

var unit: Unit
var soldiers: Array[Soldier]
var casualties: Array[Soldier]

var soldier_entries_by_soldier: Dictionary[Soldier, Dictionary]
var soldiers_entries: Array[Dictionary]

var casualty_entries_by_casualty: Dictionary[Soldier, Dictionary]
var casualties_entries: Array[Dictionary]


func _ready() -> void:
	
	for i in range(12):
		var soldier_entries: Dictionary[Entry, Control]
		
		var name_label: Label = soldier_detail_label_scene.instantiate()
		soldiers_grid_container.add_child(name_label)
		soldier_entries[Entry.NAME] = name_label
		
		var role_label: Label = soldier_detail_label_scene.instantiate()
		soldiers_grid_container.add_child(role_label)
		soldier_entries[Entry.ROLE] = role_label
		
		#var rank_label: Label = soldier_detail_label_scene.instantiate()
		#soldiers_grid_container.add_child(rank_label)
		#soldier_entries[Entry.RANK] = rank_label
		
		var weapon_label: Label = soldier_detail_label_scene.instantiate()
		soldiers_grid_container.add_child(weapon_label)
		soldier_entries[Entry.WEAPON] = weapon_label
		
		var task_label: Label = soldier_detail_label_scene.instantiate()
		soldiers_grid_container.add_child(task_label)
		soldier_entries[Entry.TASK] = task_label
		
		var progress_bar: ProgressBar = soldier_detail_progress_bar_scene.instantiate()
		soldiers_grid_container.add_child(progress_bar)
		soldier_entries[Entry.PROGRESS_BAR] = progress_bar
		
		soldiers_entries.append(soldier_entries)
		
	soldiers_grid_container.columns = soldiers_entries[0].size()
	


func _process(_delta: float) -> void:
	if is_instance_valid(unit):
		for s in soldier_entries_by_soldier:
			#var progress_bar: ProgressBar = soldier_entries_by_soldier[s][Entry.PROGRESS_BAR]
			if s:
				#var p2: float = get_makeready_progress(s)
				#progress_bar.value = p2
				#if p2 >= 1.0:
					#var string: String = str(unit)
					#print(string)
				if not unit.is_good_order():
					set_progress_bar(s, "Panicking", 0, 0)
					continue
				if unit.moving:
					set_progress_bar(s, "Moving", 0, 0)
					continue
				if unit.in_close_combat:
					set_progress_bar(s, s.close_combat_task.task_name, 0, 0)
					continue
				if not s.is_weapon_setup_done(0.0):
					set_progress_bar(s, s.setup_weapon_task.task_name, s.setup_weapon_task.start_time_s, s.setup_weapon_task.remaining_time_s)
					continue
				if not s.is_weapon_reload_done(0.0):
					set_progress_bar(s, s.reload_task.task_name, s.reload_task.start_time_s, s.reload_task.remaining_time_s)
					continue
				if not s.is_acquiring_target_done(0.0):
					set_progress_bar(s, s.aquire_target_task.task_name, s.aquire_target_task.start_time_s, s.aquire_target_task.remaining_time_s)
					continue
				if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
					set_progress_bar(s, s.assist_task.task_name, 0, 0)
					continue
				set_progress_bar(s, "Idle", 0, 0)
		for s in casualty_entries_by_casualty:
			set_casualty_progress_bar(s, "INCAPACITATED", 0, 0)


func set_progress_bar(s:Soldier, task_name: String, start_time_s: float, remaining_time_s: float):
	var progress_bar: ProgressBar = soldier_entries_by_soldier[s][Entry.PROGRESS_BAR]
	var elapsed_time_s: float = start_time_s - remaining_time_s
	progress_bar.value = elapsed_time_s / start_time_s
	
	var task_label: Label = soldier_entries_by_soldier[s][Entry.TASK]
	task_label.remove_theme_color_override("font_color")
	task_label.text = task_name

func set_casualty_progress_bar(s:Soldier, task_name: String, start_time_s: float, remaining_time_s: float):
	var progress_bar: ProgressBar = casualty_entries_by_casualty[s][Entry.PROGRESS_BAR]
	var elapsed_time_s: float = start_time_s - remaining_time_s
	progress_bar.value = elapsed_time_s / start_time_s
	
	var task_label: Label = casualty_entries_by_casualty[s][Entry.TASK]
	task_label.add_theme_color_override("font_color", Color.RED)
	task_label.text = task_name


func get_makeready_progress(soldier: Soldier) -> float:
	# 0.0..1.0 progress bar value
	var t1_delta: float = soldier.next_ready_delta_s
	var t0: float = soldier.next_ready_start_s
	var elapsed: float = soldier.now_s - t0
	#$HBoxContainer/Label.text = str(t1_delta)
	var p: float = elapsed / t1_delta
	if p < 0.0:
		p = 0.0
	if p > 1.0:
		p = 1.0
	return p


func show_unit_detail(_unit: Unit, tween_on: bool = true):
	# this shows the panel without weird resizing issue when using hiding()/showing()
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	if tween_on:
		modulate.a = 0.0
		tween_opacity(1.0)
	
	soldiers = _unit.squad_fire.soldiers
	casualties = _unit.squad_fire.casualties
	var i: int = 0
	soldier_entries_by_soldier.clear()
	for s in soldiers:
		var entries: Dictionary = soldiers_entries[i]
		
		entries[Entry.NAME].text = s.name
		entries[Entry.ROLE].text = RankGrades.get_role_name(s.role)
		#entries[Entry.RANK].text = s.name
		entries[Entry.WEAPON].text = s.weapon.name
		#entries[Entry.PROGRESS_BAR].value = 0.0
		
		soldier_entries_by_soldier[s] = entries
		
		for entry in entries.values():
			entry.show()
		
		i += 1
	
	casualty_entries_by_casualty.clear()
	for s in casualties:
		var entries: Dictionary = soldiers_entries[i]
		
		entries[Entry.NAME].text = s.name
		entries[Entry.ROLE].text = RankGrades.get_role_name(s.role)
		#entries[Entry.RANK].text = s.name
		entries[Entry.WEAPON].text = s.weapon.name
		#entries[Entry.PROGRESS_BAR].value = 0.0
		
		casualty_entries_by_casualty[s] = entries
		
		for entry in entries.values():
			entry.show()
		
		i += 1
	
	while i < soldiers_entries.size():
		var entries: Dictionary = soldiers_entries[i]
		for entry in entries.values():
			entry.hide()
		i += 1
	
	if not _unit == unit:
		if is_instance_valid(unit): 
			unit.stress_system.leadership_changed.disconnect(_on_leadership_changed)
			unit.soldiers_changed.disconnect(_on_soldiers_changed)
			unit.state_changed.disconnect(_on_state_changed)
			unit.unit_died.disconnect(_on_unit_died)
		
		unit = _unit
		
		unit.stress_system.leadership_changed.connect(_on_leadership_changed)
		unit.soldiers_changed.connect(_on_soldiers_changed)
		unit.state_changed.connect(_on_state_changed)
		unit.unit_died.connect(_on_unit_died)
		
	
	_on_leadership_changed(unit.stress_system.leadership_bonus)
	_on_state_changed(unit.stress_system.state)
	unit_type_label.text = unit.get_squad_type_name(unit.squadType)
	
	show()
	if OS.is_debug_build():
		kill_button.show()
	#await get_tree().process_frame
	#reset_size()

func hide_unit_detail():
	await tween_opacity(0.0).finished
	#hide()
	# this hides it effectively
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	
	if is_instance_valid(unit): 
		if unit.stress_system.leadership_changed.is_connected(_on_leadership_changed):
			unit.stress_system.leadership_changed.disconnect(_on_leadership_changed)
			unit.soldiers_changed.disconnect(_on_soldiers_changed)
			unit.state_changed.disconnect(_on_state_changed)
			unit.unit_died.disconnect(_on_unit_died)
		unit = null

func _on_unit_died(_unit: Unit):
	if is_instance_valid(unit): 
		_unit.stress_system.leadership_changed.disconnect(_on_leadership_changed)
		_unit.soldiers_changed.disconnect(_on_soldiers_changed)
		_unit.state_changed.disconnect(_on_state_changed)
		_unit.unit_died.disconnect(_on_unit_died)
		hide_unit_detail()

func _on_soldiers_changed():
	if is_instance_valid(unit):
		show_unit_detail(unit, false)


func _on_state_changed(state: int):
	if is_instance_valid(unit):
		unit_status_label.text = unit.get_state_name(state)
	var color: Color
	match state:
		unit.MoraleState.NORMAL:
			color = Color(0.0, 0.536, 0.0, 1.0)
		unit.MoraleState.CAUTIOUS:
			color = Color(0.65, 0.525, 0.184, 1.0)
		unit.MoraleState.PINNED:
			color = Color(0.713, 0.292, 0.0, 1.0)
		unit.MoraleState.PANIC:
			color = Color(0.847, 0.0, 0.097, 1.0)
		unit.MoraleState.COMBAT_INEFFECTIVE:
			color = Color(0.178, 0.0, 0.765, 1.0)
	unit_status_label.add_theme_color_override("font_color", color)


func _on_leadership_changed(leadership_bonus: float) -> void:
	var txt: String = ""# = "%0.2f" % leadership_bonus
	txt += stress_to_plus_string(leadership_bonus)
	leadership_bonud_label.text = txt


func stress_to_plus_string(value: float) -> String:
	#Grade.SOLDIER:      			{ "lead": 0.00, "rally": 0.00, "radius": 0, "coh_mult": 1.00 },
	#Grade.ASSISTANT_TEAM_LEADER: 	{ "lead": 0.03, "rally": 0.015, "radius": 0, "coh_mult": 1.01 },
	#Grade.TEAM_LEADER:   			{ "lead": 0.05, "rally": 0.03, "radius": 0, "coh_mult": 1.02 },
	#Grade.SQUAD_LEADER:  			{ "lead": 0.10, "rally": 0.05, "radius": 0, "coh_mult": 1.04 },
	#Grade.PLATOON_LEADER:			{ "lead": 0.18, "rally": 0.08, "radius": 1, "coh_mult": 1.06 },
	#Grade.COMPANY_LEADER:			{ "lead": 0.22, "rally": 0.10, "radius": 2, "coh_mult": 1.08 },
	var result: String = ""
	if value >= RankGrades.GRADE_PARAMS[RankGrades.Grade.COMPANY_LEADER].lead:
		result = "+++"
	elif value >= RankGrades.GRADE_PARAMS[RankGrades.Grade.PLATOON_LEADER].lead:
		result = "++"
	elif value >= RankGrades.GRADE_PARAMS[RankGrades.Grade.SQUAD_LEADER].lead:
		result = "+"
	#var result: String = ""
	#if value > 0.0:
		#var count: int = int(floor(value / 0.09))
		#var i: int = 0
		#while i < count:
			#result += "+"
			#i += 1
	return result



func tween_opacity(to: float):
	if opacity_tween: 
		opacity_tween.kill()
	opacity_tween = get_tree().create_tween()
	opacity_tween.tween_property(self, 'modulate:a', to, 0.3)
	return opacity_tween


func _on_kill_pressed() -> void:
	Debug.units_to_kill.append(unit)
