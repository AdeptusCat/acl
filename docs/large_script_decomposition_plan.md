# Behavior-preserving decomposition plan

Status: analysis and proposed implementation sequence only. No runtime code, scenes, resources, or tests were changed by this planning pass.

Analyzed on 2026-10-06 against commit `81c319d` (`removed unused files`). The working tree was clean at the start. `match_controller.gd` is the current filename; its scene node remains `GameController`.

## Recommendation and scope

Keep the three existing scripts as their scene-facing entry points. Extract contained responsibilities behind their existing methods, beginning with Unit's editor loadout recipes. Preserve public fields, exported properties, signals, script/scene identities, and the order of side effects. Do not combine this work with gameplay repairs, schema changes, or activation of dormant systems.

The scripts already delegate movement, orders, stress, presentation, command connectivity, and combat statistics to components. Further decomposition should isolate roster construction, casualty handling, match visibility and interaction, and fire resolution. Replacing those existing components or splitting by an arbitrary line limit would introduce unnecessary risk.

| Current script | Physical lines | Top-level functions | Main reason to split |
| --- | ---: | ---: | --- |
| [unit.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/unit.gd) | 2,007 | 95 | Editor authoring, roster/casualty operations, and save mapping share a lifecycle coordinator. |
| [match_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/match_controller.gd) | 1,521 | 50 | Match wiring, visibility, mouse interaction, objectives, and combat enrollment share one scene script. |
| [squad_fire_controller.gd](/home/blight/Documents/godot/Projects/acl/scenes/game/units/combat/squad_fire_controller.gd) | 1,347 | 34 | Target policy and impact calculations are mixed with asynchronous firing and shared roster state. |

Counts include comments and disabled code. A smaller file alone is not evidence that a responsibility has been separated successfully.

## Responsibilities and dependencies

### Unit

| Responsibility and current entry points | Dependencies and effects | Planned boundary |
| --- | --- | --- |
| Editor identity/catalog selection: exported setters, `set_squad_type()`, numbering setters, `_make_squad()`; lines 560–596 | `Globals` enums/names, squad catalogs, property setters, node name. Assigns catalog resources by reference. | Keep on Unit so scene authoring and initialization remain stable. |
| Seven `_make_*` loadout recipes and `_resize_loadouts()`; lines 534–559 and 597–1151 | Team-specific weapon resources, `SoldierLoadout`, ranks/roles, shared `loadouts`, toggle resets, editor notifications. These setters also run in dynamic spawning. | Extract recipe bodies to `resources/squads/squad_loadout_templates.gd`; retain setter methods and notification/reset order on Unit. |
| Runtime roster construction: `_setup_runtime_soldiers()`; lines 455–533 | `SquadLoadoutSpec`, `WeaponSpec.create_runtime()`, `Soldier`, default rifle, global RNG, fire roster, member/range counters and mortar UI. | Extract synchronous construction to `scenes/game/units/soldiers/unit_roster_builder.gd`. Unit remains the owner supplied to each Soldier. |
| Casualties, promotion, and weapon recrewing: `_on_incoming_fire_effect()`, `apply_specific_casualty()`, `_apply_casualties()`, role/index helpers; lines 1328–1694 | Live fire roster and casualty arrays, casualty history, combat stats, stress, audio, leader aura and UI. Exact casualty and random batch paths have different behavior. | Extract roster mutation/crew algorithms to `scenes/game/units/combat/unit_casualty_handler.gd`; keep effect orchestration and elimination callbacks on Unit. |
| Contacts and memory: `_check_contacts()`, `remember_enemy()`, `cleanup_enemy_memory()`; lines 1214–1271 | `Globals.unit_visible_enemies`, physics-frame clock, Unit's memory/report arrays and contact signals. | Optional later extraction to `scenes/game/units/visibility/unit_contact_reporter.gd`, after a separate memory-repair decision. |
| Save mapping: `create_save_data()`, `apply_save_data()`; lines 1950–1999 | `UnitSaveData`, typed loadouts, Soldier save data, scene path, casualty records/history and roster initialization. | Extract mapping to `resources/saves/unit_save_codec.gd`; keep public methods and roster initialization dispatch on Unit. |
| Lifecycle and integration: `setup()`, `game_start()`, `order()`, movement/morale callbacks, `surrender()`, `die()`, timer callbacks | Existing movement, action, stress, command, aura, UI, fire and AI components; `LOSHelper`, `MovementSystem`, `Globals`, `Debug`, `STATES`, `RankGrades`. | Keep on Unit. These methods coordinate existing components rather than defining another movement or action system. |

