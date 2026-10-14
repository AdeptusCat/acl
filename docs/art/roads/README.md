# Curved Alderbrook roads

Five editable SVG atlases contain matching 64 × 64 road variations for the five
campaign maps. Each road is an individually authored sequence of cubic curves.
Knots have unequal spacing, slope, and bend depth; shared tangents prevent sharp
corners, and bridge approaches use horizontal tangents and straight spans.

The curves are sliced against the actual flat hex footprint. Each painted cell
uses its own atlas region rather than repeating or flipping one bend. Dirt
shoulders, wheel tracks, and grass verges follow the same continuous geometry.
Small clip overlaps suppress antialiasing seams at shared diagonal edges.

Roads pass around farms and village buildings. Woodland cover is removed where
a road clears a corridor. Rivers remain impassable except at the original bridge
cells. Crop and orchard placement reserves road cells; the campaign retains only
wheat and green crops. LOS resources are rebuilt after the terrain changes.

## Authoring

Edit `ROUTES` in `tools/campaigns/alderbrook_roads.gd`. Each `Vector3` is
`(column, continuous row, row slope per column)`. Coordinates describe continuous
world positions, independent of odd/even hex column offsets.

1. Run `tools/campaigns/build_alderbrook_campaign.tscn` with `-- --roads-only`.
   This writes the SVG atlases and Godot-rasterized PNGs in `rasters/`.
2. Import the changed assets in Godot.
3. Run the builder scene normally to save the five maps, tile sets, manifests,
   and baked LOS resources.
4. Run `tools/campaigns/render_alderbrook_maps.py` with Pillow to update map PNGs.

The game loads the SVGs from `assets/tiles/campaign/roads/`. Designer previews
read the exact same atlas regions from Godot's rasters, including bridge flips.

Verification includes road connectivity, bridge-only river crossings, building
clearance, preserved terrain rules, and continuous visible centerlines across
tile seams and bridge approaches.

[Campaign overview](../../campaigns/road_to_alderbrook/maps/campaign_overview.png)
