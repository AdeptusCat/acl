# 128-pixel terrain

The map grid, terrain atlases, buildings, walls, water, objectives and fog use 128-pixel cells. Movement scales with cell spacing so changing art resolution preserves time per hex.

Woods and crops contain transparent gaps. The terrain baker places complete plant stamps in map coordinates before partitioning the finished image into hex tiles. Matching neighbors share crowns and crop rows. Exposed woodland edges taper to smaller trees with soft, irregular leaf silhouettes, ending before the hex border. Wheat and green crops use six-pixel clumps in rows nine pixels apart. Woodland terrain and cover layers share the same visible canopy pixels. Line of sight samples the actual atlas region and tile flips; transparent pixels do not block or hinder a ray.

Source art was created with the built-in imagegen tool. The original prompts are in `tiles_128_prompts.json`; the corrected crown and crop prompts are in `terrain_refinement_prompts.json`. Original images are in `assets/tiles/connected/source`, exported stamps in `assets/tiles/connected/stamps`, and the preview in `terrain_refinement_preview.png`.

Rebuild after an art or layout change:

1. Run `tools/art/export_tiles_128.py` with Python and Pillow.
2. Run Godot's `tools/campaigns/build_alderbrook_campaign.tscn -- --roads-only`, then import the assets.
3. Run `tools/art/rebuild_base_maps_128.tscn -- --art-only`, then import the assets.
4. Run `tools/campaigns/build_alderbrook_campaign.tscn -- --art-only`, then import the generated atlases. Use `--skip-los` instead when rebuilding mission layouts too.
5. Run `tools/art/rebuild_base_maps_128.tscn -- --los-only` and `tools/campaigns/build_alderbrook_campaign.tscn -- --los-only` to rebuild line of sight from the final pixels.
6. Run `tools/campaigns/render_alderbrook_maps.py` to refresh the map images.
7. Run `tools/art/render_terrain_preview.py` to refresh the terrain and selection preview.

The RoadBlock's western exit corridor spans column 0, rows 6–9, including the road and adjacent bypass.

The unit selection marker has an explicit 64-pixel rectangle matching the soldier display. UI textures are excluded from the tile exporter's grid scaling.
