# Code organization refactor plan

Status: implemented on 6 October 2026 after authorization to execute the plan. Both folder moves and filename renames are complete. The tables retain the original paths and intermediate Task 1 names; consult the [manifest](code_refactor_manifest.json) for paths at the end of this refactor and the [execution results](code_organization_refactor_results.md) for verification and limitations. A subsequent [faction-folder migration](faction_folder_naming_proposal.md) establishes the current country folder names.

## Scope and order

1. **Task 1: move files into folders that reflect their responsibilities.** Keep existing filenames and public names during this task.
2. **Task 2: rename files to explain what they do.** Start only after the folder moves have been verified.

The intended result is easier navigation without changes to gameplay, save formats, scene structure, or controller behavior. Splitting large scripts, changing algorithms, removing implementations, and renaming public methods or exported properties are separate work.

## Findings that shape the plan

- The root contains runtime AI, influence-map scenes, loadout catalogs, save resources, and commented reference implementations.
- `ai/platoon_alternative/platoon_ai.gd` declares `PlatoonAI` and assigns squads to defensive positions using influence-map results. The world scene instantiates it for both teams. Its folder name does not describe its role.
- `ai/platoon/platoon_ai_controller.gd` declares `PlatoonAiController` and contains tactical-phase and task planning. `scenes/world/world.tscn` instantiates it in two scenarios and sets `is_active = true` in the Orchard Road Outpost Probe scenario, but an unconditional return at the start of `_physics_process()` disables its decision loop. Preserve it as a scene dependency; its presence does not establish active AI behavior. See the [controller investigation](phased_controller_investigation.md).
- `EnemyTrack` is used by the game controller, and `SquadTacticalState` is used by `Unit`. These are shared runtime types, not files to archive with an older controller.
- Root `influence_map.gd`, `influence_map_controller.gd`, and `platoon_ai.gd` contain only commented-out code. The actual influence-map classes are under `scenes/world/influence_map/`.
- `scenes/ui/` mixes screens, panels, labels, command wheels, and effects. `unit_status.gd` also exists under the unit folder, where it manages status images rather than a tooltip label.
- `SoldierLoadout` belongs with authored soldier resources and is also used for persistence. `Units` and `UnitsCollection` hold runtime unit references used by victory conditions and global state.
- Save loading uses `UnitSaveData.unit_scene_path` and `SoldierLoadout.weapon_resource_path` as strings. LOS files are loaded and written using a directory string and a filename derived from `map.map_name`.

## Organization rules

- Retain the established top-level `autoloads/`, `ai/`, `scenes/`, `resources/`, `assets/`, `tests/`, and `docs/` layout.
- Keep reusable scenes beside their scripts. Move related `.gd`, `.tscn`, and `.gd.uid` files together where applicable; preserve their UIDs.
- Put instantiated game components under `scenes/`, authored resource definitions under `resources/`, and AI planning/perception types under `ai/`.
- Keep shared types outside either specific platoon implementation.
- Use a feature's folder for its data objects and helpers. Avoid catch-all folders such as `misc/` or `utils/`.
- Keep comments-only snapshots under `sources/archive/`, which the existing convention checker already excludes. Archive files only after checking references, including UID references.
- Leave descriptive files in sensible locations alone.

## Task 1: folder moves

### Folder layout (before Task 2 renames)

