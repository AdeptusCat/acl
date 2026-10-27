# Order queues and coordinated movement

Hold **Shift** while releasing a **Move** or **Watch** command to append it. Without Shift, an accepted command replaces the queue. Stop clears it. The first Shift order adopts an existing move, so a squad already travelling can receive its next waypoint without changing its current route.

The squad details panel contains **Order queue**. It lists numbered actions, marks the current action, and lets you remove any action. **Queue Hold position** adds a final Hold. Watch and Hold remain active until removed or replaced; remove them before appending further actions.

Moves advance only after the entire route finishes, not at intermediate hexes. Each leg finds its route from the squad's position when that leg starts, using the ordinary cover and threat preferences. Queued Watch computes its bearing from the position reached after movement. A blocked leg reports the failure and keeps later orders waiting; remove that leg to continue. Pinning pauses the queue and recovery rebuilds the interrupted move. Rout, surrender, death, map exit, close combat, and replacement orders cancel queued execution.

## A shared waiting step

1. Select a squad and add its approach moves.
2. In Order queue, click **Add squad to group**.
3. Select each other participating squad, add its approach moves, and add it to the group.
4. Click **Queue group wait**. The same numbered group, such as G1, is appended to every participant's queue. Group selection then clears for the next plan.
5. Select each participant and append its following Move and final Watch or Hold.
6. On any participant, click **Start group G1 when ready**. Squads finish their approach and release the shared wait once all remaining participants are ready.

Squads can move into position during planning, but they cannot leave the waiting step before the group is started. A pinned squad remains a blocker. Readiness appears in squad details; its tooltip identifies approaching, pinned, or blocked members. Cancelling or removing a member's waiting step, surrendering, routing, dying, leaving the map, or entering close combat removes that member from the wait so survivors can continue. Clearing the group selection only clears the prospective selection; it does not cancel waiting steps already queued.

The selected squad shows numbered queued destinations. Dashed connections show the planned sequence; the live route retains its terrain-following line. Shared G markers appear at participants' planned waiting positions, including when another squad is selected. Future legs are routed when they begin, so dashed connections are not promised travel paths.

This first implementation supports Move, Watch, Hold, and shared waits. Timed suppression, delays, and arbitrary action dependencies are not included. Queues are runtime battle orders and are not stored in campaign unit saves.

Run `tests/order_queue_regression.tscn` for movement sequencing, final actions, replacement and cancellation, pin recovery, blocked routes, coordinated release, removed members, and panel controls. Pass `-- --capture` with rendering enabled to capture the order panel.
