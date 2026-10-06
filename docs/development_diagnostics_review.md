# Development diagnostics review

Reviewed on 6 October 2026, starting from commit `5e23367` (`fixed faction naming`). The initial usage and usefulness review changed documentation only. The subsequent cleanup, explicitly scoped by the user to unused files, removed 32 files: all 22 `.tmp` files, six influence-map archives, the duplicate splash backup, and three obsolete scene stubs. The [cleanup manifest](development_diagnostics_cleanup_manifest.json) records exact paths, hashes, reasons, and the Git recovery commit. Runtime scripts and the four useful manual probes were preserved; diagnostic repairs remain deferred.

Keep the live debugging tools and the useful manual probes. Repair the tilemap fixture before relying on it, and treat the manual LOS algorithm as a superseded prototype. The initial review identified three unused scene stubs and nine redundant backups. The cleanup also removed distinct unused temporary saves and influence-map snapshots as requested; their historical contents remain recoverable from Git.

## Reference audit

The audit checked current resource paths, scene/script UIDs, declared class names, and old paths in the organization manifest. It distinguished executable scripts and authored scene/resource dependencies from comments, documentation, archive snapshots, and temporary scene saves. Generated `.godot` registries are not evidence that a probe is used by gameplay.

None of the five primary files originally under `tests/manual/` had a current project consumer outside the probe itself and historical documentation. No companion scene for the audio or LOS scripts was found. Being unused by gameplay is expected for a manual probe and does not by itself make it obsolete. This audit covers the repository; it does not establish whether someone uses a probe outside it.

## Manual probes

| File | What it does and present condition | Disposition |
| --- | --- | --- |
| [`roll_distribution_stats.gd`](../tests/manual/roll_distribution_stats.gd) and its UID | `RollStats` collects counts, a histogram, mean, sample variance, min/max, and a uniformity statistic. Its deterministic statistics and reset checks passed. It is not an RNG or an automated test of combat outcomes. | **Preserve: useful measurement helper.** Attach to a node before sampling and supply normalized rolls. |
| [`audio/stereo_panning_probe.gd`](../tests/manual/audio/stereo_panning_probe.gd) and its UID | Places `SrcLeft` and `SrcRight` at −300/+300, configures their attenuation and panning, and offers sequential playback. Configuration and the playback sequence passed in a temporary harness. It has no saved harness, assigned streams, active listener setup, or automatic playback invocation. | **Preserve: useful audio probe needing a manual harness.** Audible channel separation still needs a listening check. |
| [`los/los_sampling_debug_draw.gd`](../tests/manual/los/los_sampling_debug_draw.gd) and its UID | Samples physics points every two pixels and draws green/red LOS segments over a fixed 7×7 grid. Parsing, an empty-map query, and generation of 48 drawing records passed with supplied sibling layers. Its separate LOS implementation is incomplete and differs from the live service. | **Preserve as a prototype/reference.** Rebind its drawing to the live service before using it to assess current LOS behavior. |
| [`maps/hexagon_tile_map_layer_test.tscn`](../tests/manual/maps/hexagon_tile_map_layer_test.tscn) | A visual hex-tile fixture with terrain peering bits, collision polygons, and elevation data; no assertions. Loading after a fresh import fails because `assets/tilesets/atlas.png` is absent. | **Preserve: potentially useful terrain/collision fixture needing repair.** Recover the intended atlas or deliberately replace its tileset before evaluating it visually. |
| `ai/formation_ai_controllers.tscn` (removed) | Loaded successfully, but contained one empty node, an embedded `active` property, and no controllers, units, scenarios, or assertions. | **Removed in the unused-file cleanup.** No diagnostic behavior or current path/UID consumer was found. |

`RollStats` requires `bins > 0`, `report_every > 0`, and samples after `_ready()`. It does not validate these inputs. Negative samples can mis-bin or exceed array bounds; samples above one are put in the final bin while still affecting the mean and variance. Its chi-square denominator uses `max(1, expected)`, so the result is not the usual statistic when expected counts are below one. Use it as a diagnostic with enough normalized samples, not as a pass/fail uniformity test. Combat still contains both uniform draws and transformed draws; feed the intended distribution rather than indiscriminately sampling every random result.

