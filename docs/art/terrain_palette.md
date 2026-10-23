# Road to Alderbrook terrain colors

The campaign uses the approved [base-tile palette](palette-proposals/natural-richness.png), anchored on grass green `#427012`. Runtime colors and source brightness stops are stored in [terrain_palettes.json](../../assets/palettes/terrain_palettes.json).

All five missions use these colors for open ground, woods, orchard foliage and fruit, continuous wheat and green crops, roads, river water, bridge timber, and stone and timber buildings. Existing outlines and fog use the neutral palette. Woods use the approved muted olive `#555F2D` foliage and dark brown `#2C2A16` shadows, with nearby shading stops for the existing canopy detail. Their single-material ramp keeps warm source pixels within the same olive-and-brown scheme. Orchards retain their lighter foliage with red apples, amber pears and pale blossoms.

The palette changes RGB during rendering. Source textures, their alpha, tile spacing, cell placement, connected terrain shapes, cover metadata and baked LOS remain unchanged. Campaign layers clone their used tile sources before assigning materials, so shared base maps retain their original colors. The palette JSON is preloaded as a Godot resource and included through its normal export dependency.

The shader works with HDR and SDR in Forward+ and Compatibility. Linear color conversion requires both an HDR 2D request and a RenderingDevice; Compatibility, including Web exports, keeps sRGB output even when the project requests HDR 2D. Fog uses the same renderer check. Material-specific masks retain the distinction between foliage, fruit, blossoms, clay or slate roofs, and water beneath bridge planks. The map overview renderer uses the same ramps and masks.

Regenerate the documentation images with `tools/campaigns/render_alderbrook_maps.py`, then `tools/art/render_terrain_preview.py`.

Validation: `tests/terrain_palette_regression.tscn` checks coverage, approved swatches, unchanged shared sources and geometry. Run it with `-- --render` for GPU color and alpha checks. Terrain art, pixel LOS, campaign content and mission lifecycle regressions also cover this change.

Use `-- --render --render-only` to check GPU colors and alpha independently of map content. Run with both `--rendering-method forward_plus` and `--rendering-method gl_compatibility`; HDR readbacks are decoded only when the renderer actually uses linear output.
