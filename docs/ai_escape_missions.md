# Escape missions

Add an `EscapeMissionPolicy` to a scenario's **AI → AI Escape Policies** and link
its **Exit Condition** to that side's existing exit victory condition. Roadblock
uses this policy for the Axis column. ATTACK/DEFEND continues to control ordinary
tactical missions on other maps.

An escape mission remains active during pinning, recovery, and an unattainable
victory quota. It does not redirect the column into enemy occupation-denial
duties. By default every surviving unit, including headquarters, receives an
exit duty; the normal movement and morale restrictions still govern execution.
Disable **Withdraw Entire Force** to assign only the remaining quota. Disable
**Include Headquarters** to retain headquarters explicitly.

Each squad searches complete corridors to all matching exits. Routes minimize
travel time plus weighted exposure time and an open-ground cost. Enemy fire and
remembered contacts increase cost rather than turning traversable ground into
a wall. An observed enemy's hex remains blocked, as do neighboring hexes while
that enemy is unsuppressed. Corridors can bend away from the exit and exceed
ordinary tactical movement bounds. Execution follows the selected corridor and
checks updated knowledge before retaining it.

A completely sealed front still creates a coordinated breach. Suppressing the
blocker enough to open a passage releases that breach and its covering-fire
roles on reassessment. Headquarters wait for an exit corridor instead of
receiving an assault duty. Safe exit movement does not require company support.

Hold-to-exit fallbacks use the same corridor planning only after their existing
withdrawal trigger activates. Their confirmation, strength, objective-loss and
deadline rules remain unchanged. Scenarios without either policy retain their
ordinary attack, defense and goal-selection behavior.

Run `tests/roadblock_breach_match_regression.tscn` for authored bypasses, HQ
eligibility, pinning and recovery, sealed fronts, and release after suppression.
Run `godot --headless --path . --fixed-fps 60 tests/roadblock_escape_match_regression.tscn`
for a normal match with live combat, morale and no player orders.
