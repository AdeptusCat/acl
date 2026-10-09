Close combat owns its participant flags and keeps its fighter lists in sync with each unit's runtime roster. Surrender, death, forced hex displacement, and leaving the scene remove the unit and all of its soldiers from the encounter. Ranged casualties and roster changes are reconciled before attacks, and completed close-combat casualties refresh the targets before the next actor acts.

An encounter ends as soon as either side has no eligible soldiers. It stops its timer, hides its marker, disconnects participant signals, clears the combat flags and references, and queues itself for deletion. Reinforcements arriving in the same frame can create a new encounter; the old instance cannot resume or clear the new encounter's flags.

Participants cannot move out of an ongoing encounter. Admission preserves the attacker's entry role, clears its action and remaining path, and stops movement immediately in the occupied hex. Direct, AI, withdrawal and attack-phase movement cannot restart it; position queries and execution also reject engaged squads, including advice computed before entry. A hex-entry callback can start combat during a movement step, so that step must stop without emitting a destination arrival or advancing to another waypoint. Resolution releases the lock but does not resume canceled movement; a fresh order is required. A rout attempt in close combat has no legal route and uses the existing failed-rout surrender outcome. Forced displacement remains a lifecycle cleanup case rather than a movement option.

Removal from combat does not delete soldiers, corpses, or equipment history. Death records remain in the unit's casualty roster and the persistent casualty archive. Surrendered soldiers remain alive in their unit and are not recorded as deaths.

Regression check:

```sh
godot --headless --path . tests/close_combat_regression.tscn
```

The scene uses actual units and the game controller, with automatic simulation frozen so lifecycle transitions and seeded combat ticks can be checked independently. It also checks the scene's real timer and its cancellation. Its casualty archive is isolated under `user://tests/close_combat/`.

Coverage checklist:

- [x] Admission, reinforcements, and duplicate joins.
- [x] Surrender, direct death, ranged casualties, and close-combat elimination.
- [x] Live roster replacement and reconciliation without notifications.
- [x] Surrender from inside a casualty callback and final elimination during a tick.
- [x] Last-side cleanup, stopped timers, hidden markers, and same-frame reentry.
- [x] Movement locks for both teams, cached advice rejection, interrupted paths and fresh orders after resolution.
- [x] Failed rout, forced displacement, return, freed participants, instance deletion, and battlefield restart.
- [x] Preserved casualty and equipment records, including archive reload.

Verification limits: most combat ticks are driven directly for reproducibility; the regression does not validate AI tactics or combat balance. The prototype's missing `user://matches/debug.tres` startup message and existing shutdown resource warnings are separate issues.