The audio script expects a `Node2D` with two `AudioStreamPlayer2D` children named exactly `SrcLeft` and `SrcRight`. Assign short mono streams, establish the listener, and invoke `test_clicks()` after ready. The two historical `scenes/world/node_2d.tscn*.tmp` files were old tilemap/unit scenes without these audio children, despite the similar filename. They were not usable audio companions and were removed with the other unused temporary saves.

The LOS prototype expects sibling `GroundTileMapLayer`, `BuildingTileMapLayer`, and `WallTileMapLayer` nodes. It never increments `hindrance_count`, calculates heights without using them in blocking, has no explicit zero-distance guard, assumes a particular hex layout and collision masks, and mixes viewport mouse coordinates with tilemap-local coordinates. Its drawing also assumes matching node transforms. These limitations mean the successful empty-grid check does not establish collision, terrain, height, wall, or transformed-camera correctness. [`LOSHelper`](../autoloads/los_service.gd) already offers `check_los()`, `draw_los()`, and `generate_los_lines_for_debug()` using the live algorithm. A repaired probe should call that service instead of maintaining another checker, with focused coverage for the cases it visualizes.

The tilemap fixture additionally references three `.godot/imported/*.ctex` files directly. Those three files **did regenerate in the fresh import**; they were not the observed load failure. When repairing the fixture, reference the corresponding source textures (`assets/tiles/elevation/crest_line.png`, `assets/tiles/ground/base_tile.png`, and `assets/tiles/16x16_2b - Kopie.png`) to avoid coupling the scene to import destinations. Retain its authored terrain and collision data until its usefulness can be assessed with the atlas restored.

## Live diagnostics to retain

| Component | Evidence and usefulness |
| --- | --- |
| [`autoloads/debug_settings.gd`](../autoloads/debug_settings.gd), [`debug_panel.gd`](../scenes/ui/panels/debug_panel.gd) | `Debug` is an autoload; the battle HUD attaches the panel script and connects its toggles. Selection, damage suppression, firing suppression, fog, enemy display, command links, and tactical lines have runtime consumers. Unit-detail debug actions queue kills and surrender for the match controller. Preserve both files. |
| [`influence_map/debug/influence_map_debug_draw.gd`](../scenes/world/influence_map/debug/influence_map_debug_draw.gd) and its scene | The world instantiates the canonical scene; match setup supplies the tilemap and controller, calls `setup()`, and selects a view/team. It draws values and listens for map updates. Number keys change views, `0` clears the view, and Tab changes team. Useful for inspecting AI inputs and projection values. |
| [`autoloads/los_service.gd`](../autoloads/los_service.gd), [`tactical_lines_overlay.gd`](../scenes/world/overlays/tactical_lines_overlay.gd), [`command_connectivity_renderer.gd`](../scenes/world/overlays/command_connectivity_renderer.gd) | The match controller calls LOS drawing and clearing; unit signals feed tactical lines; debug flags control LOS, movement, and enemy command-link display. These are current diagnostics, separate from the old manual LOS checker. |
| Development scenarios embedded in [`world.tscn`](../scenes/world/world.tscn) | `Debug`, `Debug2`, and `Probe The Outpost Debug` contain actual units/objectives and enter scenario selection in debug builds. `Debug2` explicitly depends on a successful saved `Debug` match, so it can be disabled without that save. Keep these authored scenarios; their names do not establish obsolescence. |

One live-panel option needs a separate repair decision: the legacy `ThreadMap`/`EnemyTeam` switches write `Debug.draw_thread_map` and `Debug.draw_thread_map_enemy`, but no current signal connection to `match_controller._on_draw_threat()` was found. The old connection in `setup()` is commented out. `ThreatMap` still computes and emits updates; this is a disconnected drawing path, not evidence that the threat subsystem or whole debug panel is obsolete. Use the influence-map threat view for inspection while deciding whether to repair or retire the legacy dot overlay. No flags or controls were removed in this review.

[`unit_stats_summary.tscn`](../scenes/ui/units/unit_stats_summary.tscn) is also **not an unreferenced file**: the HUD assigns it to `unit_stats_details_scene`. Its old instantiation block is commented out, making the behavior dormant, but deleting it would leave a serialized dependency unless that assignment were removed too. Preserve this UI component for a separate UI usage review.

## Removed obsolete scenes

