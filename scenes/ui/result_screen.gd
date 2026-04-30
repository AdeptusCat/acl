extends CanvasLayer

@export var victory_condition_result_scene: PackedScene

@onready var result_label := $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResultLabel
@onready var major_victory_conditions_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/VictoryConditionsVBoxContainer2/VBoxContainer2/MajorVictoryConditionsVBoxContainer
@onready var minor_objectives_label: Label = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/VictoryConditionsVBoxContainer2/VBoxContainer3/MinorObjectivesLabel
@onready var minor_victory_conditions_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/VictoryConditionsVBoxContainer2/VBoxContainer3/MinorVictoryConditionsVBoxContainer


signal try_again

func _on_show_winner(winner_team: int, outcome_level: VictoryCondition.OutcomeLevel = VictoryCondition.OutcomeLevel.MAJOR, timeout: bool = false):
	var outcome_level_text: String = ""
	match outcome_level:
		VictoryCondition.OutcomeLevel.MAJOR:
			outcome_level_text = "Major Victory"
		VictoryCondition.OutcomeLevel.MINOR:
			outcome_level_text = "Minor Victory"
	if winner_team == -1:
		result_label.text = "No one wins."
	elif winner_team == 0:
		result_label.text = "Team Axis wins a " + outcome_level_text + "!"
	elif winner_team == 1:
		result_label.text = "Team Allies wins a " + outcome_level_text + "!"
	
	if timeout and winner_team == -1:
		result_label.text = "Defeat by Timeout!"
	
	show()
	
	for victory_condition in Globals.scenario_chosen.victory_conditions:
		if not victory_condition.team == Globals.team_player:
			continue
		var victory_condition_result: VictoryConditionResult = victory_condition_result_scene.instantiate()
		match victory_condition.outcome_level:
			VictoryCondition.OutcomeLevel.MAJOR:
				major_victory_conditions_v_box_container.add_child(victory_condition_result)
			VictoryCondition.OutcomeLevel.MINOR:
				minor_victory_conditions_v_box_container.add_child(victory_condition_result)
				minor_objectives_label.show()
		victory_condition_result.set_victory_condition(victory_condition.is_condition_met(), victory_condition.get_description())
		#var label = Label.new()
		#label.text = victory_condition.get_description()
		#if victory_condition.outcome_level == VictoryCondition.OutcomeLevel.MAJOR:
			#major_victory_conditions_v_box_container.add_child(label)
		#if victory_condition.outcome_level == VictoryCondition.OutcomeLevel.MINOR:
			#minor_victory_conditions_v_box_container.add_child(label)
			#minor_objectives_label.show()

func _on_try_again_pressed() -> void:
	try_again.emit()


func _on_keep_playing_pressed() -> void:
	hide()
