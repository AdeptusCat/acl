class_name CampaignDefinition
extends Resource

@export var campaign_id: String = ""
@export var title: String = ""
@export var mission_maps: Array[PackedScene] = []


func install(container: Node) -> Array[Map]:
	var installed: Array[Map] = []
	var previous: Scenario
	for packed: PackedScene in mission_maps:
		var map: Map = packed.instantiate() as Map
		map.campaign_name = title
		container.add_child(map)
		var scenario: Scenario = map.get_scenario(0)
		scenario.campaign_id = campaign_id
		scenario.campaign_mission = installed.size() + 1
		scenario.previous_scenario = previous
		previous = scenario
		installed.append(map)
	return installed