Inbound consumers include World startup, Match, unit details/UI, squad/platoon AI, `CloseCombatInstance`, save/persistence tests, and the existing child components. They read Unit's fields directly and call its current methods; the first decomposition must retain that surface.

### Match controller

| Responsibility and current entry points | Dependencies and effects | Planned boundary |
| --- | --- | --- |
| Wiring and startup: `setup()`, `setup_game()`, `start_game()`; lines 82–137, 454–474 and 807–874 | World has already bound maps, initialized/reparented units and registered scenario conditions. Match connects unit signals, registers units, assigns HQ relationships, initializes overlays and starts directors/timers. | Keep orchestration on Match. Delegate individual operations at their current positions. |
| Visibility and contact tracks: `draw_fog()`, `show_visible_units()`, `update_visible_hexes()`, `update_los_time()`, visibility timeout, detection/concealment helpers, `_on_unit_shooting()` | `LOS` supplies geometric LOS; `LOSHelper` supplies lookup/hex queries; `EnemyTrack` and `Globals` hold tracking/detection state. Also updates fog and scene visibility. | Extract to `scenes/game/match/match_visibility_coordinator.gd`; preserve scene callbacks and timers on Match. |
| Selection, command wheel, hover previews and glow: `order_via_option_wheel()`, left-click handler, active `handle_mouse_event_position_changed()`, selection methods, `hex_glow()` | Local/global mouse coordinates, map layers, selected Unit, Unit orders, parent World/UI, LOS renderer and influence overlay. | Extract to `scenes/game/match/match_interaction_handler.gd`; leave `selected_unit` and mouse-position state on Match initially. Camera callbacks remain on Match. |
| Objective assignment and victory: `set_objective_layer()`, `set_objective_cells()`, `set_victory_conditions()`, win-condition timeout; frame-clock block in `_process()` | Authored objective layers, global objective lists, condition Resources, countdown, winner signals and World's result/save handling. | Extract objective/victory operations to `scenes/game/match/match_victory_coordinator.gd`. Keep frame-clock state and its orchestration on Match. |
| Close-combat enrollment: `_on_unit_entered_hex()`, `set_close_combat_hexes_and_units()`; lines 310–453 | Visibility/terrain update order, same-hex unit lookup, movement, existing `CloseCombatInstance` scene and instance container. | Extract active enrollment to `scenes/game/combat/close_combat_coordinator.gd`; reuse the existing combat engine. |
| Dynamic and saved-unit spawning: `spawn_unit()`, `spawn_units_from_match_save()`, `spawn_unit_from_save()` | Packed scenes, scene-tree initialization, loadouts, groups, map coordinates, signal wiring, global registration and HQ links. | Late extraction to `scenes/game/match/match_unit_spawner.gd`; keep each existing path's initialization order. |
| Debug queues, drawing and dormant prototypes | `Debug` flags/queues, old threat drawing, formation stub and disabled close-combat/mouse handlers. | Keep current activation state and scene callbacks. Review retirement separately. |

World and `world.tscn` depend on the `GameController` node path and signal/method names. World owns whole-match save creation; extracting Match's victory logic must not introduce a second match-save writer.

### Squad fire controller

