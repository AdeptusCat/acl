# Battle for Alderbrook: fields into town

![Designer overview](05_battle_for_alderbrook.png)

The 26 × 18 map replaces the river barrier with a continuous approach from
farmland to village streets. The company can move between districts and commit
its reserve where the defense weakens. The existing force, campaign identity,
15-minute deadline and victory requirements remain in place.

The layout draws on the reference collection in
[ASL MMP boards](../../../art/asl_mmp_geo_boards/README.md):

- Boards 10 and 12: scattered buildings become a settlement beside branching roads.
- Board 6: an orchard and enclosed estate form a distinct defensive position.
- Boards 1 and 20: varied building footprints, road junctions and garden courts
  interrupt sight lines within town blocks.
- Board 4: hedged farm parcels leave gates and open approaches between them.

Only implemented terrain is used: open ground, crops, woods, orchards, roads,
water, timber/stone buildings, and hex-edge hedges/stone walls. Building roofs
retain brown for wood and grey for stone. The small southern pond has four
impassable hexes and does not separate the battlefield.

| District | Objective hex | Approach |
| --- | --- | --- |
| Orchard estate A | (14, 5) | Orchard concealment, farm lane and garden openings |
| Market hall B | (20, 10) | Main road, connecting streets and nearby house cover |
| Timber yard C | (16, 15) | Crop boundaries, barns and the southern orchard edge |

Coordinates are the editor's zero-based tile coordinates. Each objective lies
in a three-hex building. Five further two-hex buildings provide barns and town
landmarks. All footprint cells retain their cover and LOS behavior. Road
corridors stay free of buildings. Barriers sit on hex sides and leave openings
toward roads and courtyards.

The designer image shows the saved placements. It is not a fog-of-war view.
Automated checks cover connectivity, deployments, supported terrain, material
cover, complete building footprints, edge ownership, cached LOS and live match
startup. A full balance playthrough remains outstanding.

## Rebuild only this map

`tools/campaigns/alderbrook_village_layout.gd` defines roads, deployments,
objectives and briefing. `tools/campaigns/build_alderbrook_village.gd` defines
terrain parcels and building placement. Run the builder scene with
`-- --roads-only`, import its road atlas, then run it normally to save mission
five and its LOS. Use `-- --los-only` to preserve an edited map and rebuild only
its sight data. The regular campaign builder uses the same final-map layout.

Render the saved manifest with `tools/campaigns/render_alderbrook_maps.py`.
`tests/alderbrook_village_regression.tscn` checks the saved village and baked
sight data; `tests/alderbrook_campaign_regression.tscn -- --mission=5` exercises
the actual mission startup and enemy planning.