```text
autoloads/                         Registered global services
ai/
  orders/                         Squad and mission order types
  perception/                     Shared enemy tracking
  squad/                          Squad AI and tactical state
  platoon/
    defense/                      Influence-based defense assignment
    phased/                       Tactical phases, blackboard, and tasks
    platoon_types.gd               Types shared with perception/squad state
scenes/
  main.gd, main.tscn               Entry point, retained
  game/
    game_controller.*             Match orchestration, renamed in Task 2
    input/                        Input collection and signals
    combat/                       Close-combat encounters
    units/
      unit.gd, unit.tscn           Unit root, retained
      actions/                    Order execution and action transitions
      movement/                   Unit movement
      combat/                     Firing, combat stats, and stress
      command/                    Leadership and command connectivity
      visibility/                 Unit visibility component
      presentation/               Battlefield unit visuals
      soldiers/                   Runtime soldiers and their tasks
      collections/                Runtime unit collections
    audio/                        Existing audio scenes, retained
    effects/                      Existing gameplay effects, retained
  world/
    world.gd, world.tscn           World composition, retained
    camera/                       Camera controls
    maps/
      layers/                     Ground, terrain, wall, and building layers
    overlays/                     Tactical lines and scenario preview
    influence_map/
      influence_map_controller.*  Controller script and scene together
      core/                       Map representation and composites
      operations/                 Existing map operations, retained
      projection/                 LOS projection and rebuild data
      formations/                 Formation analysis and data
      defense/                    Defense planning and threat axes
      layers/                     Specialized influence layers
      debug/                      Influence-map visualization
  scenarios/                      Scenario scene/script and objective types
  ui/
    hud/                          Main battle UI and countdown
    screens/                      Scenario selection and match results
    panels/                       Settings and debug options
    units/                        Unit and soldier detail widgets
    tiles/                        Tile detail widgets
    orders/                       Command wheels and rout button
    tooltips/                     Shared tooltip
    effects/                      UI indicators and glow effect
resources/
  squads/                         Loadout types, faction catalogs, definitions
  soldiers/                       Soldier loadout type and definitions
  saves/                          Match, unit, and soldier save types
  los/                            Lookup resource type and baked data
  casualties/                     Existing history resources, retained
  weapons/                        Existing definitions and type, retained
  theme/, styles/                 Existing UI resources, retained
tests/                            Existing regression entry points, retained
  manual/                         Development scenes and diagnostics
docs/
  design/ai/                      AI design notes
sources/archive/                  Preserved commented reference code
```

### Move batch 1: loose resources and autoload implementations

Paths in the tables are relative to the project root. A grouped filename denotes each listed file, not an entire folder. Include `.gd.uid` companions for every script move.

| Current file(s) | Task 1 destination | Responsibility / dependency |
| --- | --- | --- |
| `squad_loadout_spec.gd`, `squads.gd`, `squads_collection.gd` | `resources/squads/`, same filenames | Authored squad loadouts and lookup catalogs. |
| `squads_collection.tres` | `resources/squads/squads_collection.tres` | Catalog joining the faction catalogs. |
| `squads_german.tres` | `resources/squads/german/squads_german.tres` | German squad catalog beside German definitions. |
| `squads_us.tres` | `resources/squads/us/squads_us.tres` | US squad catalog beside US definitions. |
| `scenes/game/units/soldier_loadout.gd` | `resources/soldiers/soldier_loadout.gd` | Authored soldier configuration and saved roster entries. Requires persistence verification. |
| `match_save_data.gd`, `unit_save_data.gd`, `soldier_save_data.gd` | `resources/saves/`, same filenames | Serialized save types. Preserve fields and class names; check old saves before release. |
| `threat_map.gd`, `threat_map.tscn` | `autoloads/`, same filenames | Registered global threat-map service. |
| `scenes/game/los/los_helper.gd`, `scenes/game/los/los_helper.tscn` | `autoloads/`, same filenames | Registered `LOSHelper` service, currently stored among LOS data. |
| `scenes/game/los/los_lookup_data.gd` | `resources/los/los_lookup_data.gd` | Lookup resource schema. |
| `scenes/game/los/default_map.tres`, `orchard_road.tres`, `los_data.tres` | `resources/los/`, same filenames | Baked lookup data. Update both directory strings in `LOSHelper` in the same batch. Check the purpose of `los_data.tres`; preserve it regardless. |
| `autoloads/rolls_stats.gd` | `tests/manual/rolls_stats.gd` | Roll-distribution diagnostic; not registered in `project.godot`. Retain `RollStats` and check UID consumers before moving. |

Keep `unit.tscn` and weapon `.tres` paths stable in these two tasks. They are recorded in saved data. Do not use this folder cleanup to reorganize weapon assets.

### Move batch 2: AI ownership

