# Company command

Match setup automatically creates company command when a team has more than one
combat platoon. Membership comes from `Unit.company` and `Unit.platoon`.
Platoon headquarters stay with their platoon; company headquarters receive a
separate support planner. An HQ without surviving combat squads remains a
support unit. A force with one combat platoon uses the original planner.

The existing `PlatoonAi` and `PlatoonAi2` nodes remain the team entry points for
scenario goals, AI controls, and inspection. Their `company_command` delegates
tactical work to one `PlatoonAI` child per platoon. The team entry point aggregates
published squad advice; child missions cannot overwrite the team's objective.

## Missions

- Scenario duties select whole platoons. Required garrison and exit counts still
  select the necessary squads inside those platoons. One platoon does not receive
  competing objective missions. Busy accepted duties retain their ownership.
- Platoons attacking the same objective in the same company receive support and
  maneuver roles. With three eligible platoons, one remains in reserve. Separate
  companies retain independent role assignments.
- Maneuver requires an established firing position in the designated support
  platoon. A proposed position or a squad still setting up does not count.
  Losing support cancels owned advancing routes; units recenter in their current
  hex using the existing movement behavior. The last covering squad retains its
  position while a supported platoon is moving or fighting in close combat.
- A disabled maneuver platoon deploys the company reserve. During defense, an
  observed good-order enemy within two hexes of the objective also deploys it.
  The reserve returns after eight quiet seconds and completion of its bound.
- Defensive platoons receive separate terrain sectors across their company's
  protected objectives. Sector size scales with combat strength, within the
  mission's area limit. Sector ownership stays fixed through routine position
  reassessments; objective and roster changes rebuild it.
- Explicit whole-force withdrawal overrides support and reserve roles and
  includes headquarters. Existing morale and route restrictions still apply.

All platoon planners share destination reservations and recheck live occupancy
before issuing a move. Occupation and exit goals retain their required capacity.
Runtime spawns register automatically; casualties, surrender, and exits update
platoon membership. Dropping to one platoon restores its original mission control.
AI OFF cancels subordinate AI orders while preserving intervening player orders.

`CompanyAI.diagnostics` describes platoon roles. Squad assignment dictionaries
contain `company_role` and `company_platoon`; position result features contain
`company_mission`.

## Defensive deployment

Occupation is a garrison requirement, not an instruction to switch the entire
platoon to assault. An uncontested objective retains defensive posture while its
assigned garrison moves to the marker. A confirmed enemy occupying the objective
can trigger a counterattack by a maneuver-capable platoon. Mortars cannot receive
direct hunting duties or take ownership of the rifle platoons' defensive sectors.

Strategic duties come exclusively from the AI side's own victory conditions.
Player victory conditions do not create capture-denial, counter-exit, or
force-preservation missions. An AI side without geographic objectives stays
anchored to its own force.

The platoon does not allocate an additional automatic guard when a scenario duty
already protects its objective. Squads remaining after scenario allocation cover
approaches. Small forces retain all needed combat squads; larger forces can keep
a capable reserve, with the existing readiness checks deploying it when needed.
Company command budgets one mobile reserve squad per six capable combat squads
across its objectives. A platoon can supply that squad only after retaining its
garrison and a front squad. Every capable squad in an existing whole-platoon
reserve counts against this budget.
Reserve ownership stays stable while the force and mission remain suitable.

The shared platoon planner uses covered terrain, approach corridors, weapon range
and LOS for both company and single-platoon defense. When no manual threat axis
is supplied, an authored enemy entry marker provides a low-confidence initial
approach. Observed and remembered contacts take precedence over that assumption.

Approach squads compare a bounded shortlist during initial deployment instead of
immediately accepting their current hex. The shortlist ranks approach coverage,
cover, travel, mutual support, spacing and forward depth. Spacing is a soft
preference: it does not prohibit adjacent positions or necessary objective
garrisons. Its bonus cannot by itself justify abandoning useful connected cover.
Only established squads contribute mutual support; destination reservations
influence spacing without promising future covering fire.

For a platoon with at least three capable combat squads, an approach squad with
more than two hexes of weapon range must make at least two hexes of progress
toward its assigned threat source. Merely seeing the approach from beside the
objective no longer fulfils that screen duty.
Smaller outposts keep compact positions without this stand-off requirement.
If the complete forward search finds no safe position, the planner searches for
a closer fallback with the same coverage, exposure and handoff checks. Advice
marks this case as `screen_fallback`; subsequent planning retries the forward
screen after any accepted movement and setup finish.

The existing exposure limits, screen preservation, safe handoffs and position
commitments remain in force. An occupation duty retains objective protection;
other defensive assignments can intercept farther forward without inventing a
physical garrison requirement. Advice exposes `approach_duty`, `assigned_coverage`,
`formation_crowding`, `mutual_support`, `forward_depth`, `forward_progress` and
`screen_fallback` for inspection.

## Validation

Run `tests/company_ai_regression.tscn` to exercise a three-platoon company on the
authored village map, real budgeted position planning, support handoffs,
destination conflicts, objective ownership, whole-force withdrawal, reserve
deployment, AI controls, runtime reinforcements, and single-platoon fallback.
Pass `-- --defend` to exercise real defensive advice inside the assigned sectors.

Run `tests/defensive_deployment_match_regression.tscn` for Battle for Alderbrook,
`-- --outpost` for Probe The Outpost, and `-- --single` for its single-platoon
debug scenario. These checks keep the authored victory conditions active, run
real movement, and verify garrison capacity, distinct sectors, approach coverage,
forward deployment, safe routes and the difference between holding and attacking.
Combat damage is disabled to isolate positional decisions.

Run `godot --headless --path . --fixed-fps 60 tests/defensive_idle_match_regression.tscn`
for three simulated minutes of Battle for Alderbrook with normal movement,
combat and morale while the player receives no orders. It checks actual settled
positions, friendly support, minimum physical garrisons and the company reserve
repeatedly after the opening. The `-- --outpost` and `-- --single` variants run
their authored smaller scenarios for two minutes and respect explicit hold-to-exit
policies. Coverage expectations account for surviving capable squads remaining
after scenario duties; a squad routed by combat cannot count as a screen.
