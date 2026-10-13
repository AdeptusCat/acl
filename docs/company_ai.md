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
- Defensive platoons receive separate terrain sectors around the objective.
  Sector ownership stays fixed through routine position reassessments.
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

## Validation

Run `tests/company_ai_regression.tscn` to exercise a three-platoon company on the
authored village map, real budgeted position planning, support handoffs,
destination conflicts, objective ownership, whole-force withdrawal, reserve
deployment, AI controls, runtime reinforcements, and single-platoon fallback.
Pass `-- --defend` to exercise real defensive advice inside the assigned sectors.
