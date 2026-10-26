@tool
extends RefCounted
class_name ReinforcementAuthoring


static func collect_changes(node: Node, changes: Array[Dictionary]) -> void:
	if node is Scenario:
		var units: Node = node.get_node_or_null("Units")
		var ids: Dictionary[String, Unit] = {}
		if units != null:
			for child: Node in units.get_children():
				if not child is Unit:
					continue
				var unit: Unit = child as Unit
				var id: String = unit.map_unit_id
				if id.is_empty() or ids.has(id):
					id = new_id()
					changes.append({"object": unit, "property": "map_unit_id", "value": id})
				ids[id] = unit
		var branch: Node = node.get_node_or_null("Reinforcements")
		var claimed: Dictionary[String, bool] = {}
		var group_ids: Dictionary[String, bool] = {}
		if branch != null:
			for child: Node in branch.get_children():
				if not child is ReinforcementDefinition:
					continue
				var definition: ReinforcementDefinition = child as ReinforcementDefinition
				var group_id: String = definition.reinforcement_id
				if group_id.is_empty() or group_ids.has(group_id):
					group_id = new_id()
					changes.append({"object": definition, "property": "reinforcement_id", "value": group_id})
				group_ids[group_id] = true
				var clean: PackedStringArray = []
				for id: String in definition.unit_ids:
					if ids.has(id) and not claimed.has(id) and ids[id].team == definition.team:
						clean.append(id)
						claimed[id] = true
				if clean != definition.unit_ids:
					changes.append({"object": definition, "property": "unit_ids", "value": clean})
	for child: Node in node.get_children():
		collect_changes(child, changes)


static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