| File | Evidence |
| --- | --- |
| `tests/manual/ai/formation_ai_controllers.tscn` | No consumers; valid but empty placeholder with no test behavior. This is separate from the retained, unfinished phased controller. |
| Root `influence_map_debug_draw.tscn` | No current path or UID consumers. Referenced missing root `influence_map_debug_draw.gd`; instantiated a scriptless node with load errors. The world uses the canonical debug scene under `scenes/world/influence_map/debug/`, with a different UID. |
| Root `influence_map_controller.tscn` | No current path or UID consumers. Referenced missing `scenes/world/influence_map/controller_subsystems/influence_map_controller.gd`; instantiated a scriptless node with load errors. The world uses `scenes/world/influence_map/influence_map_controller.tscn`, with a different UID. |

The comments-only scripts under `sources/archive/ai/` and `sources/archive/influence_map/` are historical references rather than runnable diagnostics. Keep them archived. `sources/archive/world/map.gd` contains only `extends Node2D` and has no consumers; it adds no diagnostic functionality, but is already intentionally archived and does not need to be touched for this task.

## Backup inventory and redundancy

The review inventoried 22 `.tmp` files, four `~` backups, six influence-map archives, and the font distribution archive. No literal project-code dependency on these backup/archive paths was found. Comparisons used SHA-256/content bytes, not filenames or modification dates. Current scene comparisons account for the organization manifest's moves.

The following **nine original candidates were redundant**, with an exact counterpart identified before deletion. All nine were removed. The broader requested cleanup also removed the temporary-save and influence-map-archive counterparts in this table; those versions remain in Git.

| Candidate | Identical counterpart |
| --- | --- |
| `assets/splash_screen/splash_02.png~` | Current `assets/splash_screen/splash_02.png`. |
| `assets/tiles/buildings/orchard.png40275238561.tmp` | Current `assets/tiles/buildings/orchard.png`. |
| `scenes/game/units/unit.tscn3246295297.tmp` | `scenes/game/units/unit.tscn1033487933.tmp`. |
| `scenes/game/units/unit.tscn43347079223.tmp` | `scenes/game/units/unit.tscn1033487933.tmp`. |
| `scenes/game/units/unit.tscn956448626.tmp` | `scenes/game/units/unit.tscn1033487933.tmp`. |
| `scenes/game/units/unit.tscn3940439980.tmp` | `scenes/game/units/unit.tscn3932947620.tmp`. |
| `scenes/game/units/unit.tscn4599191397.tmp` | `scenes/game/units/unit.tscn4516203250.tmp`. |
| `scenes/world/world.tscn1310094601.tmp` | `scenes/world/world.tscn1300252041.tmp`. |
| `scenes/world/influence_map.tar.gz` | `scenes/world/influence_map (1).zip`: identical 44 member names and file contents. Container metadata was not compared. |

The original inventory also contained distinct data. The user subsequently authorized removal of unused `.tmp` files and influence-map archives; distinct historical versions are recoverable from Git. Artwork backups and the font distribution remain preserved:

| Group | Findings and preservation decision |
| --- | --- |
| `scenes/game/units/unit.tscn*.tmp` | Removed twelve files containing seven distinct scene versions. None matched the current scene. Historical versions remain in Git. |
| `scenes/world/world.tscn*.tmp` | Removed four files containing three distinct versions. None matched the current world scene. Historical versions remain in Git. |
| `scenes/ui/ui.tscn2297517976.tmp`, `ui.tscn5101125052.tmp` | Removed two distinct historical HUD versions; neither matched the moved current HUD. Historical versions remain in Git. |
| `scenes/world/node_2d.tscn971304179.tmp`, `node_2d.tscn3731878108.tmp` | Removed two distinct old tilemap/unit fixtures with stale root paths; neither was an audio harness. Historical versions remain in Git. |
| `assets/objectives/allies.png~`, `axis_exit.kra~`, `objective.kra~` | Each differs from its corresponding current asset/source document. Preserve; historical artwork was not visually compared. |
| `assets/units/unit_tb_alt.png262699985.tmp` | Removed as an explicitly requested unused temporary save. Its canonical basename was absent and no other project file had identical content; the unique image remains recoverable from Git. |
| Influence-map ZIP/TAR snapshots | Removed all six unused archives, including the duplicate ZIP/TAR pair. Every member mapped to a current file, but the five distinct snapshots had three to six byte-different files each. Historical archives remain in Git; the live influence-map implementation was preserved. |
| `assets/fonts/courier-prime.zip` | Third-party font distribution with fonts, readme, and license material. Preserve; it is outside development-diagnostic cleanup. |