| Current file(s) | Task 1 destination | Responsibility / dependency |
| --- | --- | --- |
| `ai_order.gd`, `mission_order.gd` | `ai/orders/`, same filenames | Squad orders and platoon mission orders. |
| `ai/platoon_alternative/platoon_ai.gd`, `platoon_ai.tscn` | `ai/platoon/defense/`, same filenames | Influence-based squad assignment; preserve `PlatoonAI`. |
| `defense_director.gd`, `defense_director.tscn` | `ai/platoon/defense/`, same filenames | Creates and delivers defensive mission orders. |
| `ai/platoon/platoon_ai_controller.gd`, `platoon_ai_controller.tscn` | `ai/platoon/phased/`, same filenames | Phase-based controller still referenced by authored scenarios. |
| `ai/platoon/platoon_blackboard.gd`, `platoon_task.gd`, `suspected_enemy_zone.gd` | `ai/platoon/phased/`, same filenames | Blackboard, phase tasks, and suspected-zone reasoning. |
| `ai/platoon/enemy_track.gd` | `ai/perception/enemy_track.gd` | Shared enemy observation and confidence. |
| `ai/platoon/squad_tactical_state.gd` | `ai/squad/squad_tactical_state.gd` | Tactical state used by units and platoon reasoning. |
| `scenes/game/units/squad_ai_controller.gd` | `ai/squad/squad_ai_controller.gd` | AI decision making and execution of `AiOrder`. |

Keep `ai/platoon/platoon_types.gd` at its existing path: both shared types and phased reasoning use it. Update the convention checker's excluded-controller path when moving the phase-based controller; keep its existing coverage policy during this cleanup. The controller remains a dormant prototype referenced by scenes; scene references alone do not establish whether it should be developed or retired.

### Move batch 3: influence-map subsystem

All abbreviated source paths in this table are below `scenes/world/influence_map/` unless identified as root files.

| Current file(s) | Task 1 destination | Responsibility |
| --- | --- | --- |
| `controller_subsystems/influence_map_controller.gd` and root `influence_map_controller.tscn` | `scenes/world/influence_map/`, same filenames | Put the active controller and its scene together. |
| Root `influence_map_debug_draw.gd`, `influence_map_debug_draw.tscn` | `scenes/world/influence_map/debug/`, same filenames | Influence-layer visualization. |
| `controller_data_objects/composite_term.gd`, `threat_axis_composite.gd` | `scenes/world/influence_map/core/`, same filenames | Composite-map configuration and data. |
| `controller_subsystems/los_influence_projector.gd`, `projection_source_builder.gd`, `influence_unit_query.gd` | `scenes/world/influence_map/projection/`, same filenames | Source selection and LOS-based projection. |
| `controller_data_objects/projection_source.gd`, `influence_projection_config.gd`, `los_rebuild_job.gd` | `scenes/world/influence_map/projection/`, same filenames | Projection configuration and rebuild state. |
| `controller_subsystems/formation_analyzer.gd` and `controller_data_objects/formation_group.gd`, `formation_identification.gd` | `scenes/world/influence_map/formations/`, same filenames | Formation detection and grouping. |
| `controller_subsystems/defense_position_analyzer.gd`, `defense_position_planner.gd`, `defense_position_result.gd`, and root `threat_axis.gd` | `scenes/world/influence_map/defense/`, same filenames | Threat-axis data and defense-position selection. |
| `hq_support_need/hq_support_need_layer.gd` | `scenes/world/influence_map/layers/hq_support_need_layer.gd` | Specialized influence layer. |

Keep existing `core/influence_map.gd`, `core/influence_stamp.gd`, `core/unit_influence_gradient.gd`, and every file under `operations/` in place. The generic `controller_data_objects/` and `controller_subsystems/` folders become unnecessary after their contents move.

### Move batch 4: world and gameplay components

