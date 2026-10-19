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
travel time plus weighted exposure time and an open-ground cost. A bypass must
also stay below **Maximum Bypass Visibility** and **Maximum Bypass Risk**.
Visibility accounts for distance, LOS hindrance and contact confidence. Known
effective covering fire makes an otherwise open gap require a coordinated fight.
A nearly unseen route can be taken immediately. Remembered contacts increase
route cost without proving that the passage is still defended.
An observed enemy's hex remains blocked, as do neighboring hexes while that
enemy is unsuppressed. Corridors can bend away from the exit and exceed ordinary
tactical movement bounds. Planning, route retention and execution use the same
covering-fire checks.

A front covered by effective observation or fire creates a coordinated breach.
Suppressing one blocker releases that breach only when the rest of the route
is also usable. The check covers the combat column: a forward HQ cannot release
rifles that are still cut off. Headquarters wait for an exit corridor instead
of receiving an assault duty. Concealed exit movement needs no company support.

Hold-to-exit fallbacks use the same corridor planning only after their existing
withdrawal trigger activates. Their confirmation, strength, objective-loss and
deadline rules remain unchanged. Scenarios without either policy retain their
ordinary attack, defense and goal-selection behavior.

Run `tests/roadblock_breach_match_regression.tscn` for authored bypasses, HQ
eligibility, pinning and recovery, sealed fronts, and release after suppression.
Run `godot --headless --path . --fixed-fps 60 tests/roadblock_escape_match_regression.tscn`
for a normal match that verifies actual covering fire, morale and no player orders.

Battles end when a side's last remaining units are destroyed or surrendered. Both sides'
existing victory conditions are compared immediately, including conditions
normally checked at the deadline. Unfinished occupation timers stay unfinished;
elimination does not automatically award a victory. This also ends occupation
overtime. Earlier exits remain credited and do not keep a defeated rear guard's
battle running. A force that only exits retains its authored completion rules.
Run `tests/force_defeat_regression.tscn` for death and surrender completion,
major/minor outcomes, draws, player elimination, and overtime.
