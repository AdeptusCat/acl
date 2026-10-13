# Road to Alderbrook

A five-mission Allied campaign, available under **Road to Alderbrook** in the
normal mission menu. Win the previous mission with a minor or major victory to
unlock the next. Mission results use stable identifiers, so changing a briefing
title does not erase progression. Each mission introduces a larger force with a
fresh deployment; battle casualties are recorded by the existing save system.

| Mission | Player force | Enemy force | Default time | Major victory |
| --- | --- | --- | --- | --- |
| 1. Quiet Approach | 2 rifle squads + platoon HQ | 1 rifle squad + HQ | 10 min | Hold farm A for 15 seconds |
| 2. Orchard Outpost | 3 rifles + MG + HQ | 2 rifles + MG + HQ | 10 min | Hold A for 30 seconds and destroy 2 units |
| 3. The Roadblock | 3 rifles + 2 MGs + HQ | 2 small platoons + company HQ | 9 min | Destroy 2 units and prevent all enemy exits |
| 4. Two Crossings | 2 reinforced platoons + company HQ | 2 platoons + company HQ | 12 min | Hold A and B for 20 seconds each and exit 3 units east |
| 5. Battle for Alderbrook | 3 platoons + company HQ + light mortar | 3 platoons + company HQ + medium mortar | 15 min | Hold A, B, C for 45 seconds each, destroy 6 units, allow at most 1 enemy exit |

Every condition in a victory level must be satisfied. Exit prevention and the
final battle are assessed at the deadline. Mission selection applies the
authored time; the existing time control can still override it.

The first patrol starts outside opposing weapon range, with only two combat
squads to command. The orchard introduces a dedicated gun team, the roadblock
introduces interception, and the river crossing introduces two-platoon
coordination and leaving garrisons behind. The final battle has three separate
bridge approaches and village districts, with 17 player units against 14 enemy
units. Mortars and company command become part of the engagement.

## Minor victories and enemy behavior

- Quiet Approach: hold rally point B for 15 seconds at the deadline.
- Orchard Outpost: hold barn B for 30 seconds at the deadline.
- The Roadblock: hold A for 30 seconds and allow at most 2 enemy exits.
- Two Crossings: exit 2 units by the deadline.
- Battle for Alderbrook: hold central square B for 45 seconds and destroy 3 units.

Enemy AI is enabled and player AI is off. The roadblock enemy attacks toward its
western exits; the other enemies defend. Larger enemy formations use company
command. In the final mission, the defenders hold all three districts and have
an explicit hold-to-exit fallback linked to their central command post. Escape
is deferred until the hold fails, combat strength drops below four squads, or
the remaining travel window requires withdrawal. Their minor exit threshold is
two units, which conflicts with the player's major allowance of one. Secure the
eastern escape routes before breaking the town defense.

## Playable maps and images

All five maps are new, editable Godot scenes. The rivers have no ground or
pathfinding points outside bridge cells. Each map ships compressed line of
sight data calculated by the existing LOS service.

The images show the exact authored terrain, deployments, and objective
coordinates. They are designer overviews; the game's normal fog of war and
enemy-intelligence briefing remain in effect.

- [Campaign overview](maps/campaign_overview.png)
- [Quiet Approach](maps/01_quiet_approach.png)
- [Orchard Outpost](maps/02_orchard_outpost.png)
- [The Roadblock](maps/03_the_roadblock.png)
- [Two Crossings](maps/04_two_crossings.png)
- [Battle for Alderbrook](maps/05_battle_for_alderbrook.png)

## Authoring and verification

The campaign definition is `resources/campaigns/road_to_alderbrook.tres`; its
mission scenes are in `scenes/campaigns/alderbrook/`. Edit the mission blueprints
in `tools/campaigns/build_alderbrook_campaign.gd` and run its matching scene to
regenerate scenes, shared tile sets, layout manifests, and LOS data. The image
renderer `tools/campaigns/render_alderbrook_maps.py` reads those manifests and
uses Pillow to export the PNGs. Regenerate LOS after changing terrain.

`tests/alderbrook_campaign_regression.tscn` checks content, progression, victory
thresholds, deployment identities, the quiet opener, and bridge connectivity.
Run with `-- --mission=1` through `-- --mission=5` to exercise each real match
startup, initialized victory state, and enemy tactical planning. The final match
also checks that escape remains deferred while the defense is intact.

These checks establish loading and objective correctness. A complete human
balance playthrough has not been performed.
