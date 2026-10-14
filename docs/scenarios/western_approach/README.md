# Alderbrook: The Western Approach

A playable standalone candidate for replacing **Battle for Alderbrook**. Select
**Alderbrook Western Approach** in the normal mission menu, then
**Alderbrook: The Western Approach**. It is unlocked immediately and saves results
under `alderbrook_western_approach`.

The 28 × 18 map transitions from farm plots and broken woodland to an orchard
estate, roadside cottages and workshop yards, then dense paved town blocks.
There is no river. Three continuous roads and two diagonal connecting streets
support lateral movement; the northern and southern approaches remain usable
when the central approach is unavailable.

The player commands the same full company scale as the existing finale: three
platoons, each with a headquarters, three rifle squads and a machine-gun team,
plus company headquarters and a light mortar. Fourteen Axis units defend with
three smaller platoons, company headquarters and a medium mortar. The authored
duration is fifteen minutes.

| Objective | Location | Tactical role |
| --- | --- | --- |
| A — Orchard estate | `(13, 4)` | Orchard concealment and hedges screen approach; stone buildings anchor a flank into town. |
| B — Market square | `(20, 9)` | Deepest objective, in an open paved square. Roadside houses and diagonal streets provide alternatives to a frontal advance. |
| C — Workshop yard | `(16, 14)` | Timber sheds give successive covered positions. The connecting street supports a southern attack on the market. |

Objectives lie at different depths. A platoon can capture an outer district and
help a neighboring attack while another holds it. Fields hinder fire, woodland
blocks sight, and buildings provide the existing stone or timber cover. Paving
uses open-ground movement and elevation rules. Roads clear building and woodland
cover from their hexes. The market has no building cover.

Major victory requires A, B and C to be held simultaneously, each for thirty
uninterrupted seconds, and ends the battle immediately. Minor victory requires B
to be held for thirty uninterrupted seconds at the deadline. A unit must be in
good order to hold an objective; enemy presence contests it. Losing control resets
that objective's hold time. There are no destruction quotas, exit markers or
withdrawal fallback. The defenders earn major victory by holding all three
districts at the deadline, or minor victory by holding B.

[Map and deployments](alderbrook_western_approach.png) show the exact playable
terrain and authored starting positions, including hidden defenders. This is a
designer overview. The game retains its normal fog of war.

## Authoring

The standalone scene is
`scenes/scenarios/standalone/alderbrook_western_approach.tscn`.
Edit terrain, roads, deployments and briefing in
`tools/scenarios/build_western_approach.gd`. The builder reuses campaign authoring
helpers and source tiles, and writes separate terrain resources, connected
atlases, a layout manifest and baked line of sight.

Regenerate from the project root:

```sh
godot --headless --path . tools/scenarios/build_western_approach.tscn -- --roads-only
godot --headless --editor --path . --import
godot --headless --path . tools/scenarios/build_western_approach.tscn
godot --headless --editor --path . --import
python3 tools/campaigns/render_alderbrook_maps.py docs/scenarios/western_approach/alderbrook_western_approach.json
```

The image renderer requires Pillow and NumPy. `--roads-only` also rasterizes the
vector town paving. `--los-only` rebakes sight from the saved scene. `--skip-los`
is available for terrain iteration; rebake before playing changed terrain.

## Verification

`tests/western_approach_regression.tscn` exercises normal menu availability, unique
save and command identities, faction loadouts, deployment legality, country-to-town
building density, connected roads, both flanks with the center disabled, complete
baked LOS, real match startup and defending company AI. It also checks simultaneous
occupation, hold timing, loss of control, contested objectives and deadline-only
minor victory. Run with `--fixed-fps 60` and isolated user data.

Automated validation establishes scenario loading, movement and victory behavior.
Human balance and combat pacing remain unverified.

Validated with Godot 4.7.2: 266 standalone scenario checks, 6,125 terrain palette
checks and 6,959 existing campaign checks passed. All 251 project scripts parsed
and passed the explicit-type and no-ternary convention check.
