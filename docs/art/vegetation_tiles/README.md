# Spring/summer vegetation

Two transparent 64 × 64 hex terrain sprites:

- `assets/tiles/vegetation/open_ground_green.png`: fresh short meadow grass.
- `assets/tiles/vegetation/woods_green.png`: dense leafy broadleaf woodland.

Alderbrook now uses three variations derived from each original sprite; see
[the terrain variation pack](../terrain_variations/README.md). The campaign
authoring tool groups them in meadow patches and woodland clusters, matching
woodland canopies between terrain and building layers. Terrain rules remain
unchanged, and LOS caches are rebuilt with the new artwork and farmland layout.
Field artwork remains restricted to wheat and green crops.

Generated masters are preserved in `assets/tiles/vegetation/source/`, which
Godot skips importing. Run `tools/art/export_vegetation_tiles.py` with Pillow
to crop transparent padding and export the game sprites and preview. Original
terrain artwork remains available for other maps.

[Game-size preview](preview.png) · [Generation prompts](PROMPTS.md)

Art generated with the built-in imagegen tool.
