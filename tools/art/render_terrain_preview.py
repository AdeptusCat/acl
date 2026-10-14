"""Render current crops, orchards, woods and buildings at their display sizes."""

from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
from terrain_palette_preview import apply_palette

ROOT: Path = Path(__file__).resolve().parents[2]
MAPS: Path = ROOT / "docs/campaigns/road_to_alderbrook/maps"
ART: Path = ROOT / "docs/art"


def main() -> None:
    data: dict = json.loads((MAPS / "03_the_roadblock.json").read_text())
    map_image: Image.Image = Image.open(MAPS / "03_the_roadblock.png").convert("RGBA")
    preview: Image.Image = Image.new("RGBA", (1000, 946), "#e9e4d7")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    font_path: str = "/usr/share/fonts/TTF/DejaVuSans.ttf"
    if not Path(font_path).exists():
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    title: ImageFont.FreeTypeFont = ImageFont.truetype(font_path, 26)
    label: ImageFont.FreeTypeFont = ImageFont.truetype(font_path, 18)
    draw.text((24, 18), "Road to Alderbrook — approved terrain palette", font=title, fill="#25352f")
    samples: list[tuple[str, tuple[int, int], tuple[int, int]]] = [
        ("Connected woods with intact, irregular fringes", (544, 320), (24, 98)),
        ("Continuous hand-sown wheat", (544, 640), (524, 98)),
        ("Dense green crops without machine tracks", (1216, 640), (24, 384)),
        ("Fruit orchards with mature, varied crowns", (1024, 1472), (524, 384)),
        ("Farm building beside trees for scale", (832, 1280), (24, 670)),
    ]
    for caption, center, position in samples:
        cx, cy = center[0] + 60, center[1] + 152
        crop: Image.Image = map_image.crop((cx - 216, cy - 112, cx + 216, cy + 112))
        preview.alpha_composite(crop, position)
        draw.text((position[0], position[1] - 30), caption, font=label, fill="#25352f")
    draw.text((524, 640), "Unit display for scale", font=label, fill="#25352f")
    panel: Image.Image = Image.new("RGBA", (432, 224), "#70766b")
    ground: dict = data["layers"][0]["cells"][0]
    ground_tile: Image.Image = Image.open(ROOT / ground["texture"].removeprefix("res://")).convert("RGBA")
    if "texture_region" in ground:
        x, y, width, height = ground["texture_region"]
        ground_tile = ground_tile.crop((x, y, x + width, y + height))
    ground_tile = apply_palette(ground_tile, "open_ground")
    for x in range(-32, 432, 96):
        for y in range(-64, 224, 128):
            offset_y: int = y
            if (x + 32) // 96 % 2 == 1:
                offset_y += 64
            panel.alpha_composite(ground_tile, (x, offset_y))
    origin: tuple[int, int] = (184, 80)
    for asset, extent, offset in [
        ("assets/units/unit_tb_border.png", 64, (0, 0)),
        ("assets/status/idle_us.png", 40, (14, 12)),
    ]:
        sprite: Image.Image = Image.open(ROOT / asset).convert("RGBA").resize((extent, extent), Image.Resampling.LANCZOS)
        panel.alpha_composite(sprite, (origin[0] + offset[0], origin[1] + offset[1]))
    ui: ImageDraw.ImageDraw = ImageDraw.Draw(panel)
    ui.rectangle((origin[0] + 4, origin[1] + 52, origin[0] + 61, origin[1] + 64), fill="black")
    ui.rectangle((origin[0] + 5, origin[1] + 53, origin[0] + 59, origin[1] + 62), fill="#008e00")
    marker: Image.Image = Image.open(ROOT / "assets/ui/unit_selected.png").convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
    panel.alpha_composite(marker, origin)
    preview.alpha_composite(panel, (524, 670))
    draw.text((24, 913), "128-pixel hexes. All samples shown at their authored display sizes.", font=label, fill="#25352f")
    preview.convert("RGB").save(ART / "terrain_refinement_preview.png")
    preview.convert("RGB").save(ART / "tiles_128_preview.png")
    print("Rendered current terrain and selection preview.")


if __name__ == "__main__":
    main()
