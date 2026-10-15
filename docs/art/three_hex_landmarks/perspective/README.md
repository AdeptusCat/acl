# Fixed-camera building orientations

Six views of each supplied building: 0, 60, 120, 180, 240 and 300 degrees.
Wood roofs remain brown; stone roofs remain slate grey. The textile factory
retains industrial saw-tooth roofing. Each building occupies exactly three hexes.

This is a separate preview pack. The shared building palette and map placements
continue to use the existing artwork.

## Deliverables

- [Wood buildings](wood.png) and [stone buildings](stone.png), with hex boundaries
  and small yellow markers at the exact occupied centers.
- [All 36 views](preview.png).
- Six Godot atlases and 36 individual transparent PNGs under
  `assets/tiles/buildings/multihex/three_hex_landmarks/perspective/`.
- [export.json](export.json), with the exact footprint, per-member image origins,
  material and angle of every view.

The atlas anchor draws the complete building. Two invisible atlas members retain
the building pixels in their own hexes for LOS and wood/stone defense. Standalone
sprites are in the atlas folder's `sprites/<building id>/<angle>.png` directories.
Yellow center markers and hex lines appear only in the previews.

## Rules and verification

Every nonzero alpha pixel must lie inside the union of the three occupied hexes,
with a one-pixel inset. The exporter checks the complete silhouette, including
antialiasing fringes, eaves and chimneys. It scales and translates whole views;
it never clips artwork to the footprint or rotates a delivered bitmap.

All four texels surrounding each exact hex center must have alpha at least
128/255. A view that cannot meet both containment and center coverage fails export
and needs new artwork. [footprint_validation.json](footprint_validation.json)
records both checks for all 36 views.

The camera remains fixed while the building turns in the world. Roof shading,
visible walls and vertical details are repainted for alternate orientations.
Chimneys and the church tower rise toward screen top in each view. Perspective
is checked visually; numerical footprint checks do not establish perspective.

The Godot regression independently checks every nontransparent pixel against
`TileMapLayer.local_to_map`, including boundary-pixel corners and placement on
even, odd and negative columns. It also checks all center texels, exact matching
LOS fragments, complete three-cell placement and material defense values.
It installs the preview pack only into an in-memory copy of the shared palette.

## Generation and rebuilding

The built-in image generation tool produced the alternate artwork.
[prompts.json](prompts.json), [correction_prompts.json](correction_prompts.json)
and [generation.json](generation.json) record prompts, inputs and selected outputs.
The original supplied 0-degree views are retained. Intermediate footprint and
projection guides constrain the plan; their incorrect rotated vertical relief
is explicitly corrected by the image model. These guides are not delivered sprites.
The exporter consumes selected rendered images, not the guides.

Rebuild with Pillow and NumPy available:

```sh
python3 tools/art/export_landmark_perspectives.py
godot --headless --editor --path . --recovery-mode --import --quit
godot --headless --path . tests/landmark_perspectives_regression.tscn
```

Verified in Godot 4.7.2: 7,099 checks pass across 2,858,036 visible-pixel
placements, with zero failures. All 270 project scripts pass parsing and
convention checks. [verification.json](verification.json) records the results.
