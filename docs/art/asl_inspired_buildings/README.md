# ASL-inspired multihex buildings

Six original building designs inspired by the saved ASL boards: long agricultural
buildings, stepped town terraces, attached wings and open courtyard plans.
Boards 1, 6, 10, 12, 20 and 23 informed the selection. The art uses the game's
painted roof style rather than reproducing the board artwork.

| Material | Design | Footprint |
| --- | --- | --- |
| Wood | Long barn | 2 adjacent hexes |
| Wood | Stepped workshop | 2 adjacent hexes |
| Wood | L-shaped farmstead | 3 adjacent hexes in a compact cluster |
| Stone | Winged village inn | 2 adjacent hexes |
| Stone | Stepped town terrace | 2 adjacent hexes |
| Stone | Courtyard manor | 3 adjacent hexes in a compact cluster |

Every design has six orientations: 0, 60, 120, 180, 240 and 300 degrees.
Wood roofs are brown; stone roofs are slate grey. Transparent notches in the
winged buildings remain open for pixel-based sight sampling.

The shared `BuildingTileMapLayer` exposes all 36 new patterns alongside the
original 108. Select the layer's **Patterns** tab and look for names beginning
with **ASL Wood** or **ASL Stone**. Painting an individual atlas member also
creates its complete two- or three-hex footprint. All members provide wood
cover 2 or stone cover 3. Existing map placements are retained.

Previews: [all orientations](preview.png), [wood](wood.png), [stone](stone.png).
The outlines in these previews show the occupied hexes; they are not part of
the building sprites.

Generated source sheets and exported tile atlases are saved in
`assets/tiles/buildings/multihex/asl_inspired/`. The `source/` subfolder retains the
original tool output. [prompts.json](prompts.json) records the complete prompt
set; [generation.json](generation.json) records selected tool results. The
provider is the built-in image generation tool. [export.json](export.json)
records the atlas regions, material, footprint and texture origins.

The exporter extracts each design's canonical generated roof, produces exact
clockwise rotations in 60-degree increments, uniformly scales the design and
partitions roof pixels into the occupied cells. Using a single canonical roof
preserves wing positions, notches and chimneys at every angle and avoids
mirrored or duplicated generated alternate views. Compact three-hex patterns
rotate their axial coordinates before conversion to Godot's staggered columns.
The common drawing origin is rounded once, preserving exact alignment when the
footprint centroid lies between pixels.

Rebuild from the project root with Pillow and NumPy installed:

```sh
python3 tools/art/export_asl_buildings.py
godot --headless --editor --path . --import
godot --headless --path . tools/art/install_multihex_buildings.tscn
godot --headless --path . tests/multihex_buildings_regression.tscn
godot --headless --path . tests/multihex_placement_regression.tscn
```

Validation: 7,260 catalog checks and 21,014 placement/gameplay checks pass,
including every design and angle, even/odd/negative columns, fragment alignment,
complete-footprint painting and erasure, material cover and pixel-based LOS.
All 268 project GDScript files parse and satisfy the explicit-type/no-ternary
conventions. The existing resource IDs and all original catalog entries are
preserved; this pack appends six sources and 36 patterns.

Broader checks retain existing failures: the terrain-palette suite reports 24,
the older Alderbrook building-art suite reports 113 and the village suite reports
9 plus a missing lookup entry. Repeating all three suites with the original
committed tileset produces the same failures. Those tests still assume
single-hex artwork or older map/LOS fixtures.
