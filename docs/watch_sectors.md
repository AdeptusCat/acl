# Watch sectors

Select a friendly squad, hold right click toward a battlefield hex, select
**Watch**, and release. The hex sets a world-space bearing; the order does not
move the squad or replace its movement or fire orders. Watching the squad's
own hex is rejected. A direction can point toward blocked terrain, but the
order never grants line of sight through it.

Squad details provide **Narrow · 60°**, **Normal · 120°**, and **Wide · 180°**.
**Auto** clears the assignment and restores automatic attention. Width can be
chosen before assigning a bearing. The normal arc is the default, and new
assignments retain the selected width.

The selected squad's gold arc shows its assigned sector. The short drawing
indicates direction, not maximum detection range. The existing focus arrow
shows actual attention. A diverted assignment turns grey, and the details
panel explains when attention is diverted or the watch is reduced by movement.
Unselected squads and normally inspected enemies do not display watch arcs.

## Observation tradeoffs

These are directional acquisition multipliers before observer quality and
current commitment. They apply to silhouette and muzzle-flash acquisition;
terrain, distance, movement, morale and LOS retain their existing rules.

| Arc | Centre | Directly behind |
| --- | ---: | ---: |
| Narrow, 60° | 1.65 | 0.30 |
| Normal, 120° | 1.40 | 0.475 |
| Wide, 180° | 1.15 | 0.65 |

The rate changes smoothly from centre to neutral at the arc boundary, then
toward the rear multiplier. Outside detection stays possible. Wider arcs cover
the flanks better; narrow arcs concentrate observation. A watch sector never
restricts which detected enemies the squad may fire upon.
The separate [fire discipline](fire_discipline.md) setting controls whether
automatic shooting is permitted; holding fire does not weaken the watch order.

Stationary squads normally commit fully to the assignment. Moving squads keep
the bearing with 45% commitment; existing movement penalties also apply.
Distant visible contacts reduce that commitment by 20%, without replacing the
assignment. Pinned squads keep the order with their existing lower observation
quality. The order cannot bypass soldiers' existing cover and cowering
restrictions on weapon handling.

## Temporary reactions

An explicitly ordered firing target takes priority. Otherwise, detected enemies
within two hexes and received-fire bearings can divert actual attention. The
strongest immediate bearing wins, preventing opposing threats from averaging
into an empty direction. Received-fire bearings expire through the existing
four-second fire-pressure memory; very weak remnants do not sustain diversion.
Once the immediate reason passes, attention returns to the stored watch sector.
Hidden units cannot create a diversion from their live position, and distant
remembered contacts cannot erase the assignment.

Acquisition snapshots direction, width and commitment before a new contact
pulls attention away. Initial soldier reactions use that snapshot. Soldiers
inside the watched arc have better preparation; reactions outside it grow
slower toward the rear. Individual reaction variation, weapon raising, aiming,
cycling and protective behavior remain in the existing soldier system.

## Persistence and restrictions

Moving and Stop preserve the assignment. Routing, surrender, elimination and
leaving the map clear it. Pinned squads may receive Watch orders. Routed,
surrendered, inactive squads and squads in close combat cannot receive them.
Mission completion blocks both the command wheel and details controls. Enemy
inspection hides the controls unless explicit debug enemy control is enabled.

Unit saves retain the normalized world-space bearing and selected width.
Older saves default to automatic attention with a normal arc. Invalid saved
bearings are discarded and widths are clamped to the supported range.

`tests/watch_sector_regression.tscn` exercises directional tradeoffs, temporary
diversions, movement, targeting outside the arc, acquisition snapshots, soldier
reaction variation, controls, disk saves, overlay geometry and lifecycle cleanup.
`tests/command_interaction_regression.tscn` also exercises Watch through real
right-click input and the expanded command wheel.
