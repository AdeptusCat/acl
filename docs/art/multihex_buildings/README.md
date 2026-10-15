# Multihex building catalog

The [ASL-inspired pack](../asl_inspired_buildings/README.md) adds six designs and
36 orientations. The [three-hex landmarks](../three_hex_landmarks/README.md) add
another six designs and 36 orientations with strict hex boundaries. The shared
building layer now includes 30 multihex designs and 180 complete patterns.
The original pack documented below remains available.

The shared BuildingTileMapLayer includes 18 additional building designs and
108 complete patterns. Wood 01, 02 and 03 keep brown roofs; Stone 01, 02 and 03
keep grey roofs. Each parent has two distinct two-hex designs (A and B) and one
three-hex design. Each design supplies the six orientations used by the building
catalog: 0, 60, 120, 180, 240 and 300 degrees.

In Godot, open `scenes/world/maps/layers/building_tile_map_layer.tscn`, select the
building layer and paint a building from the atlas or the TileMap **Patterns**
tab. Painting one atlas tile automatically adds all two or three occupied hexes.
The same behavior and patterns are inherited by all eight existing maps and any
new instances of that scene. Placement follows the hex-column stagger, including
odd and negative columns. Erasing any occupied hex removes the whole building.
Replacing a member or overlapping another building removes its entire old
footprint, so invisible cells cannot retain cover or block sight.

Each occupied hex provides wood cover 2 or stone cover 3. The anchor draws the
complete roof once. Other cells carry invisible cover fragments with matching
texture bounds and origins. This preserves complete roof silhouettes, prevents
filtering seams when zooming and allows eaves to overhang hex borders.
Invisible fragments contain the same pixels as the visible roof in their own
hexes. Sight sampling uses the atlas region and texture origin and clips each
member to its occupied hex. The anchor's full roof cannot block rays aimed at
another member or add obstacles beyond the declared two- or three-hex footprint.
Metadata records building ID, number of hexes, orientation and fragment number.

The building layer also exposes
`place_multihex_building(anchor, design_id, orientation)` for authoring scripts.
Orientation is an integer from 0 through 5. Design IDs and atlas regions are in
`export.json`. Single-house randomization leaves multihex patterns intact.
The tool script also repairs incomplete footprints when loading a scene.
Scripts that use native `set_cell` can call `synchronize_buildings()` to apply
the footprint immediately; editor painting updates after the stroke.
`get_building_cells(cell)` returns the complete footprint for any member.
LOS resources record the multihex layout signature. Match startup rebuilds stale
sight data in memory when that layout changes, including new multihex maps with
no saved LOS resource. Rebuild the map's baked sight
resource with its authoring tool to save the refreshed lookup and avoid this
startup work in released maps.

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
godot --headless --path . tests/multihex_placement_regression.tscn
```

The regression checks all designs and orientations, even and odd column
placement, complete footprints, fragment alignment, cover, pixel-based sight,
unchanged roof colors, preservation during single-house randomization and
idempotent installation.

The placement regression paints individual atlas fragments through native cell
editing, checks all designs, angles and column parities against Godot patterns,
and verifies erasure, replacement, overlapping brush strokes, undo/redo data,
save/load repair and live/cached gameplay LOS and defense on every occupied hex.

Validation: 5,338 catalog checks, 15,854 placement/gameplay checks, 6,451 existing
building/layout/sight checks and 267 standalone gameplay checks pass. Pixel
terrain LOS checks pass, and painting and erasure also pass in editor mode.
All 258 project scripts parse and follow the explicit-type and no-ternary rules.
Designer rendering honors texture origins and invisible cover fragments.
The footprint fix changes no existing map placements, sprites or baked resources;
incomplete placements are repaired when the shared layer loads.