| Responsibility and current entry points | Dependencies and effects | Planned boundary |
| --- | --- | --- |
| Shared fire state: `set_soldiers()`, target setters/flags, attack mode, fire-recent counters, tuning exports | Unit and its action/stress systems, direct roster readers, mutable Soldier/WeaponSpec/Task instances. `(0,0)` is a valid target. | Keep authoritative state on the controller. Preserve setter side effects and existing wrappers. |
| Automatic target selection: `handle_auto_fire()`, `_score_enemy_for_target()`; lines 365–467 | Visible enemies, range/cover/movement, friendly occupancy, Unit order dispatch, fire timer. Scoring also updates enemy cover. | Extract policy to `scenes/game/units/combat/squad_target_selector.gd`; keep target publication/order dispatch at its existing point. |
| Firing lifecycle: `_process()`, `_tick_soldiers()`, `_try_fire_soldier()`, `fire_shots()`, aim/arrival setup | Global RNG, Soldier tasks, ammo, roles, morale, Unit state, timers/awaits, audio and shot signals. | Keep async chains on the controller. Later extract small synchronous preparation blocks only if coverage establishes their boundary. |
| Impact resolution: `fire_at()`; lines 855–1217 | Current target-hex occupants, ordered targets, weapon/state/stress/cover policy, global RNG, suppression and deferred Unit casualty effects. | Extract synchronous resolution to `scenes/game/units/combat/squad_hit_resolver.gd`; supply the original controller as the damage source. |
| Numeric helpers: support efficiency, mean hit chance, discrete cover policy; burst/delay random helpers | Inputs and global RNG for random helpers; some other numeric helpers only have commented consumers. | Extract used deterministic helpers first to `scenes/game/units/combat/squad_fire_math.gd`. Move random helpers only after seeded parity coverage. |
| Weapon presentation and legacy calculator setup: `_on_fire_weapon()`, `_on_stop_mg_loop()`, `set_mg()` | Sibling `WeaponAudio`, original Unit position/identity, `SquadFireInput`/`SquadFireCalculator`. | Keep audio hooks on the controller. `SquadFireCalculator.build_volley()` has no active consumer found and represents another firing model; it is not the destination for active per-soldier firing. |

Inbound consumers include Unit, `SquadActionController`, combat statistics/projection, AI, `CloseCombatInstance`, scenes and test subclasses. Existing tests override `fire_at()` and `_on_fire_weapon()`, so a helper must not bypass these calls.

## Ownership and compatibility rules

Start with typed, synchronous `RefCounted` helpers or static functions. They receive the current operation's dependencies explicitly and have no independent `_process()`, scene timers, signal subscriptions, or autoload registration. The template helper must be callable in the editor before child `@onready` references exist. Do not add child scenes merely to host synchronous algorithms.

Prefer narrow inputs for numeric/selection work. For coupled roster or impact operations, initially pass the original owner explicitly rather than changing mutation order through a new snapshot/result pipeline. Helpers must not retain owners, soldiers, targets or global dictionaries after an operation. Narrowing those contracts further is a later change once parity is established.

| State/contract | Owner that must remain authoritative | Consequence for extraction |
| --- | --- | --- |
| Unit identity, exported authoring fields, live counters, casualty records and tactical/action state | Unit and its existing components | Keep fields/methods callable at the original locations; no copied parallel roster model. |
| Runtime `soldiers`, `casualties`, targets, fire flags and counters | SquadFireController | `set_soldiers()` replaces its array; helpers operate on current references, not a cached former array. |
| Ammo/setup and weapon identity | Each runtime Soldier's physical `WeaponSpec` | Runtime construction clones definitions; recrewing transfers the same weapon object, retaining its state. Shared definition/audio resources remain shared as before. |
| Visibility, tracks, registries, destroyed units and objectives | Globals/LOS and existing condition Resources | The visibility tick replaces `Globals.unit_visible_enemies`; visible-hex arrays are cleared in place. Preserve both behaviors and read live dictionaries on subsequent calls. |
| Selection, countdown, timer-running and end-game flags | Match | Scene/UI consumers and regression tests continue to access these fields. |
| Node identity, signals, timers and coroutines | Original scene scripts | Keep callbacks, coordinate anchors, `get_tree()`/`get_parent()` meaning and source identity. A helper's `self` must not replace the controller/Unit. |
| Virtual entry points used by tests | Original Unit/fire methods | Preserve dynamic dispatch through `_make_squad()`, `_setup_runtime_soldiers()`, `_set_combat_ineffective()`, `_on_fire_weapon()` and `fire_at()`. |

Keep current script UIDs, `class_name Unit`, `class_name SquadFireController`, the Unit scene/save path, the `GameController` scene node and child names. Match currently has no `class_name`; adding one is unnecessary for extraction. Keep exported names/types/defaults and scene signal connections unchanged. Introduce new helper UIDs normally, without rewriting existing ones.

Legacy save/loadout inheritance scripts, faction redirects, weapon-definition paths and old-path test fixtures remain in place. Save extraction must preserve the existing fields and resource mapping, including `unit_scene_path` and embedded weapon source paths. It must not add restoration of ammo, tasks, positions or other fields that the current mapping does not restore.

