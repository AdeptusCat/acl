# 128-pixel terrain

The map grid, terrain atlases, buildings, walls, water, objectives and fog use 128-pixel cells. Movement scales with cell spacing so changing art resolution preserves time per hex.

Woods and crops contain transparent gaps. The terrain baker samples their patterns in map coordinates, joins matching neighbors, and recesses exposed edges by 10–14 pixels. Woodland terrain and cover layers share the same visible canopy pixels. Line of sight samples the actual atlas region and tile flips; transparent pixels do not block or hinder a ray.

Source art was created with the built-in imagegen tool. The complete prompts are in `tiles_128_prompts.json`, original images in `assets/tiles/connected/source`, and the preview in `tiles_128_preview.png`.

Rebuild after an art or layout change:

1. Run `tools/art/export_tiles_128.py` with Python and Pillow.
2. Run Godot's `tools/campaigns/build_alderbrook_campaign.tscn -- --roads-only`, then import the assets.
3. Run `tools/art/rebuild_base_maps_128.tscn -- --art-only`, then import the assets.
4. Run `tools/campaigns/build_alderbrook_campaign.tscn -- --skip-los`, then import the generated atlases.
5. Run `tools/art/rebuild_base_maps_128.tscn -- --los-only` and `tools/campaigns/build_alderbrook_campaign.tscn -- --los-only` to rebuild line of sight from the final pixels.
6. Run `tools/campaigns/render_alderbrook_maps.py` to refresh the map images.

The RoadBlock's western exit corridor spans column 0, rows 6–9, including the road and adjacent bypass.
