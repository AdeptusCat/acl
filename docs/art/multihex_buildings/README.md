# Multihex building catalog

The shared BuildingTileMapLayer includes 18 additional building designs and
108 complete patterns. Wood 01, 02 and 03 keep brown roofs; Stone 01, 02 and 03
keep grey roofs. Each parent has two distinct two-hex designs (A and B) and one
three-hex design. Each design supplies the six orientations used by the building
catalog: 0, 60, 120, 180, 240 and 300 degrees.

In Godot, open `scenes/world/maps/layers/building_tile_map_layer.tscn`, select the
building layer and use the TileMap **Patterns** tab to paint a complete building.
The same patterns are inherited by all eight existing maps and any new instances
of that scene. Select a complete pattern rather than painting individual atlas
fragments. Patterns follow the hex-column stagger automatically.

Each occupied hex provides wood cover 2 or stone cover 3. The anchor draws the
complete roof once. Other cells carry invisible cover fragments with matching
texture bounds and origins. This preserves complete roof silhouettes, prevents
filtering seams when zooming and allows eaves to overhang hex borders.
Invisible fragments contain the same pixels as the visible roof in their own
hexes. Sight and cover sampling use the atlas region and texture origin.
Metadata records building ID, number of hexes, orientation and fragment number.

The building layer also exposes
`place_multihex_building(anchor, design_id, orientation)` for authoring scripts.
Orientation is an integer from 0 through 5. Design IDs and atlas regions are in
`export.json`. Single-house randomization leaves multihex patterns intact.
After painting new buildings, rebuild that map's baked sight data.

Existing map cells and baked sight files are retained when installing this pack.
The new designs are available for authoring; this installation does not place
them into existing battles.

The raw generated sheets are in `assets/tiles/buildings/multihex/source/` and the
ready-to-use atlases are in `assets/tiles/buildings/multihex/`. The built-in image
generation tool created one sheet per design from the approved single-house
reference. `prompts.json` stores the exact generation prompts and `generation.json`
records the selected results and targeted corrections. The exporter separates
isolated sprites, orders their diagonal views, uniformly scales each design,
aligns its artwork and produces the placement fragments without repainting roofs.

Previews: [Wood 01](wood_01.png), [Wood 02](wood_02.png), [Wood 03](wood_03.png),
[Stone 01](stone_01.png), [Stone 02](stone_02.png), [Stone 03](stone_03.png).
The full catalog is in [preview.png](preview.png).

Rebuild from the project root (Pillow and NumPy required):

```sh
python3 tools/art/export_multihex_buildings.py
godot --headless --editor --path . --import
godot --headless --path . tools/art/install_multihex_buildings.tscn
godot --headless --path . tests/multihex_buildings_regression.tscn
```

The regression checks all designs and orientations, even and odd column
placement, complete footprints, fragment alignment, cover, pixel-based sight,
unchanged roof colors, preservation during single-house randomization and
idempotent installation.

Validation: 5,338 multihex checks, 6,451 existing building/layout/sight checks,
6,246 palette checks and 267 standalone gameplay checks pass. All 257 project
scripts parse and follow the explicit-type and no-ternary rules. Designer
rendering honors texture origins and invisible cover fragments. Every existing
scene file and baked sight file matches its pre-installation hash.