Influence-map archive comparisons before removal:

| Archive | Files | Identical to mapped current file | Different |
| --- | ---: | ---: | ---: |
| `influence_map.zip` | 42 | 36 | 6 |
| `influence_map (1).zip` | 44 | 38 | 6 |
| `influence_map (2).zip` | 44 | 38 | 6 |
| `influence_map (3).zip` | 44 | 41 | 3 |
| `influence_map.tar.gz` | 44 | 38 | 6 |
| `influence_map_team_threat_axis_storage.zip` | 43 | 37 | 6 |

These counts use exact file bytes after path mapping, not normalized script logic. The duplicate ZIP/TAR comparison checks member contents rather than comparing compressed container hashes.

## Validation and next work

Checks ran with Godot `4.7.2.stable.arch_linux.ed1daf0bf`. A temporary project copy excluded `.git` and `.godot`, and used isolated XDG data/config/cache directories. Fresh editor import exited zero; installed editor addons emitted socket diagnostics and an exit resource warning. Successful import did not establish that unused scenes could load, so the reviewed scenes were loaded separately.

A temporary GDScript harness completed 14 deterministic checks with zero assertion failures: RollStats parsing, count, mean, sample variance, histogram, balanced-bin statistic, endpoints, and reset; audio parsing, placement, and configuration; LOS parsing, empty-map query, and drawing-record generation. Sequential audio playback returned. Separate scene loads established the valid empty AI placeholder, broken tilemap dependency, and scriptless root stubs. The expected resource errors from those scene loads are findings, not passing checks for those scenes. No listening or visual correctness checks were performed.

`python3 tests/check_gdscript_conventions.py` passed for all 150 project scripts. The initial review did not rerun gameplay regressions because it changed documentation only. Cleanup validation is recorded below. No dedicated collision, transformed-camera, hindrance, elevation, or statistical-significance coverage was added by this review.

The concrete follow-up order is:

1. Keep the live diagnostics and useful manual helpers, using the [manual index](../tests/manual/README.md) for setup and limitations.
2. Restore or replace the atlas for the tilemap fixture; reconnect the manual LOS visualizer to the live service if the fixed-grid view is wanted. Add focused coverage when implementing those repairs.
3. Decide whether to repair or retire the disconnected legacy threat-dot controls; preserve the functioning threat subsystem and influence-map view.
4. Completed: re-scanned exact path/UID consumers and removed the three obsolete scenes, all 22 unused temporary saves, all six influence-map archives, and the redundant splash backup. The user explicitly chose unused-file cleanup only; steps 2 and 3 remain deferred.
5. Preserve the remaining distinct artwork backups and font distribution. Removed historical temporary saves and archives remain recoverable from the source commit in the cleanup manifest. The unfinished phased controller remains governed by its separate [repair and coverage plan](phased_controller_repair_plan.md).

## Cleanup execution

Removed 32 unused files totaling 2,445,812 bytes. Every removed file matched its tracked version at commit `5e23367dc2e5e470e099075373c22f52f0d03d16`; no uncommitted content was discarded. The exact path/UID rescan found no current consumers. Root-scene basename matches were checked against full paths so the canonical runtime scenes were preserved.

Added Git ignore rules for editor `.tmp`/`~` files and influence-map snapshot archives under `scenes/world/`. The font ZIP and distinct objective artwork backups remain in place. No runtime scripts, useful probe implementations, authored maps, or compatibility resources were changed.

The cleanup manifest is the authoritative removal list. A removed file can be recovered using `git restore --source=5e23367dc2e5e470e099075373c22f52f0d03d16 -- <path>`.

Cleanup validation passed:

- Fresh Godot import in a new isolated copy with no `.godot` cache exited zero. Optional editor-addon socket diagnostics and the exit resource warning matched the earlier import.
- `match_systems_regression.tscn` passed before and after cleanup with zero regression failures. Both runs reported the same existing missing `user://matches/debug.tres` diagnostic and shutdown warnings; cleanup introduced no new runtime diagnostics in this check.
- The convention checker passed for all 150 project scripts. Byte comparison against Git verified that all 653 surviving tracked scripts, scenes, resources, and UID companions were unchanged.
- The deletion set exactly matches the 32-file manifest, no `.tmp` or influence-map snapshot archives remain, retained probes/runtime scenes are unchanged, and document links resolve. Git whitespace checks passed.
