extends Node

class UnitProbe extends Unit:
	func _make_squad() -> void:
		pass

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	var rifle: Unit = UnitProbe.new()
	rifle.squad_type = Globals.SquadType.Rifle
	var hq: Unit = UnitProbe.new()
	hq.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	var regular: StressController = StressController.new()
	var command: StressController = StressController.new()
	rifle.add_child(regular)
	hq.add_child(command)
	for stress: StressController in [regular, command]:
		stress.state = UnitStates.MoraleState.PANIC
		stress.stress_fast = 80.0
		stress.stress_slow = 80.0
		stress.S_eff = 80.0
		stress._process(1.0)
	_check(command.S_eff < regular.S_eff - 0.15, "Broken headquarters sheds stress faster than a broken rifle squad without an excessive panic advantage")
	_check(command._apply_recovery_bias(0.1) > regular._apply_recovery_bias(0.1), "Headquarters rallies faster after reaching the stress threshold")
	hq.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
	_check(command._is_headquarters(), "Company headquarters also receives command recovery")
	command.cohesion = 0.3
	_check(command._apply_recovery_bias(0.1) < regular._apply_recovery_bias(0.1), "Poor cohesion can outweigh the headquarters rally advantage")
	command.cohesion = 1.0
	var baseline: float = command._situational_recovery_multiplier()
	command.on_casualty_event(1)
	var one_loss: float = command._situational_recovery_multiplier()
	_check(one_loss < baseline, "Recent casualties slow recovery")
	_check(is_equal_approx(command.casualty_recovery_window_s, 120.0), "Casualty recovery shock fades over two minutes")
	command.on_casualty_event(1, true)
	_check(command._situational_recovery_multiplier() < one_loss, "Additional casualties and leader loss deepen recovery shock")
	command._casualty_recovery_t *= 0.5
	_check(command._situational_recovery_multiplier() > command.casualty_recovery_slowdown, "Casualty shock fades over its recovery window")
	command._casualty_recovery_t = 0.01
	command._process(0.02)
	_check(is_equal_approx(command._situational_recovery_multiplier(), baseline), "Recovery returns to baseline when casualty shock expires")
	command.mark_under_fire(1.0)
	var light: float = command._situational_recovery_multiplier()
	command.mark_under_fire(command.pressure_ref_rps)
	var heavy: float = command._situational_recovery_multiplier()
	_check(heavy < light and light < baseline, "Incoming pressure slows both light and heavy fire recovery")
	command._under_fire_t = 0.0
	_check(is_equal_approx(command._situational_recovery_multiplier(), baseline), "Fire slowdown expires with existing pressure tracking")
	command.add_leadership_source(1, 0.1, 0.1, 1.2)
	command.add_leadership_source(1, 0.1, 0.1, 1.2)
	_check(is_equal_approx(command.cohesion, 1.0) and is_equal_approx(command._situational_recovery_multiplier(), 1.2), "Leadership cohesion does not compound on repeated updates")
	command.remove_leadership_source(1)
	_check(is_equal_approx(command._situational_recovery_multiplier(), baseline), "Removing leadership restores base cohesion recovery")
	var stats: UnitCombatStats = UnitCombatStats.new()
	stats.setup(hq)
	hq.stress_system = command
	stats.notify_casualty_taken(1)
	stats._update_temporary_penalties(4.0)
	_check(is_equal_approx(stats.recent_casualty_shock, 0.096), "Displayed single-casualty shock is 9.6 percent after four seconds")
	stats._update_temporary_penalties(6.0)
	_check(is_equal_approx(stats.recent_casualty_shock, 0.06), "Displayed single-casualty shock is half recovered after ten seconds")
	stats._update_temporary_penalties(10.0)
	_check(is_zero_approx(stats.recent_casualty_shock), "Displayed single-casualty shock clears after twenty seconds")
	var connectivity: CommandConnectivity = CommandConnectivity.new()
	hq.add_child(connectivity)
	hq.command_connectivity = connectivity
	connectivity.leader_presence_strength = 0.5
	stats.notify_casualty_taken(1)
	stats._update_temporary_penalties(10.0)
	_check(is_equal_approx(stats.recent_casualty_shock, 0.03), "Partial leadership proportionally accelerates casualty shock recovery")
	stats.recent_casualty_shock = 0.0
	connectivity.leader_presence_strength = 1.0
	stats.notify_casualty_taken(1)
	stats._update_temporary_penalties(10.0)
	_check(is_zero_approx(stats.recent_casualty_shock), "Full leadership clears a single casualty shock in ten seconds")
	connectivity.leader_presence_strength = 0.0
	stats.notify_casualty_taken(1)
	stats._update_temporary_penalties(10.0)
	_check(is_equal_approx(stats.recent_casualty_shock, 0.06), "Losing leadership restores the twenty-second baseline")
	stats.free()
	rifle.free()
	hq.free()
	print("Stress recovery checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