| Current file(s) | Task 1 destination | Responsibility |
| --- | --- | --- |
| `scenes/game/input_manager.gd`, `input_manager.tscn` | `scenes/game/input/`, same filenames | Input handling. |
| `scenes/game/close_combat_instance.gd`, `close_combat_instance.tscn` | `scenes/game/combat/`, same filenames | Close-combat encounter simulation. |
| `scenes/game/maps/map.gd`, `map.tscn` | `scenes/world/maps/`, same filenames | Map composition and scenario lookup. |
| `scenes/game/maps/ground_tile_map_layer.gd`, `ground_tile_map_layer.tscn`, `terrain_tile_map_layer.gd`, `wall_tile_map_layer.gd`, `building_tile_map_layer.gd`, `enums.gd` | `scenes/world/maps/layers/`, same filenames | Hex terrain layers and their terrain enum. |
| `scenes/game/maps/scenario.gd`, `scenario.tscn` | `scenes/scenarios/`, same filenames | Scenario units, objectives, and victory conditions. |
| `scenes/world/camera_2d.gd` | `scenes/world/camera/camera_2d.gd` | Camera movement, zoom, and map limits. |
| `scenes/game/los_renderer.gd`, `los_renderer.tscn`, `scenes/world/command_connectivity_renderer.gd`, `target_area.gd` | `scenes/world/overlays/`, same filenames | Tactical lines, command links, and faction preview areas. |
| `scenes/game/units/soldier.gd`, `soldier_task.gd` | `scenes/game/units/soldiers/`, same filenames | Runtime soldiers and task lifetime. |
| `scenes/game/units/units.gd`, `units_collection.gd` | `scenes/game/units/collections/`, same filenames | Runtime unit lists grouped by team. |
| `scenes/game/units/squad_action_controller.gd`, `squad_action_controller.tscn` | `scenes/game/units/actions/`, same filenames | State transitions and player/AI order execution. |
| `scenes/game/units/unit_movement.gd`, `unit_movement.tscn` | `scenes/game/units/movement/`, same filenames | Path following and arrival handling. |
| `scenes/game/units/squad_fire_controller.gd`, `squad_fire_controller.tscn`, `squad_fire_calculator.gd`, `unit_combat_stats.gd`, `unit_stress_controller.gd`, `unit_stress_controller.tscn` | `scenes/game/units/combat/`, same filenames | Firing, crew allocation, combat effectiveness, and morale/stress. |
| `scenes/game/units/command_connectivity.gd`, `command_connectivity.tscn`, `leader_aura.gd`, `leader_aura.tscn` | `scenes/game/units/command/`, same filenames | Command links and leadership effects. |
| `scenes/game/units/enemy_visibility_checker.gd`, `enemy_visibility_checker.tscn` | `scenes/game/units/visibility/`, same filenames | Unit visibility component. |
| `scenes/game/units/unit_ui.gd`, `unit_ui.tscn`, `unit_status.gd` | `scenes/game/units/presentation/`, same filenames | Battlefield unit displays and status images. |

`scenes/world/map.gd` is a one-line `extends Node2D` script, distinct from the actual `Map` class. Check references before assigning it a permanent role; see the development-file review below.

### Move batch 5: UI by function

All sources in this table are currently directly under `scenes/ui/`, except root `glow_marker.gd`. Each listed file moves with its existing name.

| Files | Task 1 destination | Responsibility |
| --- | --- | --- |
| `ui.gd`, `ui.tscn`, `countdown.gd` | `scenes/ui/hud/` | Battle HUD and remaining match time. |
| `start_screen.gd`, `start_screen.tscn`, `result_screen.gd`, `result_screen.tscn`, `victory_condition_result.gd`, `victory_condition_result.tscn` | `scenes/ui/screens/` | Scenario selection, match outcome, and result rows. |
| `settings.gd`, `debug.gd` | `scenes/ui/panels/` | Settings and debug controls embedded in the UI scene. |
| `unit_details.gd`, `unit_stats_details.gd`, `UnitStatsDetails.tscn`, `soldier_detail.gd`, `soldier_detail.tscn`, `soldier_detail_label.tscn`, `soldier_detail_progress_bar.tscn`, `soldiers_grid_container.gd`, `unit_status.gd`, `unit_type.gd`, `leadership_bonus.gd` | `scenes/ui/units/` | Unit detail panels, soldier entries, and tooltip labels. |
| `tile_details.gd`, `tile_stats.gd`, `tile_textures.gd` | `scenes/ui/tiles/` | Selected-tile information and preview. |
| `selection_wheel.gd`, `selection_wheel.tscn`, `selection_wheel_alt.tscn`, `wheel_option.gd`, `rout_button.gd` | `scenes/ui/orders/` | Unit command selection and rout control. |
| `tooltip.gd` | `scenes/ui/tooltips/` | Shared tooltip display. |
| `glow_marker.tscn`, `cover_icon.tscn`, `close_combat_sign.tscn`, and root `glow_marker.gd` | `scenes/ui/effects/` | UI indicators and transient glow effect. |

Many UI scripts attach to nodes inside `ui.tscn`; no standalone scenes need to be created for them. File organization does not require changing that scene's node hierarchy.

### Move batch 6: references and development files

