# Spring/summer vegetation prompts

Generated with the built-in imagegen tool, with transparent backgrounds.

## open_ground_green

Primary request: Open ground: a lush green spring/summer meadow of short fresh grass. Gentle irregular patches of emerald, fresh leaf green, and muted olive. Very subtle small tufts and low-contrast grain. Calm, mostly even green ground with no directional rows; clear space for unit counters. No trees, bushes, crop rows, rocks, flowers, paths, tracks, bare soil, or objects.

## woods_green

Primary request: Woods: dense spring/summer broadleaf woodland. Six to eight overlapping rounded deciduous tree crowns form a leafy green canopy, with fresh mid-green highlights, rich emerald leaves, and deep cool green shade between crowns. Small bright leaf clusters suggest full healthy vegetation; no autumn colors and no bare branches. Grass and low green undergrowth fill gaps and the entire hex under the crowns. Distinct large crown shapes readable at 64 pixels; forest clearly darker and more textured than open grass. No conifers, roads, trails, clearings, buildings, trunks, or visible tree sides.

## Shared specification

Use case: stylized-concept.
Asset type: game terrain sprite for a 64 by 64 pixel Godot hex strategy map.
Composition: exactly ONE flat-topped hexagon viewed vertically from directly overhead, filling the square canvas edge-to-edge with no padding. Hex vertices at normalized coordinates (0.25,0), (0.75,0), (1,0.5), (0.75,1), (0.25,1), (0,0.5). Transparent background outside the hex; opaque artwork throughout its interior, including the grass beneath foliage. A very subtle dark green boundary defines the hex without a thick outline.
Style: crisp painted pixel-art terrain, earthy but noticeably GREEN spring/summer vegetation. Simple large shapes and lightly mottled small details that survive reduction to 64 pixels. Match a top-down tactical board-game map with textured wheat and crop-row tiles. Low to moderate contrast, no glossy surfaces, no photorealism, no neon colors. Consistent soft overhead lighting.
Constraints: orthographic overhead view, no perspective or visible tile sides, no cast shadows outside the hex, no detached floating objects, no labels, no lettering, no numbers, no grid, no multiple tiles, no decorative frame. Keep the exact flat-topped hex silhouette centered and uncropped. Output an isolated production sprite with actual transparent alpha.
