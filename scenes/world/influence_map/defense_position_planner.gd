class_name DefensePositionPlanner
extends RefCounted


static func analyze_best_positions_for_config(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	reserved_hexes_by_unit: Dictionary = {}
) -> Array[DefensePositionResult]:
	return DefensePositionAnalyzer.analyze_best_positions_for_config(
		controller,
		config,
		reserved_hexes_by_unit
	)


static func analyze_best_positions_for_threat_axis(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	axis_units: Array[Unit],
	axis_enemy_units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	return DefensePositionAnalyzer.analyze_best_positions_for_threat_axis(
		controller,
		config,
		axis_units,
		axis_enemy_units,
		reserved_hexes_by_unit
	)