## Behavior that requires explicit protection

1. **Startup and editor order.** World binds map/LOS dependencies, initializes scenario units, reparents them and calls `game_start()` before Match setup/start. Unit's `_ready()` performs catalog selection; it does not perform full runtime `setup()`. Dynamic spawning sets several authoring fields before `add_child()`, whereas saved-unit spawning adds the child first. Do not consolidate these three paths during extraction. Preserve template setter reentry, resource aliasing, toggle resets and notification order.
2. **Signal timing.** Objective layers/lists are populated before `start_match` emits; other startup operations occur afterward. Preserve movement/arrival/morale callback order, contact reporting frequency, shot/audio order and winner signal timing relative to flag changes. A subscriber may observe partially advanced state at the signal point. Keep signal names and current argument behavior; signature repairs are separate.
3. **Roster and casualty semantics.** `apply_specific_casualty()` returns true for elimination of the last soldier, not for every successful casualty. Random casualties use the current shuffled-index/removal order. Preserve casualty records, leader promotion, crew reassignment, stress/UI/aura updates and the differences between specific and batch casualties. Surrender and death remain distinct operations.
4. **Randomness and formulas.** Keep the global RNG and the number/order of draws, including initialization phase, shuffled casualties, burst-size rejection sampling, jitter, detection and hits. Preserve iteration/tie order. Despite its name, `cover_multiplier_exp()` uses discrete exact-value cases; replacing it with an exponential formula changes combat. Impact hit chance is cumulatively modified while iterating targets; do not convert it into independent per-target calculations.
5. **Fire scheduling and death.** `_process()` starts `_tick_soldiers()` without awaiting it; that method awaits soldiers sequentially, gunners first. Keep the present possibility of overlapping frame-started chains. The first burst visual fires synchronously; later visuals stop when the owner dies. An already launched projectile still resolves its impact after owner death, while `shooting` only emits if the owner remains alive. Keep the async timer chain and overridden `fire_at()` call on the controller.
6. **Impact target collection and deferral.** At impact, current occupants of the target hex are appended to the original batch, including friendly occupants. Keep target-array mutation, order, suppression/cover side effects, casualty clamping and deferred `_on_incoming_fire_effect()` calls. The deferred source argument remains the original SquadFireController.
7. **Visibility clocks.** Match's visibility timer runs every 0.1 seconds but currently passes `1.0` to the detection probability calculation. Track aging uses Unix time; Unit contact memory uses physics-frame time. Preserve those clocks, confidence thresholds and same-hex lock behavior. Firing changes track confidence without immediately republishing the global visibility dictionary.
8. **Match-clock and victory ordering.** All conditions advance while the clock runs, using the capped final-frame elapsed time. Preserve timer-label emission order, major/minor priority, tie/timeout distinctions, iteration/early-return behavior and the end-game guard. Do not normalize winner signal arguments or move flag updates across its emission.

## Implementation order and required coverage

Each row is a separate reviewable extraction. Add the necessary characterization assertions to the unchanged implementation first, then extract and compare behavior. Tests should assert externally observable effects, event order, identities and lifecycle results; avoid tests that merely repeat the new helper's implementation. Proposed helper paths below do not exist yet.

