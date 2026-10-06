# Phased platoon controller investigation

Investigated on 6 October 2026 through source, authored scene references, the preserved pre-refactor baseline, and captured integration backtraces. No gameplay code was changed or the dormant tactical loop enabled.

## Current behavior

`ai/platoon/phased/platoon_phase_controller.gd` declares `PlatoonAiController`. Its `_ready()` registers the configured squads, initializes an attack objective, and prints startup messages. Its `_physics_process()` immediately returns at line 98, before checking `is_active`, advancing timers, or calling `_tactical_tick()`. The same return exists in the unchanged pre-refactor baseline. No external callers of its tactical tick or mission setter were found in current project code.

The world scene contains two instances attached to Allied platoon HQ units:

| Scenario | Configuration | Actual tactical execution |
| --- | --- | --- |
| Orchard Road / Outpost Probe | `is_active = true`; HQ and two rifle squads; default objective `(8, 4)` | Disabled by unconditional return |
| Default Map / Outpost Probe | Default `is_active = false`; HQ and two rifle squads; objective `(11, 13)` | Disabled by unconditional return |

Scene references require the script and scene files to remain loadable until those references are removed. They do not make this controller necessary for current movement or combat decisions.

## Intended responsibility

The dormant code describes a platoon-level coordinator for a coordinated objective attack. Every nominal 0.5-second tactical tick would read squad strength, stress, cohesion, and morale; merge enemy tracks into a shared blackboard; update suspected enemy locations and objective beliefs; choose a tactical phase; generate tasks; assign squads to roles; and issue movement/fire orders.

| Phase or feature | Intended behavior in the code |
| --- | --- |
| Planning and approach | Rally squads, approach the objective, and provide overwatch/security. |
| Contact and suppression | Select a contact, assign covering fire, and stage an assault squad. |
| Maneuver and assault | Move an assault group toward the objective while retaining support and security. Assault movement is held until support is ready. |
| Consolidation | Require physical proximity and observation plus sufficiently low enemy suspicion before treating the objective as clear; secure it and regroup. |
| Reorganization and withdrawal | Change plans when platoon effectiveness drops or stress becomes excessive. |
| Formation control | Allocate column/wedge slots, avoid duplicate destinations, and wait for squads to settle before advancing the formation. |

Role assignment scores squad type, effectiveness, cohesion, stress, and distance. The design favors rifle squads for assault/probing and machine guns or mortars for support. Actual issued orders use `Unit.order()` and movement controls; much role/task information is recorded as metadata.

The value of this layer would be cooperation between squads: one element covers while another moves, and the platoon changes its overall plan as contact and morale change. This is an inference from the task builders and phase transitions, not currently observed gameplay.

## Relationship to active AI

The separate `PlatoonAI` in `ai/platoon/defense/platoon_defense_controller.gd` receives a `MissionOrder` from `DefenseDirector`. Match startup calls both defense directors. This implementation selects defensive positions using influence maps and threat axes, retains a reserve when possible, and periodically issues movement orders. It does not call the phased controller.

`SquadAiController` makes individual squad decisions and executes its own orders. It does not depend on the phased blackboard or task objects. `EnemyTrack`, `SquadTacticalState`, and `PlatoonTypes` are shared with current gameplay, so retiring the phased prototype must preserve those shared types.

The phased implementation is therefore a separate, disabled attempt at coordinated objective tactics, rather than a necessary wrapper around the active defense controller.

## Readiness and earlier diagnostic correction

Enabling the update loop would need implementation review and tests. For example, the controller calls `blackboard.get_hex_distance()`, which `PlatoonBlackboard` does not implement. Some blackboard helpers read `EnemyTrack.hex`, while the current track stores `last_known_hex`. These are source-level mismatches in dormant code; they were not executed during this investigation. Controller ownership would also need review: the Default Map's Allied rifle squads are referenced by both the phased prototype and the active defense controller.

The earlier reported Orchard Road `follow_cube_path` error does not originate in the phased controller. Captured backtraces show `DefenseDirector.assign_order_to_platoon()` → `PlatoonAI.receive_mission_order()` → defense movement orders → `Unit.order()` → `SquadActionController._start_move_on_path()`, where `movement` is `Nil`. The same failure was captured before and after the file refactor. Refactor documentation has been corrected accordingly.

## Support decision

Decision confirmed on 6 October 2026: retain the phased controller as unfinished work requiring repair and dedicated coverage. Preserve its implementation, scene instances, and associated types. Archiving is no longer a pending decision.

The tactical loop remains disabled while repair and coverage are pending. Existing smoke checks establish scene compatibility, not correctness of its tactical behavior. Simply changing `is_active` does not enable it. The [repair and coverage plan](phased_controller_repair_plan.md) defines the work and completion criteria; implementation has not started.
