# Road layers

All eight maps use `scenes/world/maps/layers/road_tile_map_layer.tscn` and
`resources/tilesets/roads.tres`. Select `TileMapLayers/RoadTileMapLayer` in the
Godot scene tree to paint roads. The terrain layer contains vegetation and
fields; its paint catalog no longer includes road sources.

The drawing order is ground, water where present, terrain, roads, walls, then
buildings. A road can share a hex with an orchard or part of a building without
replacing that terrain's LOS or defensive properties. Roads themselves remain
open terrain with no blocking or hindrance. Inspection recognizes the road
layer, with vegetation and buildings taking precedence when they share its hex.

The shared catalog includes the existing reusable straight, bend and junction
tiles, plus the curved atlases for the campaign and Western Approach. Curved
atlas regions describe specific map positions; they are not an autotile set.
The campaign builders paint these regions onto the road layer. All road verges
are drawn before the road surfaces so branches cannot paint over junctions.

Battle for Alderbrook retains its buildings, orchards and other terrain. Its
complete 132-cell road atlas is restored, including the two pieces at `(20, 5)`
and `(23, 10)` previously replaced by orchard tiles.

## Curved road authoring

The atlases slice authored cubic curves against the actual flat hex footprint.
Each painted cell uses its own region rather than a repeated or flipped bend.
Shared tangents keep bends smooth and bridge approaches straight. Small clip
overlaps suppress antialiasing seams at shared diagonal edges. SVG geometry uses
64 units per tile; imported textures and game cells use 128 pixels.

Edit mission 1–4 routes in `tools/campaigns/alderbrook_roads.gd`, village routes
in `tools/campaigns/alderbrook_village_layout.gd`, and standalone routes in
`tools/scenarios/build_western_approach.gd`. Each knot is
`Vector3(column, continuous row, row slope per column)`, independent of the
odd/even column offsets.

Run the appropriate builder with `-- --roads-only` to regenerate SVGs and the
matching Godot rasters without rebuilding the map. Import the artwork in Godot.
The full builder regenerates map layouts, TileSets, manifests and baked LOS;
map-specific atlas regions must agree with the saved road cells. Field and
orchard generation reserves road corridors, and rivers remain impassable away
from bridges.

The game loads SVGs from `assets/tiles/campaign/roads/`. Designer previews read
the same atlas regions from `rasters/`, including bridge flips. Render a selected
manifest with `tools/campaigns/render_alderbrook_maps.py` to update its map PNG.

## Validation

```sh
godot --headless --path . tests/road_layers_regression.tscn
python3 tests/alderbrook_road_art_regression.py
godot --headless --path . tests/los_map_lifecycle_regression.tscn
```

[Campaign overview](../../campaigns/road_to_alderbrook/maps/campaign_overview.png)