| Batch | Change | Coverage required before/after extraction |
| --- | --- | --- |
| 0. Capture baseline | Record current import/parser diagnostics, convention results, regression outcomes and scenario startup. Add missing behavioral coverage before the corresponding extraction. | Use an isolated project copy and user-data directories. Freeze relevant RNG/time inputs for deterministic probes. Record established diagnostics separately from new failures. |
| 1. Loadout templates | Extract the seven recipe bodies and resize algorithm to `resources/squads/squad_loadout_templates.gd`. Retain all Unit setter/recipe entry points and `_make_squad()` on Unit. | New editor/runtime authoring cases for both teams and all seven toggles: names, counts, roles/ranks, weapon resource identity/paths, resizing, reset flags, catalog assignment and notifications. Existing roster and weapon-state/save suites. |
| 2. Deterministic fire math | Extract active cover, mean-chance and support-efficiency helpers to `scenes/game/units/combat/squad_fire_math.gd`, retaining wrappers. Leave unused prototype formulas and random helpers unchanged initially. | Boundary cases for exact cover values and fallback, support count limits and hit mean; use real fire behavior as well as formula checks. No arithmetic rearrangement or balance adjustment. |
| 3. Runtime roster builder | Delegate `_setup_runtime_soldiers()` construction to `scenes/game/units/soldiers/unit_roster_builder.gd`, preserving loop-time effects and wrapper dispatch. | Roster, weapon-state, weapon-save and task-lifecycle suites; add fallback/embedded weapon cases, runtime clone identity, per-soldier RNG phase order, repeated construction and mortar UI observations. Preserve existing counter behavior. |
| 4. Unit save codec | Delegate current capture/restore mapping to `resources/saves/unit_save_codec.gd`. Restore still calls the original Unit roster hook. | Weapon-save, casualty-persistence and both compatibility suites; fresh-process persistence verification and pre-refactor fixtures. Compare mapped fields/resource paths; no expanded schema. |
| 5. Casualty handler | Extract casualty selection/removal, promotion and recrewing into `scenes/game/units/combat/unit_casualty_handler.gd`. Keep Unit incoming-effect orchestration, `die()` and `_set_combat_ineffective()` dispatch. | Roster, weapon-state, casualty-persistence, close-combat and death suites. Add seeded leader/gunner/loader-loss combinations, event ordering and weapon-instance/ammo continuity. Cover both specific and random batch paths without merging them. |
| 6. Match visibility | Extract live detection, track aging, firing confidence, fog and unit display operations into `scenes/game/match/match_visibility_coordinator.gd`. Match keeps timer callbacks and frame order. | New seeded detection/aging cases: confidence threshold, LOS loss, same-hex lock, firing confidence before/after tick, dictionary replacement and debug visibility. Existing objective-visibility and match-systems suites; both map smoke checks. |
| 7. Match interaction | Extract active selection, order-wheel validation, hover preview and glow operations into `scenes/game/match/match_interaction_handler.gd`. Keep disabled mouse callback disabled. | Unit movement/arrival and match-systems suites; focused actual-scene checks for stacked-unit selection, enemy-debug selection, deselection/death, coordinate anchors, movement/attack restrictions and UI/overlay updates. |
| 8. Objectives and victory | Extract objective/condition assignment and winner evaluation into `scenes/game/match/match_victory_coordinator.gd`. Preserve clock/start sequencing on Match. | Four objective-visibility variants; existing match-clock checks. Add major/minor priority, both-team ties, actual timeout, repeated evaluation and subscriber-visible state/event order, including World's result/save response. |
| 9. Fire target policy | Extract active automatic scoring/filtering into `scenes/game/units/combat/squad_target_selector.gd`. Keep acquisition/task and Unit order side effects at the original points. Random math may move in a separate small commit after seeded parity checks. | Real-controller cases for ranking/ties, friendly occupied hexes, target movement/death/surrender, range/null rejection and cover side effects. Retain origin ground/track/mortar and mode-replacement cases. Compare RNG tail state if random helpers move. |
| 10. Fire impact resolver | Extract synchronous `fire_at()` body into `scenes/game/units/combat/squad_hit_resolver.gd`; original wrapper and coroutine dispatch remain. | Dedicated real-resolver bullet/HE/grenade/mortar cases with seeded RNG, multiple ordered targets, current/friendly occupants, cover/stress, suppression, deferred casualties and source identity. Verify RNG continuation. Existing death, roster, weapon-state and close-combat suites. |
| 11. Close-combat enrollment | Extract only active same-hex enrollment/refresh to `scenes/game/combat/close_combat_coordinator.gd`. Preserve `_on_unit_entered_hex()` order. | Existing close-combat/death/arrival suites plus actual Match cases for reuse/new-instance creation, roster loss, movement stop, surrendered/broken participants and signal unsubscription. No prototype activation. |
| 12. Match spawning | Extract spawning to `scenes/game/match/match_unit_spawner.gd` while retaining dynamic/save wrappers and distinct path order. Keep authored scenario setup in World/Match. | Characterize authored startup, dynamic spawn and saved-unit spawn separately: `_ready`/property order, exact signal wiring, groups, registry/HQ links, roster creation, terrain and stable scene paths. Run persistence/compatibility and repeated-match task-lifecycle checks. |

Stop after a batch if parity cannot be established; keep the last verified extraction and address the uncertainty separately. Do not roll several coupled changes into one large migration.

