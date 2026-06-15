class_name ProjectionSourceBuilder
extends RefCounted


static func build_from_threat_axis(
	axis: ThreatAxis,
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	var sources: Array[ProjectionSource] = []

	if axis == null:
		return sources

	var projected_hexes: Array[Vector2i] = get_projected_line_hexes(
		objective,
		axis.source_hex,
		max_cells,
		skip_front,
		count
	)

	for observer_hex: Vector2i in projected_hexes:
		var source: ProjectionSource = ProjectionSource.new(
			null,
			observer_hex,
			1.0,
			1.0
		)

		sources.append(source)

	return sources


static func build_from_units(
	units: Array[Unit],
	objective: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[ProjectionSource]:
	var sources: Array[ProjectionSource] = []

	for unit: Unit in units:
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		var projected_hexes: Array[Vector2i] = get_projected_line_hexes(
			objective,
			unit.current_hex,
			max_cells,
			skip_front,
			count
		)

		var firepower: float = InfluenceUnitQuery.get_unit_firepower(unit)
		var effectiveness: float = InfluenceUnitQuery.get_unit_effectiveness(unit)

		for observer_hex: Vector2i in projected_hexes:
			var source: ProjectionSource = ProjectionSource.new(
				unit,
				observer_hex,
				firepower,
				effectiveness
			)

			sources.append(source)

	return sources


static func get_projected_line_hexes(
	from_hex: Vector2i,
	to_hex: Vector2i,
	max_cells: int,
	skip_front: int,
	count: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not is_instance_valid(LOSHelper.ground_layer):
		return result

	var from_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(from_hex)
	var to_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(to_hex)
	var line: Array[Vector3i] = LOSHelper.ground_layer.cube_linedraw(from_cube, to_cube)

	if line.is_empty():
		return result

	var start_index: int = skip_front
	if start_index < 0:
		start_index = 0

	var end_index: int = line.size()

	if max_cells > 0 and max_cells < end_index:
		end_index = max_cells

	if count > 0:
		var counted_end_index: int = start_index + count
		if counted_end_index < end_index:
			end_index = counted_end_index

	if start_index >= end_index:
		return result

	for index: int in range(start_index, end_index):
		var cube: Vector3i = line[index]
		var hex: Vector2i = LOSHelper.ground_layer.cube_to_map(cube)

		if hex == from_hex:
			continue

		if hex == Vector2i.ZERO:
			continue

		result.append(hex)

	return result
