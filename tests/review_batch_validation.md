# Review-batch fixes and verification

Target: Godot 4.7 / GDScript. Verified with Godot 4.7.2.

## Coverage checklist

- [x] Read project instructions and map the relevant callers, signals, scenes, and resources. No applicable `AGENTS.md` or `sources/` directory was present.
- [x] Trace command-link collection, expiry, and visibility updates.
- [x] Trace player and tracked fire orders, rifle/mortar execution and visuals, attack-order holding, retreat selection, and influence projection at `(0,0)`.
- [x] Separate occupation evaluation from active match time, including stopped matches, expiry, and conditions following an unmet condition.
- [x] Replace the three executable LOS ternaries with branches.
- [x] Annotate project-owned declarations, signals, parameters, return values, lambdas, and loop variables, including inferred `:=` declarations.
- [x] Run parser checks for all 147 project scripts and the convention checker.
- [x] Run all 11 regression suites, with four objective-visibility startup combinations and fresh-process weapon/casualty save verification: 16 successful runs.
- [x] Run 600 active match frames with unit details open and threat-map drawing enabled.
- [x] Compare the tested script contents with the workspace; check whitespace and preserve excluded files.

Vendor `addons/` and `ai/platoon/phased/platoon_phase_controller.gd` are excluded from annotation enforcement and parser coverage. The authored Orchard Road Outpost Probe scenario sets this controller's `is_active` flag to true, but an unconditional return in `_physics_process()` disables its tactical loop; the organization refactor preserves that wiring and the existing coverage policy. The unused theme and missing development-scene texture reference are unchanged. Nullable value-type coordinates and heterogeneous dictionary entries retain explicit `Variant` annotations. GDScript property-setter parameters inherit their property's declared type. The annotation forms follow [Godot's static typing documentation](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html).

## Confirmed behavior and corrections

| Area | Original trigger and failure | Correction and regression evidence |
| --- | --- | --- |
| Command-link history ([tactical_lines_overlay.gd](/home/blight/Documents/godot/Projects/acl/scenes/world/overlays/tactical_lines_overlay.gd:164)) | Repeated connectivity samples appended records without advancing their expiry timers. | Age and expire records. A simulated minute of 600 samples stays bounded; all samples expire after updates stop. |
| Connectivity visibility ([command_connectivity_renderer.gd](/home/blight/Documents/godot/Projects/acl/scenes/world/overlays/command_connectivity_renderer.gd:13)) | Disabling connectivity hid children, then the same update re-showed eligible children. The actual world scene also starts the renderer parent hidden. | Synchronize parent visibility with the setting and return after hiding. The actual scene and settings checkbox are exercised, checking inherited visibility at startup, with both enemy-debug settings, and after disabling/re-enabling. |
| Origin targeting ([squad_fire_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/combat/squad_fire_controller.gd:85), [unit.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/unit.gd:273), [squad_action_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/actions/squad_action_controller.gd:108)) | Coordinate-zero sentinel checks rejected valid ground and tracked targets, mortar shots, and visuals. | Explicit target-presence flags and clearing, correct order replacement, and weapon-family visual dispatch. Probe verifies rifle and mortar orders/tracking at `(0,0)`, explicit clearing, replacement of tracking at the same tile, and holding an origin attack order. |
| Origin retreat/projection ([squad_action_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/actions/squad_action_controller.gd:532), [squad_ai_controller.gd](/home/blight/Documents/godot/Projects/acl/ai/squad/squad_ai_controller.gd:167), [projection_source_builder.gd](/home/blight/Documents/godot/Projects/acl/scenes/world/influence_map/projection/projection_source_builder.gd:142)) | Origin coordinates were rejected as failed retreat destinations or discarded from projected cells. | Compare retreat results with the current tile, which the search returns when no candidate exists, and retain projected origin cells. Regression verifies an origin rout and no-candidate failure, plus origin projection. |
| Occupation ([occupy_objective_condition.gd](/home/blight/Documents/godot/Projects/acl/scenes/scenarios/victory_conditions/occupy_objective_condition.gd:51), [match_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/match_controller.gd:926)) | Every evaluation added one second, including result queries; an earlier unmet condition could prevent later occupation checks. | Read-only evaluation and a separate active-clock update using elapsed seconds. Probe verifies repeated reads, fractional seconds, contest reset, stopped clocks, independent condition updates, and the capped final frame. |

The original-code probe failed 18 assertions across history, visibility, origin firing/visuals, and occupation. A follow-up found that the initial visibility test instantiated a fresh renderer and missed the actual scene's hidden parent. The revised test uses the world renderer, toggles the actual checkbox, and checks `is_visible_in_tree()`. The completed probe passes. Existing default contest and victory timing policies are preserved.

## Two exported options still need a defined contract

`contested_by_enemy_presence` is never read by the active occupation evaluator. Any good-order enemy on an objective currently resets continuous occupation, even when the option is false. Broken, surrendered, and dead units do not count as occupying or contesting it. Assuming the flag's name expresses its intent, false would allow friendly occupation to accumulate despite enemy presence; whether non-good-order enemies should contest is a separate design decision.

`test_at_scenario_end` is never read by the match evaluator or result screen. Victory conditions are checked periodically during play and can finish the match before the countdown expires; they are also checked at expiry and for result display. Assuming the flag's name expresses its intent, true would restrict that condition's victory eligibility to scenario end. This does not settle whether occupation should accumulate throughout the match or whether several satisfied conditions should determine a particular final outcome. No authored configuration explicitly setting this flag was found. These two options were left unchanged because this request asks for an explanation of their unclear contract.

## Re-run the new checks

From the project root:

```bash
python3 tests/check_gdscript_conventions.py
acl_test_data="$(mktemp -d)"
env XDG_DATA_HOME="$acl_test_data/data" XDG_CONFIG_HOME="$acl_test_data/config" XDG_CACHE_HOME="$acl_test_data/cache" godot --headless --path . res://tests/match_systems_regression.tscn
```

The XDG directories isolate the test's save data. Expected summaries: `convention violations: 0` and `Review batch regression failures: 0`.

## Verification limits

Checks ran headlessly in an isolated full project copy with separate user data. A 600-frame active-match smoke check exercised simulation, unit-detail updates, and threat-map drawing without script errors. No interactive visual playthrough or long-running full-match benchmark was performed. The history check simulates elapsed time. Existing missing `user://matches/debug.tres` diagnostics and shutdown ObjectDB/resource warnings still occur in scenario-based tests; the completed batch probe has the same 58 leaked-instance shutdown count as its original-code baseline. No new script runtime errors occurred in the successful test runs. The unrelated theme and development texture issues were neither repaired nor treated as passing asset checks.
