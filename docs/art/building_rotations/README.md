# Shared building layer and orientations

Every map instances `scenes/world/maps/layers/building_tile_map_layer.tscn`.
Its shared catalog is `resources/tilesets/buildings.tres`: three timber designs
with brown roofs and three stone designs with grey roofs. The large masonry
building is **Stone Building 03**, with stone cover 3 in all six orientations.
The layer provides transparent 128-pixel hex tiles and the shared building script.
Scenarios store their own cells while inheriting the scene's tileset.

The same layer also supplies [18 multihex designs](../multihex_buildings/README.md)
as complete two- and three-hex placement patterns, with six orientations each.

All eight building layers use this scene: Orchard Road, Default Map, all five
Road to Alderbrook maps, and the standalone Western Approach. Their original
building coordinates, design variants, categories and cover values are preserved.
Timber retains cover 2; masonry retains cover 3. Connected woodland cover sources
from every map also belong to the shared catalog and retain their existing art,
atlas coordinates and rules. Campaign palettes leave the approved roof colors intact.

Orientations are chosen with a seeded random generator per map or scenario and
saved in the scene. They remain stable when starting or rebuilding a match,
keeping baked sight data aligned with the building silhouettes.

The approved source sheet is
`assets/tiles/buildings/rotated/source/approved_roofs.png`. The built-in image
generation tool edited the user's sheet with this prompt specification: change
only the Stone 01, Stone 02 and Large building roofs to neutral slate grey;
preserve the three brown wood rows, all shapes, roof textures, ridges, chimneys,
extensions, labels, positions, orientations and transparent background.
`tools/art/export_building_rotations.py` extracts the views without their preview
labels, preserves alpha, and applies one common scale per design to fit each hex.
The six-view atlases live in `assets/tiles/buildings/rotated/`.
[Exported building views](preview.png) show the exact tiles; `export.json` records
source paths and scales. Export requires Pillow; map rendering also requires NumPy.

Rebuild the artwork and existing layer instances from the project root:

```sh
python3 tools/art/export_building_rotations.py
godot --headless --editor --path . --import
godot --headless --path . tools/art/rebuild_building_layers.tscn
godot --headless --path . tools/campaigns/build_alderbrook_campaign.tscn -- --los-only
godot --headless --path . tools/scenarios/build_western_approach.tscn -- --los-only
godot --headless --path . tools/scenarios/build_western_approach.tscn -- --manifest-only
godot --headless --path . tools/art/rebuild_base_maps_128.tscn -- --los-only
python3 tools/campaigns/render_alderbrook_maps.py
python3 tools/campaigns/render_alderbrook_maps.py docs/scenarios/western_approach/alderbrook_western_approach.json
```

Both normal authoring builders retain the reusable scene and shared catalog.
Add new scenario building layers by instancing the shared scene; existing
building-layer definitions and separate scenario tilesets are no longer needed.

`tests/alderbrook_building_art_regression.tscn` compares all eight maps against
recorded pre-replacement building layouts, verifies reuse of the layer scene,
checks all six designs and Stone Building 03's cover, verifies unclipped sprites
and repeatable orientations, and compares baked sight and cover with fresh pixel
checks at every building. Baselines record positions, design, category and cover;
update them only for intentional layout changes.

Validation: 6,451 building, layout, catalog and sight checks; 6,959 campaign
checks; 6,246 palette checks; 267 standalone gameplay checks. Base-map gameplay
smoke checks pass. All 254 project scripts parse and follow the explicit-type
and no-ternary conventions. Repeating the migration retains every non-building
tile byte and each map's independent building positions and orientations.
