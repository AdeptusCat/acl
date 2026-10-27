# Orchard Outpost

The 22 × 16 map draws on the scattered farms of ASL board
[17](../../../art/asl_mmp_geo_boards/bd17.gif) and the enclosed orchard plots of
board [54](../../../art/asl_mmp_geo_boards/bd54.gif). It uses the existing game
artwork and terrain rules.

The platoon advances diagonally from a southwestern copse toward the northern
farmhouse. Six irregular orchard plots, hedge openings and separated copses
break the approach into short engagements. The main road enters from the north,
bends beneath the farmhouse and exits through the eastern fields. A branch lane
leads back toward the player's assembly area.

- **Western approach:** orchards and the central copse screen movement toward B,
  with hedge gaps exposing squads as they change plots.
- **Barn B:** a timber barn and shed form an intermediate position. One defending
  rifle squad starts here; the gun team occupies a stone cottage farther north.
- **Farmhouse A:** stone buildings and a walled yard anchor the final defense.
- **Eastern flank:** fields offer more room to maneuver, with longer exposed
  crossings around the road bend.

Forces, loadouts, ten-minute duration, victory resources and campaign save
identities are retained. Both sides have A and B markers, including the enemy's
existing B condition.

Rebuild only this map with `tools/campaigns/build_alderbrook_orchard.tscn`:
generate roads with `-- --roads-only`, import them, rebuild with `-- --skip-los`,
import the terrain atlases, then use `-- --los-only`. The builder edits the
existing scene and writes separate Orchard tile sets. The full campaign builder
also uses this layout.

Render its designer preview from `02_orchard_outpost.json` using
`tools/campaigns/render_alderbrook_maps.py`. The regression scene is
`tests/alderbrook_orchard_regression.tscn`; it checks deployment cover, objective
markers, clear roads, directional boundaries and baked visibility.
