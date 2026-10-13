# Field tiles

Four generated sprites, exported as transparent 64 × 64 PNGs for the project's
flat-topped hex grid:

| Tile | Primary campaign palette source |
| --- | --- |
| `field_wheat.png` | 6 |
| `field_green_rows.png` | 7 |
| `field_ploughed.png` | 8 |
| `field_stubble.png` | 9 |

The eight existing Field atlas sources in
`resources/campaigns/alderbrook_terrain.tres` now use these four images. Their
source IDs, alternatives, flips, hindrance, and blocking data remain unchanged.
The current campaign field cells use wheat; the other variants are available
in the terrain palette. The campaign authoring tool preserves the new art when
maps are regenerated. Original field assets used by other maps remain intact.

High-resolution generated masters are in `assets/tiles/fields/source/`.
That directory is excluded from Godot import. Run
`tools/art/export_field_tiles.py` with Pillow to normalize the transparent
bounds, export game sprites, and regenerate the preview. This only crops and
resizes the generated sprites; the alpha channel is preserved.

[Game-size preview](preview.png) · [Generation prompts](PROMPTS.md)

Art generated with the built-in imagegen tool.
