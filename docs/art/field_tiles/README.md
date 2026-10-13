# Field tiles

Four generated sprites, exported as transparent 64 × 64 PNGs for the project's
flat-topped hex grid:

| Tile | Alderbrook palette sources |
| --- | --- |
| `field_wheat.png` | 3, 6, 9, 10 |
| `field_green_rows.png` | 7, 8, 11, 12 |
| `field_ploughed.png` | Not used in Alderbrook |
| `field_stubble.png` | Not used in Alderbrook |

Alderbrook now uses three variations of both wheat and green crops, arranged in
coherent plots; see [the terrain variation pack](../terrain_variations/README.md).
The original sprites listed above remain available. The campaign authoring tool
preserves the wheat/green-crop restriction when maps are regenerated.

High-resolution generated masters are in `assets/tiles/fields/source/`.
That directory is excluded from Godot import. Run
`tools/art/export_field_tiles.py` with Pillow to normalize the transparent
bounds, export game sprites, and regenerate the preview. This only crops and
resizes the generated sprites; the alpha channel is preserved.

[Game-size preview](preview.png) · [Generation prompts](PROMPTS.md)

Art generated with the built-in imagegen tool.
