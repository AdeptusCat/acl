# Alderbrook terrain variations

Fifteen new transparent 64 × 64 PNG sprites, generated with the built-in
imagegen tool from the existing terrain masters. Each family has three distinct
variations, numbered `01` through `03`:

| Family | Saved game sprites |
| --- | --- |
| Open ground | [01](../../../assets/tiles/vegetation/open_ground_green_01.png), [02](../../../assets/tiles/vegetation/open_ground_green_02.png), [03](../../../assets/tiles/vegetation/open_ground_green_03.png) |
| Woods | [01](../../../assets/tiles/vegetation/woods_green_01.png), [02](../../../assets/tiles/vegetation/woods_green_02.png), [03](../../../assets/tiles/vegetation/woods_green_03.png) |
| Wheat | [01](../../../assets/tiles/fields/field_wheat_01.png), [02](../../../assets/tiles/fields/field_wheat_02.png), [03](../../../assets/tiles/fields/field_wheat_03.png) |
| Green crops | [01](../../../assets/tiles/fields/field_green_rows_01.png), [02](../../../assets/tiles/fields/field_green_rows_02.png), [03](../../../assets/tiles/fields/field_green_rows_03.png) |
| Orchard | [01](../../../assets/tiles/orchard/orchard_green_01.png), [02](../../../assets/tiles/orchard/orchard_green_02.png), [03](../../../assets/tiles/orchard/orchard_green_03.png) |

The high-resolution generated masters are in each asset directory's `source/`
folder, excluded from Godot import. Run `tools/art/export_terrain_variations.py`
with Pillow to crop transparent padding, resize the game sprites, and regenerate
the contact sheet.

## Placement

The campaign authoring tool installs every variant and paints all five maps:

- Short grass along roads and bridge approaches, lush grass near riverbanks,
  rougher grass along woodland margins, and smooth noise-based meadow patches.
- Woodland canopies grouped in broad spatial clusters. Terrain and building
  layers use the matching canopy image at each woodland hex.
- Wheat and green crops alternate between explicitly authored farmland plots.
  Each plot keeps one crop type and row texture throughout.
- Orchard blocks sit near farms and village buildings. The outpost retains its
  larger orchard; row patterns vary in groups within planted areas.

Planting skips buildings, woods, roads, and impassable river cells. Terrain
classes retain their elevation, cover, hindrance, blocking, and collision
settings. Farmland now forms coherent plots, so campaign LOS caches are rebuilt
with the new layout. Deployments, objectives, and mission duration are unchanged.
Alderbrook uses wheat and green crops for fields.

[Tile preview](preview.png) · [Generation prompts](PROMPTS.md) ·
[Campaign maps](../../campaigns/road_to_alderbrook/maps/campaign_overview.png)
