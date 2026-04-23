extends CanvasLayer


signal game_started(team : int)
signal hover_start_button(team: int)
signal time_changed(_time: float)



@onready var objective_label = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/ObjectiveLabel
@onready var start_as_axis_button = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/VBoxContainer2/HBoxContainer/StartAsAxisButton
@onready var start_as_allies_button = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/VBoxContainer2/HBoxContainer/StartAsAlliesButton
@onready var animation_player = $AnimationPlayer
@onready var time_spinbox = $Control/CenterContainer/PanelContainer/VBoxContainer/HBoxContainer/SpinBox
@onready var game_mode_attack = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/VBoxContainer/HBoxContainer/GameModeAttack
@onready var game_mode_defend = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/VBoxContainer/HBoxContainer/GameModeDefend
@onready var maps_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/MapsVBoxContainer
@onready var scenario_description: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/ScenarioDescription
@onready var team: TextureRect = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/Team
@onready var objectives_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/ObjectivesVBoxContainer


var team_texture: Dictionary[Globals.Team, Texture] = {
	Globals.Team.AXIS: preload("res://assets/ui/axis_flag.png"),
	Globals.Team.ALLIES: preload("res://assets/ui/us_flag.png")
}

var time: float

func _ready():
	if not SessionSettings.mission_time == 0:
		time_spinbox.value = SessionSettings.mission_time
	if Globals.game_mode == Globals.GameMode.DEFEND:
		game_mode_defend.text = "DEFEND"
		game_mode_attack.text = ""
	if Globals.game_mode == Globals.GameMode.ATTACK:
		game_mode_attack.text = "ATTACK"
		game_mode_defend.text = ""
	#visible = true
	start_as_axis_button.pressed.connect(_on_start_as_axis_pressed)
	start_as_allies_button.pressed.connect(_on_start_as_allies_pressed)
	animation_player.play("fade_in")  # Play when screen appears
	time = time_spinbox.value
	time_changed.emit.call_deferred(time)

func setup_map_options(maps: Array[Map]):
	for map in maps:
		var scenarios: Array[Scenario] = map.get_scenarios()
		var map_button: Button = Button.new()
		map_button.text = map.map_name
		maps_v_box_container.add_child(map_button)
		for scenario in scenarios:
			if not OS.is_debug_build() and not scenario.released:
				continue
			var scenario_button: Button = Button.new()
			scenario_button.text = scenario.scenario_name
			maps_v_box_container.add_child(scenario_button)
			scenario_button.pressed.connect(_on_scenario_button_pressed.bind(scenario))
			scenario_button.mouse_entered.connect(_on_scenario_button_mouse_entered.bind(scenario))
			scenario_button.mouse_exited.connect(_on_scenario_button_mouse_exited)
			
			
func _on_scenario_button_mouse_entered(scenario: Scenario):
	scenario_description.text = scenario.scenario_description
	team.texture = team_texture[scenario.player_team]
	for victory_condition in scenario.victory_conditions:
		var label = Label.new()
		label.text = victory_condition.get_description()
		objectives_v_box_container.add_child(label)

func _on_scenario_button_mouse_exited():
	scenario_description.text = ""
	for label in objectives_v_box_container.get_children():
		label.queue_free()

func _on_scenario_button_pressed(scenario: Scenario):
	Globals.scenario_chosen = scenario
	animation_player.play("fade_out")
	await animation_player.animation_finished
	visible = false
	game_started.emit(scenario.player_team, Globals.game_mode)


func _on_set_objective_text(_hex: String):
	objective_label.text = "Hold objective (red circle) with an unbroken unit when the time runs out!"


func _on_start_as_axis_pressed():
	animation_player.play("fade_out")
	await animation_player.animation_finished
	visible = false
	game_started.emit(Globals.Team.AXIS, Globals.game_mode)


func _on_start_as_allies_pressed():
	animation_player.play("fade_out")
	await animation_player.animation_finished
	visible = false
	game_started.emit(Globals.Team.ALLIES, Globals.game_mode)


func _on_spin_box_value_changed(value: float) -> void:
	time = value
	SessionSettings.mission_time = value
	time_changed.emit(time)


func _on_start_as_axis_button_mouse_entered() -> void:
	hover_start_button.emit(0)


func _on_start_as_axis_button_mouse_exited() -> void:
	hover_start_button.emit(-1)


func _on_start_as_allies_button_mouse_entered() -> void:
	hover_start_button.emit(1)


func _on_start_as_allies_button_mouse_exited() -> void:
	hover_start_button.emit(-1)


func _on_attack_pressed() -> void:
	Globals.game_mode = Globals.GameMode.ATTACK
	game_mode_attack.text = "ATTACK"
	game_mode_defend.text = ""


func _on_defend_pressed() -> void:
	Globals.game_mode = Globals.GameMode.DEFEND
	game_mode_defend.text = "DEFEND"
	game_mode_attack.text = ""
