# Three-hex landmarks

Six new buildings, each with six clockwise orientations and exactly three
occupied hexes. All wood roofs are brown; all stone roofs are slate grey.

| Material | Building | Footprint |
| --- | --- | --- |
| Wood | Timber sawmill factory | Three hexes in a line |
| Wood | Timber granary | Three hexes in a line |
| Wood | Timber craft hall | Three mutually adjacent hexes |
| Stone | Stone textile factory | Three hexes in a line |
| Stone | Stone village church | Three mutually adjacent hexes |
| Stone | Stone guildhall | Three mutually adjacent hexes |

The set contains two factories and one church. The shared building layer's
**Patterns** tab exposes 36 new patterns beginning with **3-hex**. Painting one
atlas member also fills the complete footprint. Every occupied cell supplies
wood cover 2 or stone cover 3. Existing maps and earlier building artwork are
retained.

Previews: [six designs](overview.png), [all orientations](preview.png),
[wood](wood.png), [stone](stone.png).
Green polygons show the actual occupied hexes and are not part of the sprites.

## Strict footprint boundary

This pack uses the union of the three actual flat-top hex polygons, rather than
the rectangular atlas canvas, as its allowed boundary. Every nonzero alpha pixel
must fit within that union at every orientation, including antialiasing fringes.
A three-pixel inset provides space for texture filtering at the outside edge.
The exporter scales and positions each complete roof without cutting off eaves,
chimneys, wings or other building details. All six views share one scale.

The three invisible gameplay fragments are partitioned by the actual hex
polygons. They retain the visible roof pixels in their own cells for LOS and
defense. The anchor draws the complete roof once, preventing internal rendering
seams. [footprint_validation.json](footprint_validation.json) records outside
pixel counts, roof area per member and the inset for all 36 views.

The Godot regression independently maps every visible pixel through
`TileMapLayer.local_to_map`, including even, odd and negative column placements.
It also checks the corners of boundary pixels, exact LOS-fragment alpha,
substantial roof area in every occupied hex and the wood/stone cover values.
It does not rely on the exporter's polygon formulas to establish containment.

## Sources and rebuilding

The built-in image generation tool created one canonical sprite per design.
[prompts.json](prompts.json) preserves the exact prompt set and footprint guides;
[generation.json](generation.json) records selected outputs. Canonical sprites
and tile atlases are saved under
`assets/tiles/buildings/multihex/three_hex_landmarks/`. The `source/` subfolder
contains the original tool output. The exporter makes six rigid rotations of
the canonical roof, preserving building shape and chimney positions.

Rebuild from the project root with Pillow and NumPy installed:

```sh
python3 tools/art/export_three_hex_landmarks.py
godot --headless --editor --path . --import
godot --headless --path . tools/art/install_multihex_buildings.tscn
godot --headless --path . tests/three_hex_landmarks_regression.tscn
godot --headless --path . tests/multihex_buildings_regression.tscn
godot --headless --path . tests/multihex_placement_regression.tscn
```

Validation: 1,917 strict-boundary checks pass, covering 2,299,584 visible pixel
placements in Godot with zero pixels in a fourth hex. All 36 views retain at
least 1,806 substantial roof pixels in every occupied cell. Catalog checks
(9,710), placement/LOS/defense checks (28,286), and parsing/convention checks
for all 269 GDScript files also pass.
