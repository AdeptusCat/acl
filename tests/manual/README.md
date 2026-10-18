# Manual development probes

These files are preserved diagnostics and prototypes, not automated regression entry points. The [usage review](../../docs/development_diagnostics_review.md) records reference checks, validation, and repair needs. The subsequent unused-file cleanup removed the empty formation-AI placeholder; the [cleanup manifest](../../docs/development_diagnostics_cleanup_manifest.json) records removed files and their recovery commit. Useful probes remain preserved; repairs were deferred at the user's request.

| Probe | Purpose | How to use / status |
| --- | --- | --- |
| [roll_distribution_stats.gd](roll_distribution_stats.gd) | Measure a normalized roll distribution. | Attach `RollStats` to a node, wait for ready, and feed `sample(value)` with values in `[0, 1]`. Set positive `bins` and `report_every`; use `report()` and `reset()` as needed. Deterministic statistics checks passed. The output is diagnostic, not a pass/fail uniformity test. |
| [audio/stereo_panning_probe.gd](audio/stereo_panning_probe.gd) | Check left/right positional audio. | Attach to `Node2D` with `AudioStreamPlayer2D` children named `SrcLeft` and `SrcRight`. Assign short mono streams, establish a listener, then call `test_clicks()` after ready. Configuration/playback sequence checked headlessly; audible panning requires listening. No companion scene is saved. |
| [los/los_sampling_debug_draw.gd](los/los_sampling_debug_draw.gd) | Historical 7×7 LOS sampling/drawing prototype. | Requires sibling hex tilemap layers named `GroundTileMapLayer`, `BuildingTileMapLayer`, and `WallTileMapLayer`. Preserve as reference; its independent checker omits current LOS behavior. Use the live `LOSHelper` drawing/service for current diagnostics. Rebind this visualizer before trusting it. |
| [maps/hexagon_tile_map_layer_test.tscn](maps/hexagon_tile_map_layer_test.tscn) | Inspect hex terrain and collision setup visually. | Retained for repair. Currently fails to load because `assets/tilesets/atlas.png` is missing. Preserve its authored tile data until the fixture can be evaluated. |

Current runtime diagnostics live in the battle HUD debug panel, influence-map overlay, tactical/command-line renderers, and `LOSHelper`. Their setup and known disconnected legacy threat-dot option are documented in the review.
