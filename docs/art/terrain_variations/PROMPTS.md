# Alderbrook terrain variation prompts

Generated with the built-in imagegen tool, using transparent backgrounds and the existing terrain masters as references.

## Shared specification

Use case: stylized-concept. Asset type: production terrain sprite for a 64x64 pixel Godot hex tactical game. Edit the reference terrain into one distinct variation described below. Preserve its overhead painted pixel-art style, soft overhead lighting, overall color family, and flat-topped hex geometry. Exactly ONE isolated tile. The six hex vertices at normalized coordinates are (0.25,0), (0.75,0), (1,0.5), (0.75,1), (0.25,1), (0,0.5). Fill the square canvas edge to edge with this hex, without padding. Transparent alpha outside the hex, opaque artwork inside; vegetation must have grass below it throughout the hex. Make broad forms readable after reducing to 64 pixels, keep edges close in color so neighboring variants blend. No text, numbers, symbols, perspective, tile sides, shadows outside the silhouette, borders thicker than a subtle dark green or olive earthen edge, multiple tiles, roads, buildings, people, equipment or decorative framing. Preserve spring/summer greens for vegetation and mature golden grain for wheat. Do not create ploughed or harvested fields.

## open_ground_green_01

Reference: assets/tiles/vegetation/source/open_ground_green.png

Variation: Short, even spring meadow grass with subtle low clover patches and fine low-contrast grain. This is tidy open ground beside roads and village buildings. Smooth mostly uniform green, very few tufts; no objects or rows.

## open_ground_green_02

Reference: assets/tiles/vegetation/source/open_ground_green.png

Variation: Lush green moist meadow with several softly spreading patches of small grass blades and clover, slightly darker but close to the reference's mid-green. This grows near riverbanks. Still entirely open grass; no trees, reeds, water, mud, crop rows, flowers or objects.

## open_ground_green_03

Reference: assets/tiles/vegetation/source/open_ground_green.png

Variation: Rough summer meadow with scattered larger grass tufts, tiny fern-like ground leaves and irregular mottled grassy patches. This is open ground at woodland margins. Keep the same overall mid-green as the other meadow variants; no shrubs, rocks, paths, or objects.

## woods_green_01

Reference: assets/tiles/vegetation/source/woods_green.png

Variation: Dense fresh green broadleaf woodland dominated by nine to eleven smaller rounded young tree crowns in an irregular connected canopy. Green undergrowth fills the gaps. A different crown arrangement from the reference; distinctly forest, not a planted orchard.

## woods_green_02

Reference: assets/tiles/vegetation/source/woods_green.png

Variation: Mature summer broadleaf woodland dominated by four to six larger rounded oak-like crowns, overlapping irregularly, with dark green shaded foliage between them. All lush green. Clearly different large-crown layout from the reference; not ordered rows.

## woods_green_03

Reference: assets/tiles/vegetation/source/woods_green.png

Variation: Mixed broadleaf woodland with seven asymmetrically arranged crowns of varied sizes, finer foliage texture and a couple lighter fresh-green crowns among deeper green canopies. Dense continuous leafy greenery underneath; no clearings, rows, bare soil, autumn leaves, or conifers.

## field_wheat_01

Reference: assets/tiles/fields/source/field_wheat.png

Variation: Fully planted mature golden wheat with six broad straight diagonal rows at 30 degrees and subtle green-brown narrow lanes. Even full heads, tidy calm pattern, a distinct row phase and spacing from the reference. Preserve wheat identity.

## field_wheat_02

Reference: assets/tiles/fields/source/field_wheat.png

Variation: Fully planted golden wheat with seven slightly narrower closely packed straight diagonal rows at 30 degrees. Strong continuous wheat bands, subtle irregular grain heads; a distinct texture from the reference. Golden growing wheat, never cut or harvested.

## field_wheat_03

Reference: assets/tiles/fields/source/field_wheat.png

Variation: Fully planted mature wheat in five broader diagonal bands at 30 degrees, with subtle wind ripple in the heads and a few greener growing stalks mixed in. A clear different broad-row pattern. Keep golden wheat dominant; no bare field, stubble, harvest, hay, or plough furrows.

## field_green_rows_01

Reference: assets/tiles/fields/source/field_green_rows.png

Variation: Growing green broadleaf crop plants in five broad evenly spaced diagonal rows at 30 degrees, rounded leafy plant clumps over narrow brown soil lanes. Tidy planted field, distinguishable chunky rows, not orchard trees.

## field_green_rows_02

Reference: assets/tiles/fields/source/field_green_rows.png

Variation: Growing green crop plants in seven closely spaced diagonal rows at 30 degrees, smaller darker emerald leaf clusters and very narrow dark earth lanes. Clearly a cultivated green crop field, a different dense texture from the reference.

## field_green_rows_03

Reference: assets/tiles/fields/source/field_green_rows.png

Variation: Growing green crop plants in six diagonal rows at 30 degrees, with slightly larger lighter leaf-green plants and gentle variations in plant spacing. Continuous recognizable rows across the hex. No bare or harvested areas, trees, plough furrows, flowers, equipment or objects.

## orchard_green_01

Reference: assets/tiles/buildings/orchard.png, assets/tiles/vegetation/source/open_ground_green.png

Variation: Green spring/summer orchard with eight small rounded leafy fruit-tree crowns evenly arranged in two straight diagonal rows of four. Wide bright grassy alleys between rows. Trees are separated and geometrically planted, unlike dense woods. Use the first reference's ordered fruit-tree idea and the second reference's grass palette and painted terrain style.

## orchard_green_02

Reference: assets/tiles/buildings/orchard.png, assets/tiles/vegetation/source/open_ground_green.png

Variation: Green spring/summer orchard with six moderately larger rounded fruit-tree crowns in two neatly aligned diagonal rows of three, evenly spaced with wide short-grass alleys. Dense healthy emerald-green leaves, tiny lighter fresh leaves, no colored fruit required. Distinct six-tree layout; clearly orderly orchard, not woodland.

## orchard_green_03

Reference: assets/tiles/buildings/orchard.png, assets/tiles/vegetation/source/open_ground_green.png

Variation: Green spring/summer orchard with nine small well-pruned rounded fruit-tree crowns in a regular three-by-three diagonal planting grid. Fresh leaf-green crown tops, deeper green underside shading, wide smooth grass lanes. Ordered spacing and open alleys must remain legible at 64 pixels. No woodland thickets or irregularly scattered trees.
