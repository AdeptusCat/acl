class_name FormationAnalyzer
extends RefCounted

const FORMATION_GROUP_RADIUS: int = 3


static func identify_from_gradients(
	gradients: Array[UnitInfluenceGradient],
	best_gradient: UnitInfluenceGradient
) -> FormationIdentification:
	var result: FormationIdentification = FormationIdentification.new()

	if best_gradient == null:
		return result

	var assigned_units: Dictionary = {}
	var front_group: FormationGroup = FormationGroup.new(
		FormationGroup.Role.FRONT,
		best_gradient
	)

	result.front = front_group

	for gradient: UnitInfluenceGradient in gradients:
		if not is_valid_gradient(gradient):
			continue

		var distance_to_front: int = LOSHelper.get_hex_distance(
			gradient.from_hex,
			best_gradient.from_hex
		)

		if distance_to_front <= FORMATION_GROUP_RADIUS:
			add_gradient_to_group(front_group, gradient, assigned_units)

	var remaining_gradients: Array[UnitInfluenceGradient] = get_unassigned_gradients(
		gradients,
		assigned_units
	)

	while not remaining_gradients.is_empty():
		var flank_seed: UnitInfluenceGradient = InfluenceMapQueryOps.get_largest_gradient(
			remaining_gradients
		)

		if flank_seed == null:
			break

		var flank_group: FormationGroup = FormationGroup.new(
			FormationGroup.Role.FLANK,
			flank_seed
		)

		add_gradient_to_group(flank_group, flank_seed, assigned_units)

		for gradient: UnitInfluenceGradient in remaining_gradients:
			if not is_valid_gradient(gradient):
				continue

			if is_unit_assigned(gradient.unit, assigned_units):
				continue

			var distance_to_flank: int = LOSHelper.get_hex_distance(
				gradient.from_hex,
				flank_seed.from_hex
			)

			if distance_to_flank <= FORMATION_GROUP_RADIUS:
				add_gradient_to_group(flank_group, gradient, assigned_units)

		result.flanks.append(flank_group)

		remaining_gradients = get_unassigned_gradients(
			gradients,
			assigned_units
		)

	return result


static func add_gradient_to_group(
	group: FormationGroup,
	gradient: UnitInfluenceGradient,
	assigned_units: Dictionary
) -> void:
	if not is_valid_gradient(gradient):
		return

	if is_unit_assigned(gradient.unit, assigned_units):
		return

	group.gradients.append(gradient)
	group.units.append(gradient.unit)
	assigned_units[gradient.unit.get_instance_id()] = true


static func get_unassigned_gradients(
	gradients: Array[UnitInfluenceGradient],
	assigned_units: Dictionary
) -> Array[UnitInfluenceGradient]:
	var result: Array[UnitInfluenceGradient] = []

	for gradient: UnitInfluenceGradient in gradients:
		if not is_valid_gradient(gradient):
			continue

		if is_unit_assigned(gradient.unit, assigned_units):
			continue

		result.append(gradient)

	return result


static func is_valid_gradient(gradient: UnitInfluenceGradient) -> bool:
	if gradient == null:
		return false

	if gradient.unit == null:
		return false

	return true


static func is_unit_assigned(unit: Unit, assigned_units: Dictionary) -> bool:
	if unit == null:
		return false

	return assigned_units.has(unit.get_instance_id())
