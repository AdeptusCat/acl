The unit forwards `unit_arrived_at_hex` to its squad action controller. This signal means the whole movement path has finished. Intermediate waypoint stops and the transition from the covered assault path into its exposed segment do not complete the action.

The controller uses its existing completion rules: move, defend, assault, and local withdrawal establish a position at the assigned destination, then the establishing timer advances to holding. A stopped move short of its objective holds at the recentered hex. Rout completion keeps the existing regrouping state and timer. Arrival notifications are ignored while movement continues, when their hex differs from the unit's occupied hex, or when the unit is dead or surrendered. Repeated arrival notifications do not restart the establishing timer.

Assumption: ordinary move orders retain the existing establishing-then-holding behavior, including when `take_and_hold` is false. This change reconnects the action state machine without introducing different order semantics.

Regression check:

```sh
godot --headless --path . tests/unit_arrival_regression.tscn
```

Coverage checklist:

- [x] Actual unit setup and movement-to-arrival signal connections.
- [x] Move and defend arrival, intermediate waypoints, and arrival at the current hex.
- [x] Covered and exposed assault paths, including attacks with one segment.
- [x] Withdrawal, rout completion, establishing timers, and regrouping timers.
- [x] Player Move/Stop, Hold, cleared orders, replacement orders, and direct AI movement.
- [x] Duplicate and late arrival notifications, inactive units, and timer cancellation.
- [x] Battlefield restart and controller cleanup.

Verification limits: movement steps are driven directly while automatic simulation is frozen; the real action timers run with shorter waits. This checks completion transitions without validating AI tactics or combat balance. Empty or invalid paths remain outside this fix. The existing missing debug-save startup message and shutdown resource warnings are separate issues.
