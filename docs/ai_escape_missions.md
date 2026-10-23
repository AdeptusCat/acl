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
travel time plus weighted exposure time, observation time and an open-ground cost.
**Concealment Weight** favors longer routes behind LOS hindrance and concealed
terrain over short visible road crossings. Observation cost uses contact confidence
and distance, so crossing close to a known defender costs more even while its
current firepower is low. It is a preference: an entirely observed map still
allows escape, and remembered contacts never become hard blockers. Seeing an enemy
across open ground increases that cost without creating a pursuit objective.
Enemy fire can seal a close guarded gap (within two hexes) or a terrain
bottleneck with at most two usable neighboring hexes. Such a passage requires
both observation above **Maximum Bypass Visibility** and effective fire above
**Maximum Bypass Risk** before it triggers a coordinated fight. Visibility
accounts for distance, LOS hindrance and contact confidence. A nearly unseen
route can be taken immediately. Remembered contacts increase route cost without
proving that the passage is still defended.
An observed enemy's hex remains blocked, as do neighboring hexes while that
enemy is unsuppressed. Corridors can bend away from the exit and exceed ordinary
tactical movement bounds. Planning, route retention and execution use the same
covering-fire checks. A unit already inside a defended area can disengage through
less exposed cells farther from that enemy. Observation of its open starting
position does not license entering a separate guarded bottleneck.

A front sealed by adjacent defenders or effective fire at guarded passages creates a coordinated breach.
Suppressing one blocker releases that breach only when the rest of the route
is also usable. Escape availability is assessed for each squad. A cut-off squad
does not send squads with usable bypasses back into a fight. A platoon whose
combat squads can all escape withdraws without taking a company assault or
covering-fire role. An opened corridor immediately releases an accepted fighting
bound, even while the strategic mission keeps the same identity.
Pinned, panicking, or otherwise immobile squads retain their escape assignment
while recovering. Their current firing lane cannot create a breach duty for
the mobile column. A squad unable to move does not invalidate the other squads'
planning results. Its HQ keeps a recovery support duty, and the squad resumes
its escape mission when it can move again. If every combat squad is pinned,
headquarters support recovery instead of receiving an assault mission.
A forward HQ cannot release mobile rifles that are still cut off.

Live escape/breach reassessment uses a resumable search with a 1,500-microsecond
per-frame scheduling target. Cell evaluation, safe-corridor flooding,
origin-specific disengagement, weighted breach search, and path reconstruction
all resume across frames. Defender coordinates and suppression flags are reused
within each search. Published missions and squad assignments remain in place
until a complete replacement is available. New snapshots, changed squad origins
or mobility, changed defender activity/suppression, and edited bypass policies
invalidate pending work. Reassessment waits 0.5 seconds after publication before
starting another search; response latency includes its scheduled slices.
Initial mission setup and frozen test callers retain a synchronous API using
the same search implementation.

During the breach, platoon headquarters follow
their own squads and company headquarters follow their company in protected
support bounds. Calm rifle squads and support weapons both receive leadership
priority during withdrawal. Headquarters may take short open bounds within their
fire-risk and crossing budgets and avoid unsuppressed defenders. Once a corridor
opens for their formation, they replace support bounds with complete exit orders.
Headquarters without surviving subordinates seek their own exit. Concealed exit
movement needs no company support.

Hold-to-exit fallbacks use the same corridor planning only after their existing
withdrawal trigger activates. Their confirmation, strength, objective-loss and
deadline rules remain unchanged. Scenarios without either policy retain their
ordinary attack, defense and goal-selection behavior.

Run `tests/roadblock_breach_match_regression.tscn` for authored bypasses, HQ
eligibility, follow movement, split-column bypasses, interrupted fighting bounds,
support-to-exit transitions, actual pinning callbacks, queued planning during
pinning, recovery, sealed fronts, and release
after suppression.
Run `godot --headless --path . --fixed-fps 60 tests/roadblock_escape_match_regression.tscn`
for a normal match that verifies the authored escape quota under live fire,
morale, and movement by all three headquarters without player orders.
Run `tests/roadblock_pursuit_regression.tscn` for a live sighting-only reproduction:
player units move behind the column while damage and morale changes are disabled,
and every rifle and headquarters must keep escaping through the western exits.
Run `tests/influence_positions_regression.tscn` for concealed detours, safer exit
selection, remembered sightlines and escape when the concealed bypass is unavailable.

Run `godot --headless --path . --fixed-fps 60 tests/roadblock_performance_regression.tscn`
for stationary authored-force frame timing, repeated mission publication,
pending-mission retention, sliced/synchronous result parity, expired deadlines,
and invalidation after movement, pinning, policy changes, or snapshot replacement.
The breach match regression also checks sliced weighted-search parity on a
sealed front. Timing checks measure CPU simulation, not rendering performance.

Battles end when a side's last remaining units are destroyed or surrendered. Both sides'
existing victory conditions are compared immediately, including conditions
normally checked at the deadline. Running occupation timers complete for the side
whose enemy was defeated, provided enough good-order squads still occupy each
hex. Unstarted, abandoned, or undermanned captures remain incomplete; objectives
with several markers still require every marker. Other victory requirements
remain unchanged. This also ends occupation
overtime. Earlier exits remain credited and do not keep a defeated rear guard's
battle running. A force that only exits retains its authored completion rules.
Run `tests/force_defeat_regression.tscn` for death and surrender completion,
major/minor outcomes, draws, player elimination, running captures, and overtime.
