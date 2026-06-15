# Influence Map Refactor

## File split

Core data and storage:
- `influence_map.gd` — map bounds, layers, composite rebuild, public compatibility wrappers.
- `influence_stamp.gd` — rectangular stamp data object.
- `unit_influence_gradient.gd` — unit gradient result object.

Influence map operations:
- `influence_map_layer_ops.gd` — write modes, array merge/multiply, positive masks.
- `influence_map_stamp_ops.gd` — radius stamp creation, stamp merging, stamp-to-full-map conversion.
- `influence_map_query_ops.gd` — max-value queries and gradient-neighbor queries.

Controller data objects:
- `influence_projection_config.gd` — tactical projection config.
- `projection_source.gd` — LOS/projection source data.
- `composite_term.gd` — composite recipe term data.
- `formation_group.gd` — front/flank group data.
- `formation_identification.gd` — front + flanks result.

Controller subsystems:
- `influence_map_controller.gd` — orchestration, update loop, map lifecycle, compatibility wrappers.
- `influence_unit_query.gd` — living-unit filtering and unit stat access.
- `projection_source_builder.gd` — projected line/axis source generation.
- `formation_analyzer.gd` — FRONT/FLANK identification.
- `los_influence_projector.gd` — friendly/enemy LOS layer projection and budgeted LOS processing.
- `defense_position_analyzer.gd` — pure objective/threat-axis defense position analysis.
- `defense_position_result.gd` — best-position analysis result object returned to PlatoonAI.
- `defense_position_planner.gd` — compatibility wrapper; no unit orders.

## Important API changes

- `InfluenceMap.InfluenceStamp` became `InfluenceStamp`.
- `InfluenceMap.UnitInfluenceGradient` became `UnitInfluenceGradient`.
- `substract_layer_value()` is kept as a compatibility alias, but new code uses `subtract_layer_value()`.
- `InfluenceMap.WriteMode.SUBSTRACT` is kept as a compatibility alias, but new code uses `InfluenceMap.WriteMode.SUBTRACT`.

## Behavior boundary

- `PlatoonAI` issues movement orders and mutates unit assignment state.
- Influence-map classes return analysis data only.
- `run_post_rebuild_tactical_tasks_with_threataxis()` has been replaced by `analyze_defense_positions_for_threat_axis(...)`.
- `create_maps()`, `rebuild_static_terrain_layers()`, `rebuild_dynamic_tactical_layers()`, `get_map_for_team()`, and `get_movement_weight()` remain available.

## Validation status

Godot is not installed in this sandbox, so the files were not compiler-checked inside Godot. The refactor was checked for balanced delimiters and obvious old nested-type references.
