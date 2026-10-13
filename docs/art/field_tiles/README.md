# Field tiles

Four generated sprites, exported as transparent 64 × 64 PNGs for the project's
flat-topped hex grid:

| Tile | Alderbrook palette sources |
| --- | --- |
| `field_wheat.png` | 3, 6, 9, 10 |
| `field_green_rows.png` | 7, 8, 11, 12 |
| `field_ploughed.png` | Not used in Alderbrook |
| `field_stubble.png` | Not used in Alderbrook |

The eight existing Field atlas sources in
`resources/campaigns/alderbrook_terrain.tres` use only wheat and green crops. Their
source IDs, alternatives, flips, hindrance, and blocking data remain unchanged.
The current campaign field cells use wheat; green crops are also available
in the terrain palette. The campaign authoring tool preserves this restriction
when maps are regenerated. Original field assets used by other maps remain intact.

High-resolution generated masters are in `assets/tiles/fields/source/`.
That directory is excluded from Godot import. Run
`tools/art/export_field_tiles.py` with Pillow to normalize the transparent
bounds, export game sprites, and regenerate the preview. This only crops and
resizes the generated sprites; the alpha channel is preserved.

[Game-size preview](preview.png) · [Generation prompts](PROMPTS.md)

Art generated with the built-in imagegen tool.