| Current file(s) | Proposed destination | Condition |
| --- | --- | --- |
| Root `influence_map.gd`, `influence_map_controller.gd` | `sources/archive/influence_map/`, same filenames | Comments-only snapshots; confirm no resource or UID consumers before archiving. |
| Root `platoon_ai.gd` | `sources/archive/ai/platoon_ai.gd` | Comments-only snapshot; distinct from both executable controllers. |
| `AI.odt`, `phase_evaluation` | `docs/design/ai/`, same filenames | Existing design document and phase-planning notes. |
| `hexagon_tile_map_layer_test.tscn` | `tests/manual/maps/hexagon_tile_map_layer_test.tscn` | Development tilemap scene; preserve referenced assets. |
| `scenes/world/node_2d.gd` | `tests/manual/audio/node_2d.gd` | Stereo/panning diagnostic. Locate any companion scene or UID consumers first. |
| `scenes/game/los/draw_los.gd` | `tests/manual/los/draw_los.gd` | Contains LOS sampling plus interactive drawing; no direct path consumer was found. Confirm intended use and scene attachment before moving. |
| `scenes/world/formation_ai_controllers.tscn` | `tests/manual/ai/formation_ai_controllers.tscn` | Minimal placeholder scene; no direct path consumer was found. Confirm UID consumers first. |
| `scenes/world/map.gd` | `sources/archive/world/map.gd`, if confirmed unused | Empty script, not the real `Map` implementation. Keep its path until usage is settled. |

Inventory `.tmp`, `.zip`, `.tar.gz`, and editor backup files separately. Preserve anything needed; confirmed development archives can be grouped under `sources/archive/`. Their disposition is optional follow-up, not permission to delete them. Existing assets, third-party `addons/`, export tooling, and regression scene paths stay outside the move batches.

### Task 1 execution checklist

- [x] Record an explicit old-path → new-path manifest for the batch, including companions and UID-only references.
- [x] Establish the existing import/parser, regression, and smoke-test baseline in an isolated copy with isolated user data.
- [x] Move one batch at a time, preserving filenames, class names, singleton names, UIDs, and scene node names.
- [x] Update `res://` paths in scripts, `.tscn`, `.tres`, `project.godot`, tests, and relevant documentation. For UID-based references, verify resolution from a fresh import.
- [x] Update dynamically constructed LOS paths, including both load and bake/save paths. Keep `default_map.tres` and `orchard_road.tres` names aligned with map names.
- [x] Update the convention checker exclusion for the moved phased controller. Keep the exclusion limited to that existing controller.
- [x] Verify representative pre-move save files in a fresh process. Preserve a legacy-path mapping or compatibility resource if an old serialized script/resource path cannot resolve; do not accept silent equipment fallback as compatibility.
- [x] Complete relevant import, regression, persistence, and headless smoke checks before the next batch. Interactive visual inspection remains unperformed.

**Task 1 is complete when:** the manifest is implemented, every affected scene/resource resolves after a fresh import, both platoon implementations remain wired to their existing scenarios, and persistence/regression behavior matches the baseline.

## Task 2: names that explain responsibilities

### Naming rules

- Use lowercase `snake_case` for project-owned filenames and folders.
- Prefer a concrete role: `*_panel`, `*_label`, `*_overlay`, `*_controller`, `*_catalog`, or `*_data` only when that role fits the implementation.
- Match a scene's basename to its script where there is one shared component. Scene variants may have a more specific basename while using the same script.
- Use domain qualifiers to distinguish files that currently share a vague name.
- Rename filenames first. Keep existing `class_name` declarations, autoload keys, node names, signals, properties, and save fields during these two tasks. Aligning public identifiers later is a separate, more invasive change.
- Retain established acronyms such as `los`, `hq`, and `ui` where their meaning is clear from the domain.

### Rename batch 1: runtime roles and data catalogs

The current paths below are the destinations after Task 1.