Optional later work: extract contact reporting once the memory-cleanup defect has an explicit disposition, and smaller synchronous firing-preparation blocks once the async suite covers overlapping ticks, retargeting during flight, reload/setup/acquisition, movement and owner removal. Keeping cohesive lifecycle/coroutine orchestration in the original scripts is an acceptable final design.

## Existing coverage and gaps

The current 13 regression scenes cover roster/cache consistency, runtime weapon independence and recrewing, persistence/legacy paths, movement/arrival/order replacement, death cleanup, launched-projectile survival, task lifetime, active close combat, origin targeting, objective visibility and elapsed-time occupation/clock behavior.

However, `FireProbe` in `match_systems_regression.gd` and `ImpactProbe` in `unit_death_regression.gd` override `fire_at()`. They protect firing lifecycle and dispatch, but do not establish parity for the actual casualty/suppression algorithm. Batch 10 requires dedicated real-resolver coverage. Existing objective/clock assertions likewise do not cover all winner-priority and signal-observation branches. Editor recipes, automatic target ordering, probabilistic detection and the separate spawning paths need their focused cases before extraction.

For final validation, run these existing scenes plus any new characterization suites:

- `casualty_persistence_regression`, `close_combat_regression`, `faction_save_compatibility_regression`, `match_systems_regression`, `objective_visibility_regression`, `save_path_compatibility_regression`, `soldier_task_lifecycle_regression`, `unit_arrival_regression`, `unit_death_regression`, `unit_movement_regression`, `unit_roster_regression`, `weapon_save_regression`, `weapon_state_regression`.
- Run objective visibility for default, `--allies`, `--defend` and `--allies --defend`.
- Run weapon-save and casualty-persistence again in fresh processes with `-- --verify-persistence`, using the fixtures/user-data location written by their first runs.

That is 18 existing runs before adding new suites. Preserve legacy fixtures rather than rewriting them to current paths. Run `python3 tests/check_gdscript_conventions.py` and the project/autoload-aware parser check after every extraction; new helpers must be included. A fresh import alone does not validate every script or gameplay path. Keep the existing phased-controller exclusion explicit; that controller's dedicated repair/coverage belongs to its separate plan.

Finish with Default Map and Orchard Road active-match smoke checks, and an interactive review of authoring, selection, previews, orders, fog, command links, countdown and results. Check repeated startup/shutdown and resource/task lifetime. Compare observed diagnostics with the new baseline instead of treating known errors as refactor successes.

## Separate repairs and retirement decisions

These findings are reasons to characterize current behavior and constrain extraction, not authorization to change it:

- `Unit.cleanup_enemy_memory()` builds a filtered dictionary but never assigns it back. Contact cleanup therefore does not perform the apparent intended expiration. Do not silently repair it in a helper move.
- Match's old mouse callback and close-combat timeout return immediately; the older `update_close_combat()` helper chain has no active caller found and uses a different Soldier field convention. The formation spawner is a stub and the legacy threat-draw connection is commented. Preserve current reachability.
- Unit's per-unit `EnemyVisibilityChecker` is disabled; active geometric LOS and detection are in LOS/Match. Moving detection into that disabled component would change activation and scheduling.
- `SquadFireCalculator`/`SquadFireInput` form an unused aggregate-volley path; crew/support efficiency values in active firing are calculated without applying them. Pending rounds have no active flush found. Do not reconnect/apply these while splitting code.
- Static inspection found the squad AI calling `squad_fire.set_target()`, which the fire controller does not define. Saved-unit loading checks a loaded scene but currently instantiates the configured Unit scene instead. API/scene-selection repairs require separate tests and changes.
- Existing Orchard Road defense-controller movement errors, debug-save diagnostics and shutdown resource warnings need baseline comparison. The retained phased controller and development-probe repairs remain in their existing plans.

## Completion criteria

An implemented batch is complete when its original callers and test overrides still work; its responsibility is behind one documented helper boundary; authoritative state, RNG consumption, event order, save paths and lifecycle behavior match the baseline; and its focused coverage, import/parser/convention checks and relevant regressions pass without new diagnostics.

This planning task is complete with the responsibility/dependency analysis and staged coverage plan above. Implementation has not begun. The recommended next implementation batch is loadout-template extraction after its characterization coverage is in place.
