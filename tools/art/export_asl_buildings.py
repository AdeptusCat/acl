"""Export the original ASL-inspired building pack without replacing older art."""

import copy
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from export_multihex_buildings import extract, render_view, scale_for

ROOT: Path = Path(__file__).resolve().parents[2]
DOCS: Path = ROOT / "docs/art/asl_inspired_buildings"
OUTPUT: Path = ROOT / "assets/tiles/buildings/multihex/asl_inspired"


def triangle_views() -> list[dict]:
    """Rotate three adjacent axial cells, then normalize Godot's odd-q offsets."""
    cells: list[tuple[int, int]] = [(0, 0), (0, 1), (1, 0)]
    views: list[dict] = []
    for orientation in range(6):
        minimum_q: int = min(q for q, r in cells)
        offsets: list[tuple[int, int]] = [(q - minimum_q, r + (q - minimum_q) // 2) for q, r in cells]
        minimum_y: int = min(y for x, y in offsets)
        parts: list[dict] = []
        for x, y in offsets:
            y -= minimum_y
            parts.append({"cell": [x, y], "center": [64 + 96 * x, 64 + 128 * y + 64 * (x % 2)]})
        views.append({"angle": orientation * 60, "parts": parts})
        cells = [(-r, q + r) for q, r in cells]
    return views


def main() -> None:
    definitions: list[dict] = json.loads((DOCS / "prompts.json").read_text())["designs"]
    lines: dict = json.loads((ROOT / "docs/art/multihex_buildings/footprints.json").read_text())
    records: list[dict] = []
    font: ImageFont.FreeTypeFont = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 15)
    preview: Image.Image = Image.new("RGBA", (6 * 320, len(definitions) * 340), "#343e35")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    for index, definition in enumerate(definitions):
        source: Image.Image = Image.open(OUTPUT / "source" / (definition["id"] + ".png")).convert("RGBA")
        # Use one canonical roof for exact rotations. Generated alternate views
        # can mirror a wing or duplicate an angle; atlas assembly must not.
        canonical: Image.Image = extract(source, 0)
        sprites: list[Image.Image] = [canonical.rotate(-orientation * 60, resample=Image.Resampling.BICUBIC, expand=True) for orientation in range(6)]
        count: int = definition["hexes"]
        region: int = count * 128
        views: list[dict] = copy.deepcopy(lines[str(count)])
        scale: float = scale_for(sprites, count, region)
        if definition["footprint"] == "triangle":
            views = triangle_views()
            scale = min(scale, 248.0 / sprites[0].height)
        atlas: Image.Image = Image.new("RGBA", (6 * region, count * region))
        for orientation, (sprite, view) in enumerate(zip(sprites, views)):
            pattern, pieces = render_view(sprite, scale, view["parts"], region)
            for part, piece in enumerate(pieces):
                atlas.alpha_composite(piece, (orientation * region, part * region))
            center_x: int = orientation * 320 + 160
            center_y: int = index * 340 + 190
            centers: list[list[int]] = [part["center"] for part in view["parts"]]
            mean_x: int = round(sum(point[0] for point in centers) / count)
            mean_y: int = round(sum(point[1] for point in centers) / count)
            for cx, cy in centers:
                vertices: list[tuple[int, int]] = [(center_x + cx - mean_x + x, center_y + cy - mean_y + y) for x, y in [(-64, 0), (-32, -64), (32, -64), (64, 0), (32, 64), (-32, 64), (-64, 0)]]
                draw.line(vertices, fill="#70846b", width=1)
            preview.alpha_composite(pattern, (center_x - region // 2, center_y - region // 2))
            draw.text((orientation * 320 + 12, index * 340 + 12), definition["label"], fill="#efe4ce", font=font)
            draw.text((orientation * 320 + 12, index * 340 + 34), str(orientation * 60) + " degrees", fill="#bfd0bd", font=font)
        atlas.save(OUTPUT / (definition["id"] + ".png"))
        records.append({"id": definition["id"], "label": definition["label"], "material": definition["material"], "parent": definition["parent"], "pack": "asl_inspired", "hexes": count, "footprint": definition["footprint"], "orientation_method": "rigid clockwise rotation of canonical source view 0", "region_size": region, "texture": "res://assets/tiles/buildings/multihex/asl_inspired/" + definition["id"] + ".png", "scale": scale, "views": views})
        print("Exported", definition["id"], count, "hexes")
    preview.save(DOCS / "preview.png")
    preview.crop((0, 0, preview.width, 3 * 340)).save(DOCS / "wood.png")
    preview.crop((0, 3 * 340, preview.width, 6 * 340)).save(DOCS / "stone.png")
    (DOCS / "export.json").write_text(json.dumps({"tile_size": 128, "orientation_count": 6, "buildings": records}, indent=2) + "\n")


if __name__ == "__main__":
    main()
