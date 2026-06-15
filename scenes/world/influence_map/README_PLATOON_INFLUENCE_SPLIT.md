# Platoon AI / Influence Map Split

## Ownership boundary

`PlatoonAI` owns command decisions and unit mutation:

- assigns squads to reserve, objective defense, or threat-axis defense
- keeps the planned reservation dictionary
- receives best-position analysis results
- calls `squad.order(...)`
- updates `squad.best_index`
- assigns `squad.influence_map` debug score maps

Influence-map logic owns spatial analysis only:

- builds threat axes from current formation analysis
- builds influence projection configs
- calculates best defensive hexes
- returns `DefensePositionResult` objects
- does not call `unit.order(...)`
- does not mutate controller-level reserved hexes

## New files

- `defense_position_analyzer.gd`
  - Pure best-position analysis.
  - Replaces command-emitting behavior from the old planner.

- `defense_position_result.gd`
  - Result DTO returned to `PlatoonAI`.
  - Contains unit, role, axis, target hex, target index, score, previous score, should_move, and score_map.

- `README_PLATOON_INFLUENCE_SPLIT.md`
  - This note.

## Changed files

- `platoon_ai.gd`
  - No longer builds `ThreatAxis` objects from formation data directly.
  - No longer contains fake local hex scoring stubs.
  - Calls `InfluenceMapController.get_sorted_threat_axes_for_team(...)`.
  - Calls `InfluenceMapController.analyze_defense_positions_for_threat_axis(...)`.
  - Calls `InfluenceMapController.analyze_objective_defense_positions(...)`.
  - Issues all movement orders itself.

- `influence_map_controller.gd`
  - Exposes analysis methods for `PlatoonAI`.
  - Converts formation groups into sorted `ThreatAxis` objects.
  - Delegates best-position scoring to `DefensePositionAnalyzer`.
  - No longer owns a tactical `reserved_hexes` dictionary.
  - No longer runs post-rebuild unit movement tasks.

- `defense_position_planner.gd`
  - Kept as a compatibility wrapper.
  - It forwards analysis calls to `DefensePositionAnalyzer`.
  - It no longer issues orders.

## New flow

1. `PlatoonAI.reconsider_assignments()` selects available squads.
2. `PlatoonAI` asks `InfluenceMapController` for sorted threat axes.
3. `PlatoonAI` distributes squads over axes.
4. `PlatoonAI` passes assigned squads and reserved hexes to influence analysis.
5. `DefensePositionAnalyzer` returns `DefensePositionResult` objects.
6. `PlatoonAI` stores assignments and issues movement commands.

## Critical rule

No influence-map class should call `unit.order(...)`.
