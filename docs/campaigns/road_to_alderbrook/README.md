# Road to Alderbrook

An Allied campaign with a full-force prologue followed by five missions, available under **Road to Alderbrook** in the
normal mission menu. Win the previous mission with a minor or major victory to
unlock the next. Mission results use stable identifiers, so changing a briefing
title does not erase progression. Earned unlocks survive replay defeats and draws;
completion is retained per player faction alongside the latest battle result.
Existing victory saves retain their completion when replayed. Each mission
introduces a larger force with a fresh deployment; battle casualties are recorded
by the existing save system.

| Mission | Player force | Enemy force | Default time | Major victory |
| --- | --- | --- | --- | --- |
| Prologue. Opening the Road | 3 rifles + 2 MGs + light mortar + platoon HQ + company HQ + off-map 105 mm battery | 2 rifles + MG + HQ | 10 min | Hold road A and farm B for 15 seconds each |
| 1. Quiet Approach | 1 rifle squad + platoon HQ | 1 rifle squad + HQ | 10 min | Hold farm A for 15 seconds |
| 2. Orchard Outpost | 3 rifles + MG + HQ | 2 rifles + MG + HQ | 10 min | Hold A for 30 seconds and destroy 2 units |
| 3. The Roadblock | 3 rifles + 2 MGs + HQ | 2 small platoons + company HQ | 9 min | Destroy 2 units and prevent all enemy exits |
| 4. Two Crossings | 2 reinforced platoons + company HQ | 2 platoons + company HQ | 12 min | Hold A and B for 20 seconds each and exit 3 units east |
| 5. Battle for Alderbrook | 3 platoons + company HQ + light mortar | 3 platoons + company HQ + medium mortar | 15 min | Hold A, B, C for 45 seconds each, destroy 6 units, allow at most 1 enemy exit |

Every condition in a victory level must be satisfied. Exit prevention and the
final battle are assessed at the deadline. Mission selection applies the
authored time; the existing time control can still override it.

The prologue gives the player eight units and a four-gun 105 mm battery with
48 rounds against four dispersed defenders. Secure road A and farm B for major
victory; holding A for 15 seconds at the deadline earns a minor victory. Both
unlock Quiet Approach. The company and its supporting weapons continue along
the main road while a rifle squad and platoon HQ check the flank.

The patrol starts outside opposing weapon range, with one combat squad to
command and no artillery or reinforcements. Use covered approaches and keep HQ
behind the rifle squad. A retreat to rally point B can secure a minor victory. The orchard introduces a dedicated gun team, the roadblock
introduces interception, and the river crossing introduces two-platoon
coordination and leaving garrisons behind. The final battle transitions from hedged farmland through an orchard estate
into connected village streets, with 17 player units against 14 enemy
units. Mortars and company command become part of the engagement.

## Minor victories and enemy behavior

- Quiet Approach: hold rally point B for 15 seconds at the deadline.
- Orchard Outpost: hold barn B for 30 seconds at the deadline.
- The Roadblock: hold A for 30 seconds and allow at most 2 enemy exits.
- Two Crossings: exit 2 units by the deadline.
- Battle for Alderbrook: hold market hall B for 45 seconds and destroy 3 units.

Enemy AI is enabled and player AI is off. The roadblock enemy attacks toward its
western exits; the other enemies defend. Larger enemy formations use company
command. In the final mission, the defenders hold all three districts and have
an explicit hold-to-exit fallback linked to their central command post. Escape
is deferred until the hold fails, combat strength drops below four squads, or
the remaining travel window requires withdrawal. Their minor exit threshold is
two units, which conflicts with the player's major allowance of one. Secure the
eastern escape routes before breaking the town defense.

## Playable maps and images

All six maps are editable Godot scenes. Mission four retains the river crossing;
mission five uses connected country and town approaches with a small pond. Water
has no ground or pathfinding points outside bridge cells. Each map ships compressed line of
sight data calculated by the existing LOS service.

Buildings use the [approved generated orientation set](../../art/building_rotations/README.md):
brown roofs for timber and grey roofs for stone. Buildings retain their material cover category; orientations are saved with the
map and included in its baked sight data. The final village also uses complete
two- and three-hex buildings.

Open ground, woods, wheat, green crops, and orchards each use three visual
variations. Meadows form broad patches, woods form canopy clusters, and crops
form coherent farm plots near settlements. See the
[terrain variation pack](../../art/terrain_variations/README.md) for the assets.

Roads follow continuous, individually authored curves, with unequal bend lengths
and long straight approaches to the bridges. Unique matching hex pieces keep the
road smooth across the column stagger. Roads skirt village buildings, clear
woodland from their corridors, and cross water only at the existing bridges.
See the [curved road assets](../../art/roads/README.md) and the
[final village design](maps/05_battle_for_alderbrook.md).

The images show the exact authored terrain, deployments, and objective
coordinates. They are designer overviews; the game's normal fog of war and
enemy-intelligence briefing remain in effect.

- [Campaign overview](maps/campaign_overview.png)
- [Opening the Road](maps/00_opening_the_road.png)
- [Quiet Approach](maps/01_quiet_approach.png)
- [Orchard Outpost](maps/02_orchard_outpost.png)
- [The Roadblock](maps/03_the_roadblock.png)
- [Two Crossings](maps/04_two_crossings.png)
- [Battle for Alderbrook](maps/05_battle_for_alderbrook.png)

## Authoring and verification

The prologue has a separate builder, `tools/campaigns/build_alderbrook_prologue.tscn`,
which preserves the five existing maps. Run it with `-- --roads-only`, import
the road SVG, then run it normally and import its generated terrain atlases.
Finally run with `-- --los-only` to bake LOS against the imported textures.
It writes the scene, designer manifest, independent tile sets, and baked LOS.
The main campaign builder retains the prologue at the front of the campaign.
Existing mission save IDs stay unchanged.

The campaign definition is `resources/campaigns/road_to_alderbrook.tres`; its
mission scenes are in `scenes/campaigns/alderbrook/`. Edit the mission blueprints
in `tools/campaigns/build_alderbrook_campaign.gd` and road knots in
`tools/campaigns/alderbrook_roads.gd`. When editing roads, run the builder scene
with `-- --roads-only`, import the resulting SVG atlases in Godot, then run the
builder scene normally to
regenerate scenes, shared tile sets, layout manifests, and LOS data. The image
renderer `tools/campaigns/render_alderbrook_maps.py` reads those manifests and
uses Pillow to export the PNGs, including the exact atlas regions and Godot's SVG
rasters. Regenerate LOS after changing terrain. To rebuild only the final map, use
`tools/campaigns/build_alderbrook_village.tscn`; its `-- --los-only` mode preserves
editor changes. Its layout is defined in `alderbrook_village_layout.gd`.

`tests/alderbrook_campaign_regression.tscn` checks content, progression, victory
thresholds, deployment identities, the quiet opener, and bridge connectivity.
Run with `-- --mission=1` (prologue) through `-- --mission=6` (final battle) to exercise each real match
startup, initialized victory state, and enemy tactical planning. The final match
also checks that escape remains deferred while the defense is intact.

These checks establish loading and objective correctness. A complete human
balance playthrough has not been performed.
