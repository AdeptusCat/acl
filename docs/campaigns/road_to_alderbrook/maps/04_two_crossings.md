# Two Crossings

The 28 × 20 map takes its river layout from the narrow, winding watercourse
between farms and buildings on ASL [board 41](../../../art/asl_mmp_geo_boards/bd41.gif).
The river occupies a single chain of hexes from north to south. Each of the two
bridges occupies one hex. There are no fords, wider river sections or routes
around the ends.

The northern crossing leads into a stone bridge hamlet with walls and orchard
edges. The southern crossing lies farther east at a wooded timber yard. The
offset bridgeheads require different approaches, with a bank lane available to
shift reserves between the platoons. A second lane links the eastern bridgeheads
to the exit roads.

The river artwork follows a continuous curve through the river hex centers.
Grassy banks, water and bridge planks are assembled into map-specific atlases.
The visible bank margins are part of the impassable river hex; crossing is
restricted to the two marked bridges under the existing movement rules.

The eleven Allied and nine Axis units retain their identities and loadouts.
The twelve-minute duration and six victory resources are preserved: hold A and B
for twenty seconds and exit three units for major victory, or exit two by the
deadline for minor victory.

Rebuild this map with `tools/campaigns/build_alderbrook_crossings.tscn`: run
`-- --roads-only` to generate the road and river artwork, import it, run
`-- --skip-los`, import the terrain atlases, and finish with `-- --los-only`.
The builder edits the existing scene and saves independent terrain, buildings,
roads and water tile sets. The full campaign builder uses the same layout.

`tests/alderbrook_crossings_regression.tscn` checks the single-file river, both
individual crossings, the absence of bypasses, deployments, boundaries and baked
visibility. `-- --layout-only` omits the visibility checks while authoring.
