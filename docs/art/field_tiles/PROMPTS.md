# Field tile generation prompts

Generated with the built-in imagegen tool, using transparent backgrounds.
Each of the four calls used the common specification below, with its matching
primary request inserted.

## Common specification

Use case: stylized-concept.

Asset type: game terrain tile for a 64 by 64 pixel Godot hex strategy map.

Composition: exactly ONE flat-topped hexagonal tile viewed directly from above,
filling the entire square canvas edge-to-edge with no padding. Six vertices at
normalized coordinates (0.25,0), (0.75,0), (1,0.5), (0.75,1), (0.25,1),
(0,0.5). Crop rows run diagonally at 30 degrees. Transparent alpha outside the
hex; opaque inside it. Use a subtle narrow desaturated olive earthen boundary
around the hex, no black border.

Style: crisp, lightly textured painted pixel-art terrain. Broad simple patterns
that remain legible after downscaling to 64 pixels. Flat earthy board-game
colors, low contrast texture, no glossy rendering. Match a rustic overhead
tactical map with dark olive grass and woodland.

Constraints: no perspective, no visible sides, no shadows outside the
silhouette, no buildings, no trees, no hedges, no roads, no people, no equipment,
no water, no labels, no numbers, no decorative frame, no multiple tiles, no
grid. Keep the exact hex silhouette completely centered and uncropped. Output
an isolated production sprite with transparent background.

## Primary requests

- Wheat: A mature wheat field, ochre and straw-gold crops in six to eight broad
  parallel rows separated by muted olive-brown earth. Rich wheat but muted,
  never neon yellow.
- Green crops: A cultivated green crop field, muted sage and olive plants in
  six to eight broad parallel rows over dark umber soil. Plant clumps readable
  at small size.
- Ploughed soil: A freshly ploughed field, six to eight broad parallel furrows
  in warm brown and umber soil with pale dusty ridges. No crops; a few subtle
  earth clods.
- Harvested stubble: A harvested field, six to eight broad parallel rows of
  short ochre stubble on light brown soil. Sparse tiny straw flecks, no hay
  bales.