| After Task 1 | Proposed filename(s) | Why |
| --- | --- | --- |
| `ai/platoon/defense/platoon_ai.gd`, `platoon_ai.tscn` | `platoon_defense_controller.gd`, `platoon_defense_controller.tscn` | Assigns defensive positions and reserves using influence maps. |
| `ai/platoon/defense/defense_director.gd`, `defense_director.tscn` | `defense_mission_director.gd`, `defense_mission_director.tscn` | Constructs and delivers the initial defensive mission. |
| `ai/platoon/phased/platoon_ai_controller.gd`, `platoon_ai_controller.tscn` | `platoon_phase_controller.gd`, `platoon_phase_controller.tscn` | Runs tactical phases, plans, and squad-role assignments. Update the exact checker exclusion again. |
| `ai/orders/ai_order.gd` | `squad_ai_order.gd` | Order consumed by squad AI; distinct from a platoon mission. |
| `ai/orders/mission_order.gd` | `platoon_mission_order.gd` | Objective, sector, fallback, threat axes, and reserve policy. |
| `resources/squads/squads.gd` | `squad_loadout_catalog.gd` | Maps squad type to loadout. |
| `resources/squads/squads_collection.gd` | `team_squad_loadout_catalog.gd` | Maps team to its squad-loadout catalog. |
| `resources/squads/squads_collection.tres` | `team_squad_loadout_catalog.tres` | Authored instance of the team catalog. |
| `resources/squads/german/squads_german.tres`, `resources/squads/us/squads_us.tres` | `squad_loadout_catalog.tres` in each faction folder | Folder identifies the faction; basename identifies the resource role. |
| `scenes/game/units/collections/units.gd` | `unit_list.gd` | Runtime list of unit references. |
| `scenes/game/units/collections/units_collection.gd` | `team_unit_lists.gd` | Runtime unit lists indexed by team, not an authored squad catalog. |
| `scenes/game/game_controller.gd`, `game_controller.tscn` | `match_controller.gd`, `match_controller.tscn` | Match setup, units, objectives, clock, visibility, and results. |
| `autoloads/los_helper.gd`, `los_helper.tscn` | `los_service.gd`, `los_service.tscn` | Provides LOS queries, geometry, lookup data, and baking. Keep the autoload key `LOSHelper`. |
| `autoloads/los.gd` | `unit_visibility_system.gd` | Updates enemy visibility for units. Keep the autoload key `LOS`. |
| `autoloads/globals.gd` | `game_globals.gd` | Aligns filename with the existing `GameGlobals` class. Keep the autoload key `Globals`. |
| `autoloads/debug.gd` | `debug_settings.gd` | Holds debug flags and queued debug actions. Keep the autoload key `Debug`. |
| `scenes/world/camera/camera_2d.gd` | `battle_camera.gd` | Implements battle camera movement, limits, and zoom. |
| `scenes/world/overlays/los_renderer.gd`, `los_renderer.tscn` | `tactical_lines_overlay.gd`, `tactical_lines_overlay.tscn` | Draws LOS, movement, chain-of-command, and link-strength lines. |
| `scenes/world/overlays/target_area.gd` | `scenario_start_area_preview.gd` | Switches faction areas when hovering over scenario start options. |
| `scenes/world/maps/layers/enums.gd` | `terrain_types.gd` | Contains `TerrainType`, rather than general project enums. |
| `scenes/game/units/presentation/unit_ui.gd`, `unit_ui.tscn` | `unit_battlefield_view.gd`, `unit_battlefield_view.tscn` | Battlefield visuals and status display, distinct from detail panels. |
| `scenes/game/units/presentation/unit_status.gd` | `unit_status_icons.gd` | Selects status images by team and squad type. |
| `scenes/game/effects/moving_dotted_line.gd`, `moving_dotted_line.tscn` | `movement_path_line.gd`, `movement_path_line.tscn` | Visualizes a unit's movement line. |

Keep `unit.gd`, `soldier.gd`, `soldier_task.gd`, `squad_action_controller.gd`, `squad_fire_controller.gd`, `squad_fire_calculator.gd`, `unit_movement.gd`, `unit_combat_stats.gd`, `unit_stress_controller.gd`, save-data filenames, and descriptive influence-map filenames. Renaming them adds little clarity compared with placing them in the right folder.

### Rename batch 2: UI components

