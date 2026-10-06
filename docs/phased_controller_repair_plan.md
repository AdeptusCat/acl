# Phased controller repair and coverage plan

Status: retained as unfinished work by user decision on 6 October 2026. Repair and dedicated regression coverage are pending. The current tactical loop remains disabled. See the [investigation](phased_controller_investigation.md) for verified behavior and scene dependencies.

## Scope

Develop the existing coordinated objective-attack controller into a working, tested component. Preserve the shared `EnemyTrack`, `SquadTacticalState`, and `PlatoonTypes` contracts used by current gameplay. Keep repairs focused on the phased controller and its integration; the existing defense-controller movement failure remains a separate issue.

## Repair order

1. **Repair stale API calls and establish a runnable test fixture.** Replace calls to the nonexistent blackboard distance helper using the established hex-distance service. Update stale `EnemyTrack.hex` access to the current tracking contract. Review other dormant calls against current unit, movement, combat, and LOS APIs. Build an isolated fixture that explicitly invokes tactical ticks without activating the authored scenarios.
2. **Validate the mission and phase model.** Check objective initialization, cooldowns, plan refresh, contact confidence, objective verification, and reorganization/withdrawal thresholds. Investigate whether the persistent objective-suspicion zone and clear-confidence cap can prevent consolidation indefinitely. Ensure reading or aging enemy information does not mutate shared tracks unexpectedly.
3. **Make task execution reliable.** Verify role assignment, formation destinations, support readiness, actual movement/fire/assault commands, hold behavior, and duplicate-order suppression. Handle null, dead, removed, and ineffective squads; stop assigning tasks to invalid instances. Confirm that task names correspond to the commands actually issued.
4. **Resolve controller ownership and lifecycle.** Give each squad one platoon controller that issues its orders. The Default Map currently references the same Allied rifle squads from both implementations. Bind squads from the selected scenario and issue orders only after their components are ready. Define how control is acquired and released on startup, stop, death, and scenario changes.
5. **Integrate activation under test.** Replace the unconditional return with functioning activation and match-state guards after the preceding coverage passes. Start with an isolated phased-controller scenario, then verify the authored Outpost Probe scenes. Record the intended activation settings explicitly rather than enabling all existing instances during unrelated cleanup.
6. **Restore normal verification coverage.** Once the repaired controller passes parser and convention checks, remove its specific exclusion. Run the existing regression suites and compare active-match diagnostics against the baseline.

## Dedicated coverage

Add a phased-controller regression entry point following the repository's existing test-scene pattern. Use deterministic tactical ticks and focused fixtures; avoid assertions that only mirror private implementation details.

| Area | Observable behavior to verify |
| --- | --- |
| Activation | An inactive controller or stopped match issues no orders; an enabled, initialized controller performs tactical updates. |
| Mission lifecycle | Setting or replacing an objective resets stale plans, role assignments, formation state, and relevant timing. |
| Phase progression | A scripted attack progresses through approach/contact/support/maneuver/assault/consolidation as prerequisites change, without rapid oscillation. |
| Enemy knowledge | Fresh, stale, absent, and uncertain contacts produce appropriate decisions; the controller does not corrupt shared enemy tracks. |
| Objective verification | LOS alone does not establish that an objective is secured; physical verification and suspicion resolution can eventually permit consolidation. |
| Roles and tasks | Covering fire and assault go to suitable squads; reserves and ineffective squads receive appropriate tasks without duplicate squad assignments. |
| Support coordination | Assault movement waits for ready support and proceeds when support becomes available. |
| Formation movement | Destinations do not collide, repeated decisions do not restart identical movement, and progress waits for the required squad readiness. |
| Recovery and withdrawal | Strength and stress changes produce the intended recovery or withdrawal behavior. |
| Squad lifetime | Empty platoons and squads that die, disappear, or become ineffective do not cause invalid-instance access or stale assignments. |
| Controller ownership | The defense and phased controllers cannot concurrently issue conflicting orders to the same squad. |
| Scene integration | Authored scenarios bind the selected scenario's squads and run through startup, active ticks, and match stop without new script errors. |

## Completion criteria

- The controller's tactical loop executes in a dedicated scenario and obeys activation and match lifecycle rules.
- Dedicated regressions verify decisions and resulting orders, including invalid-squad and coordination cases.
- The repaired script is covered by ordinary parser and convention checks.
- Existing regression suites pass, and active integration checks introduce no new runtime errors.
- Documentation distinguishes validated behavior from any remaining unfinished features. Scene loading alone is not evidence of tactical correctness.
