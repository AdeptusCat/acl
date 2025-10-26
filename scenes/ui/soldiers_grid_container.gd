extends GridContainer

@export var soldier_detail_label_scene: PackedScene
@export var soldier_detail_progress_bar_scene: PackedScene

enum Entry { NAME, ROLE, RANK, WEAPON, PROGRESS_BAR }

var unit: Unit
var soldiers: Array[Soldier]
var soldier_entries_by_soldier: Dictionary[Soldier, Dictionary]
var soldiers_entries: Array[Dictionary]



func _ready() -> void:
	
	for i in range(12):
		var soldier_entries: Dictionary[Entry, Control]
		
		var name_label: Label = soldier_detail_label_scene.instantiate()
		add_child(name_label)
		soldier_entries[Entry.NAME] = name_label
		
		var role_label: Label = soldier_detail_label_scene.instantiate()
		add_child(role_label)
		soldier_entries[Entry.ROLE] = role_label
		
		#var rank_label: Label = soldier_detail_label_scene.instantiate()
		#add_child(rank_label)
		#soldier_entries[Entry.RANK] = rank_label
		
		var weapon_label: Label = soldier_detail_label_scene.instantiate()
		add_child(weapon_label)
		soldier_entries[Entry.WEAPON] = weapon_label
		
		var progress_bar: ProgressBar = soldier_detail_progress_bar_scene.instantiate()
		add_child(progress_bar)
		soldier_entries[Entry.PROGRESS_BAR] = progress_bar
		
		soldiers_entries.append(soldier_entries)
		
	columns = soldiers_entries[0].size()


func _process(delta: float) -> void:
	if is_instance_valid(unit):
		for s in soldier_entries_by_soldier:
			var progress_bar: ProgressBar = soldier_entries_by_soldier[s][Entry.PROGRESS_BAR]
			if s:
				var p2: float = get_makeready_progress(s)
				progress_bar.value = p2


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


func show_unit_detail(_unit: Unit):
	unit = _unit
	soldiers = unit.squad_fire.soldiers
	var i: int = 0
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
	
	while i < soldiers_entries.size():
		var entries: Dictionary = soldiers_entries[i]
		for entry in entries.values():
			entry.hide()
		i += 1
	
	unit.soldiers_changed.connect(_on_soldiers_changed)

func hide_unit_detail():
	unit.soldiers_changed.disconnect(_on_soldiers_changed)
	unit = null

func _on_soldiers_changed():
	if is_instance_valid(unit):
		show_unit_detail(unit)