| After Task 1 | Proposed filename(s) | Why |
| --- | --- | --- |
| `scenes/ui/hud/ui.gd`, `ui.tscn` | `battle_hud.gd`, `battle_hud.tscn` | UI shown during a match. |
| `scenes/ui/hud/countdown.gd` | `match_countdown_panel.gd` | Displays and animates remaining match time. |
| `scenes/ui/screens/start_screen.gd`, `start_screen.tscn` | `scenario_selection_screen.gd`, `scenario_selection_screen.tscn` | Selects map/scenario, faction, time, and attack/defend mode. |
| `scenes/ui/screens/result_screen.gd`, `result_screen.tscn` | `match_result_screen.gd`, `match_result_screen.tscn` | Match outcome and restart/continue actions. |
| `scenes/ui/screens/victory_condition_result.gd`, `victory_condition_result.tscn` | `victory_condition_result_row.gd`, `victory_condition_result_row.tscn` | One condition's status and description. |
| `scenes/ui/panels/settings.gd`, `debug.gd` | `settings_panel.gd`, `debug_panel.gd` | Distinguishes UI controls from autoload settings/state. |
| `scenes/ui/units/unit_details.gd` | `unit_details_panel.gd` | Selected-unit details and controls. |
| `scenes/ui/units/unit_stats_details.gd`, `UnitStatsDetails.tscn` | `unit_stats_summary.gd`, `unit_stats_summary.tscn` | Small firepower/range/morale summary; also fixes scene filename casing. Preserve it pending a separate usage review. |
| `scenes/ui/units/soldier_detail.gd`, `soldier_detail.tscn` | `soldier_details_row.gd`, `soldier_details_row.tscn` | A single soldier's details and readiness progress. |
| `scenes/ui/units/soldiers_grid_container.gd` | `soldier_roster_grid.gd` | Builds the selected unit's soldier display. |
| `scenes/ui/units/unit_status.gd`, `unit_type.gd`, `leadership_bonus.gd` | `unit_status_label.gd`, `unit_type_label.gd`, `leadership_bonus_label.gd` | Tooltip labels, distinct from unit status icons. |
| `scenes/ui/tiles/tile_details.gd`, `tile_stats.gd`, `tile_textures.gd` | `tile_details_panel.gd`, `tile_cover_overlay.gd`, `tile_texture_preview.gd` | Panel, cover/hindrance indicators, and enlarged tile texture display. |
| `scenes/ui/orders/selection_wheel.gd` | `unit_command_wheel.gd` | Shared command-selection implementation. |
| `scenes/ui/orders/selection_wheel_alt.tscn` | `unit_command_wheel.tscn` | Currently used move/fire/stop command wheel. |
| `scenes/ui/orders/selection_wheel.tscn` | `move_fire_command_wheel.tscn` | Variant containing move and fire commands without stop. |
| `scenes/ui/orders/wheel_option.gd` | `unit_command_wheel_option.gd` | Command option resource used by the wheel. |
| `scenes/ui/effects/close_combat_sign.tscn` | `close_combat_indicator.tscn` | Indicator for close combat. |

Both command-wheel scenes use the same script. `selection_wheel_alt.tscn` is the one instantiated by the current UI and includes move, fire, and stop commands plus a no-command option. The other scene has move and fire commands plus a no-command option. The proposed names reflect those inspected option lists. Preserve both variants; `_alt` does not mean unused.

### Rename batch 3: diagnostics and references

| After Task 1 | Proposed filename | Why |
| --- | --- | --- |
| `tests/manual/audio/node_2d.gd` | `stereo_panning_probe.gd` | Configures left/right audio players and tests panning. |
| `tests/manual/los/draw_los.gd` | `los_sampling_debug_draw.gd`, if its diagnostic role is confirmed | Samples and draws LOS, rather than a general renderer. |
| `tests/manual/rolls_stats.gd` | `roll_distribution_stats.gd` | Tracks histogram, mean, variance, and uniformity. |
| `tests/review_batch_regression.gd`, `review_batch_regression.tscn` | `match_systems_regression.gd`, `match_systems_regression.tscn` | Covers command links, targeting, retreat/projection, and occupation. Keep historical validation notes and update their test command links. |
| `sources/archive/influence_map/influence_map.gd` | `influence_map_reference.gd` | Distinguishes the preserved snapshot from the live implementation. |
| `sources/archive/influence_map/influence_map_controller.gd` | `influence_map_controller_reference.gd` | Same distinction for the controller snapshot. |
| `sources/archive/ai/platoon_ai.gd` | `platoon_defense_reference.gd` | Commented defense-assignment prototype. |
| `docs/design/ai/phase_evaluation` | `platoon_phase_evaluation_notes.md` | Gives the phase notes a readable document extension and subject. |
| `docs/design/ai/AI.odt` | `ai_design_notes.odt` | Descriptive filename and consistent casing; no format conversion. |

