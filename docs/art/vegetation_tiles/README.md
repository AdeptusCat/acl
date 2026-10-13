# Spring/summer vegetation

Two transparent 64 × 64 hex terrain sprites:

- `assets/tiles/vegetation/open_ground_green.png`: fresh short meadow grass.
- `assets/tiles/vegetation/woods_green.png`: dense leafy broadleaf woodland.

Alderbrook uses the new open-ground image in its ground layers and the new
woodland image in both its terrain and building tile sets. The campaign
authoring tool preserves this artwork when regenerating maps. Terrain labels,
cover, hindrance, blocking flags, and pathfinding remain unchanged. The campaign
LOS caches are rebuilt because the woodland image has a new opaque silhouette.
Field artwork remains restricted to wheat and green crops.

Generated masters are preserved in `assets/tiles/vegetation/source/`, which
Godot skips importing. Run `tools/art/export_vegetation_tiles.py` with Pillow
to crop transparent padding and export the game sprites and preview. Original
terrain artwork remains available for other maps.

[Game-size preview](preview.png) · [Generation prompts](PROMPTS.md)

Art generated with the built-in imagegen tool.
