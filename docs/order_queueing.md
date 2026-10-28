# Selection and order queues

Click a battlefield squad or roster row to select it. **Shift-click** adds or removes a friendly squad from the selection. Roster Shift-clicks preserve the camera position. Drag a rectangle with the left mouse button to select friendly squads whose counters intersect it. Drag in any direction; **Shift-drag** adds to the existing selection. An ordinary empty click clears selection. Enemies remain individually inspectable and are excluded from multiple selection.

Every selected squad is highlighted on the battlefield and in the roster. The most recently selected squad supplies the details and order queue shown in the panel; the formation label also shows the selection count.

Wheel commands apply to every selected squad. Each squad checks its own command restrictions and finds its own route to the chosen hex. Unavailable squads are skipped, and feedback reports how many accepted the order. Selecting another squad while the wheel is open invalidates that wheel's pending command.

Hold **Shift** while releasing **Move** or **Watch** to append the command to every selected squad's queue. Without Shift, an accepted command replaces that squad's queue. Stop clears it. The first Shift order adopts an existing move without replacing its route.

The **Order queue** section lists numbered actions for the active squad and lets you remove them. A final move stops at its destination automatically. Watch remains active until removed or replaced; remove it before appending further actions. Shared waiting steps and coordination groups have been removed.

Moves advance only after the entire route finishes. Each leg uses the squad's actual position when it begins, with the ordinary cover and threat preferences. Watch computes its bearing from the final position. A blocked leg reports failure and waits for removal. Pinning pauses the queue; recovery rebuilds the interrupted move. Rout, surrender, death, exit, close combat, and replacement orders cancel queued execution.

Selected squads show numbered queued destinations and dashed connections. These show the sequence, while the live route shows the actual path. Queues apply to the current battle and are not stored in campaign unit saves.

Validation scenes: `tests/multiple_selection_regression.tscn`, `tests/order_queue_regression.tscn`, `tests/command_interaction_regression.tscn`, `tests/stacked_squads_regression.tscn`, and `tests/squad_roster_hud_regression.tscn`.