The `.odt` document was not inspected for content. Its rename is a broad subject label, not a claim about a specific AI design inside it.

### Task 2 execution checklist

- [x] Record a rename manifest with old and new basenames; include paired scenes and script UID companions.
- [x] Rename one domain at a time after Task 1 is complete.
- [x] Update references and documentation in the same batch, including the convention checker exclusion and renamed regression entry point.
- [x] Preserve public identifiers and scene nodes. A filename rename does not require renaming `$GameController`, `Globals`, `LOS`, or `PlatoonAI`.
- [x] Review case-only renames for a temporary intermediate filename. None of the implemented renames differ only in casing.
- [x] Repeat relevant import, regression, persistence, and headless UI checks. Interactive visual inspection remains unperformed.

**Task 2 is complete when:** the approved rename manifest is implemented, names distinguish implementation roles and UI components, paired scene/script basenames are consistent, and references work after a fresh import.

## Verification requirements and execution notes

The following requirements guided implementation. The baseline passed 16 regression runs; both completed tasks passed 17 runs after adding the legacy-save compatibility regression. Final parser and convention checks each covered 149 scripts with zero failures. UI interaction checks ran headlessly; the planned interactive visual inspection was not performed. See the execution results for exact coverage and existing runtime diagnostics.

| Affected batch | Verification |
| --- | --- |
| Every batch | Fresh Godot import and parser check for the same coverage as the baseline; `python3 tests/check_gdscript_conventions.py`; check stale old paths against the manifest. Preserve UIDs and exact class declarations. |
| Resource/save moves and catalog renames | `weapon_save_regression`, `casualty_persistence_regression`, `weapon_state_regression`, and `unit_roster_regression`. Run weapon/casualty persistence verification in a second process using `-- --verify-persistence`. Also load a fixture produced before the moves; newly generated fixtures alone do not establish backward compatibility. |
| Unit and combat components | `unit_movement_regression`, `unit_arrival_regression`, `unit_death_regression`, `close_combat_regression`, and `soldier_task_lifecycle_regression`. |
| World, LOS, maps, overlays, and UI | `objective_visibility_regression` for default, `--allies`, `--defend`, and `--allies --defend`; `review_batch_regression` or its new name after Task 2. Inspect scenario selection, details panels, tooltip labels, command wheel, countdown, and result screen interactively. |
| LOS data relocation | Load both Default Map and Orchard Road from a fresh import. Exercise the bake/save path in an isolated copy and reload the produced lookup resource. |
| AI and influence moves/renames | Start scenarios that instantiate both defense controllers and the phase-based controller, including Orchard Road Outpost Probe. Verify existing activation settings, exported references, influence overlays, and squad orders. Existing regressions do not establish coverage of all AI paths. |
| End of each task | Run all 11 existing regression suites, including the startup variants and fresh-process persistence cases; run an active-match smoke check with unit details, command links, and threat/influence drawing enabled. Compare diagnostics with the captured baseline. |

Checks used isolated copies and user data so test saves did not affect normal match history. Baseline diagnostics were compared with the completed refactor, including the existing Orchard Road movement error triggered by defense-controller orders, missing debug-match data, and shutdown warnings. The earlier attribution of that error to the phased controller was incorrect.

## Deferred decisions

- Resolved: retain the dormant phased controller as unfinished work requiring repair and dedicated coverage. Its decision loop remains disabled regardless of `is_active`. Follow the [repair and coverage plan](phased_controller_repair_plan.md); the existing refactor checks do not validate its tactical behavior.
- Development diagnostics and placeholder scenes were preserved under `tests/manual/`; any broader usage review remains separate work.
- Serialized script-path compatibility was resolved with five inheritance scripts at the old save/loadout paths. Unit-scene and weapon-definition paths remain stable. These compatibility scripts must remain while old saves are supported.
- Resolved: faction directories use full country names in lowercase `snake_case`, with `germany` and `united_states` consistently across resources/assets. See the [implemented naming convention](faction_folder_naming_proposal.md) and [migration manifest](faction_folder_refactor_manifest.json). Old resource paths remain available through compatibility redirects; image basenames are unchanged.
- Large scripts such as `unit.gd`, `game_controller.gd`, and `squad_fire_controller.gd` may merit decomposition later. Their responsibilities must be analyzed separately; folder moves and filenames alone do not require that change.
