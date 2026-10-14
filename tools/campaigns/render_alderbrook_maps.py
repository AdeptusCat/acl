"""Export designer map images from the authored Godot tile layout manifests."""

from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT: Path = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
from terrain_palette_preview import apply_palette, family_for_cell

OUTPUT: Path = ROOT / "docs/campaigns/road_to_alderbrook/maps"
FONT: str = "/usr/share/fonts/TTF/DejaVuSans.ttf"
BOLD: str = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
if not Path(FONT).exists():
    FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
PAPER: str = "#e9e4d7"
INK: str = "#25352f"
BLUE: str = "#376889"
RED: str = "#a45446"
GOLD: str = "#d8b760"

PHASES: list[str] = ["Patrol: 2 rifle squads + HQ", "Platoon: 3 rifles + MG + HQ", "Platoon: 3 rifles + 2 MGs + HQ", "Two reinforced platoons + company HQ", "Company: 3 platoons + mortar + company HQ"]
GOALS: list[str] = ["Occupy the farm; secure the rally point.", "Occupy the outpost and destroy two units.", "Destroy two units and prevent enemy exits.", "Secure both crossings and exit three units.", "Occupy three districts, destroy six units, stop escape."]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path: str = FONT
    if bold:
        path = BOLD
    return ImageFont.truetype(path, size)


def texture(path: str, cache: dict[str, Image.Image]) -> Image.Image:
    if path in cache:
        return cache[path]
    local: Path = ROOT / path.removeprefix("res://")
    if local.suffix == ".svg":
        raster: Path = ROOT / "docs/art/roads/rasters" / (local.stem + ".png")
        tile: Image.Image = Image.open(raster).convert("RGBA")
    else:
        tile = Image.open(local).convert("RGBA")
    cache[path] = tile
    return tile


def render_map(path: Path) -> tuple[dict, Image.Image]:
    data: dict = json.loads(path.read_text())
    positions: dict[tuple[int, int], tuple[int, int]] = {}
    cache: dict[str, Image.Image] = {}
    for layer in data["layers"]:
        for cell in layer["cells"]:
            positions[tuple(cell["hex"])] = tuple(round(value) for value in cell["position"])
    max_x: int = max(point[0] for point in positions.values()) + 64
    max_y: int = max(point[1] for point in positions.values()) + 64
    offset: tuple[int, int] = (60, 152)
    canvas: Image.Image = Image.new("RGBA", (max(1000, max_x + 120), max_y + 284), PAPER)
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, canvas.width, 124), fill=INK)
    draw.text((38, 20), "ROAD TO ALDERBROOK", font=font(16, True), fill="#c9c9b2")
    draw.text((38, 47), data["title"], font=font(30, True), fill=PAPER)
    index: int = int(data["id"][:2]) - 1
    duration: int = int(data["seconds"] / 60)
    subtitle: str = f"{PHASES[index]}  |  {duration} minutes  |  {data['size'][0]} x {data['size'][1]} hexes"
    draw.text((38, 91), subtitle, font=font(16), fill="#c9c9b2")
    for layer in data["layers"]:
        for cell in layer["cells"]:
            tile: Image.Image = texture(cell["texture"], cache)
            if "texture_region" in cell:
                x, y, width, height = cell["texture_region"]
                tile = tile.crop((x, y, x + width, y + height))
            if cell.get("flip_h", False):
                tile = ImageOps.mirror(tile)
            if cell.get("flip_v", False):
                tile = ImageOps.flip(tile)
            tile = apply_palette(tile, family_for_cell(layer["name"], cell))
            point: list = cell["position"]
            canvas.alpha_composite(tile, (round(point[0] - tile.width / 2 + offset[0]), round(point[1] - tile.height / 2 + offset[1])))
    draw = ImageDraw.Draw(canvas)
    labels: dict[str, str] = {"rifle": "R", "mg": "MG", "hq": "HQ", "company_hq": "CHQ", "light_mortar": "M", "medium_mortar": "M"}
    for key, color in [("player", BLUE), ("enemy", RED)]:
        for platoon, kind, x, y in data[key]:
            point: tuple[int, int] = positions[(x, y)]
            px: int = point[0] + offset[0]
            py: int = point[1] + offset[1]
            draw.rounded_rectangle((px - 19, py - 11, px + 19, py + 11), radius=5, fill=color, outline=PAPER, width=2)
            label: str = labels[kind]
            draw.text((px, py - 1), label, font=font(11, True), fill="white", anchor="mm")
            if platoon > 0:
                draw.text((px, py + 16), f"P{platoon}", font=font(10, True), fill=INK, anchor="mm", stroke_width=2, stroke_fill=PAPER)
    marker_labels: list[str] = ["EXIT", "A", "B", "C", "START"]
    seen: set[tuple[int, int]] = set()
    for key in ["allied_markers", "axis_markers"]:
        for marker, x, y in data[key]:
            if marker == 4 or (x, y) in seen:
                continue
            seen.add((x, y))
            point = positions[(x, y)]
            px = point[0] + offset[0] + 16
            py = point[1] + offset[1] - 23
            label = marker_labels[marker]
            width: int = 26
            if marker == 0:
                width = 46
            draw.rounded_rectangle((px - width // 2, py - 10, px + width // 2, py + 10), radius=4, fill=GOLD, outline=INK)
            draw.text((px, py), label, font=font(10, True), fill=INK, anchor="mm")
    footer_y: int = canvas.height - 100
    draw.line((38, footer_y - 15, canvas.width - 38, footer_y - 15), fill="#afa99b", width=1)
    draw.text((38, footer_y), GOALS[index], font=font(17, True), fill=INK)
    draw.text((38, footer_y + 33), "Blue: Allied deployment    Red: Axis deployment    Gold: objectives / exits", font=font(14), fill=INK)
    draw.text((38, footer_y + 60), "Designer overview. Terrain and deployment coordinates match the playable map.", font=font(12), fill="#5f665a")
    image: Image.Image = canvas.convert("RGB")
    image.save(path.with_suffix(".png"))
    return data, image


def render_overview(maps: list[tuple[dict, Image.Image]]) -> None:
    canvas: Image.Image = Image.new("RGB", (1800, 2330), PAPER)
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, 1800, 168), fill=INK)
    draw.text((46, 30), "ROAD TO ALDERBROOK", font=font(44, True), fill=PAPER)
    draw.text((48, 95), "Five linked Allied missions. Start with a patrol; finish with company command.", font=font(22), fill="#c9c9b2")
    for index, (data, image) in enumerate(maps):
        x: int = 38 + (index % 2) * 880
        y: int = 200 + (index // 2) * 630
        width: int = 844
        if index == 4:
            x = 38
            width = 1724
        height: int = 595
        if index == 4:
            height = 785
        draw.rounded_rectangle((x, y, x + width, y + height), radius=12, fill="#f7f4eb", outline="#c4bfad", width=2)
        draw.text((x + 24, y + 18), data["title"], font=font(25, True), fill=INK)
        draw.text((x + 24, y + 59), PHASES[index], font=font(16), fill="#59675c")
        crop: Image.Image = image.crop((24, 126, image.width - 24, image.height - 110))
        box: tuple[int, int] = (width - 48, 404)
        if index == 4:
            box = (950, 580)
        fitted: Image.Image = ImageOps.contain(crop, box, Image.Resampling.LANCZOS)
        px: int = x + (width - fitted.width) // 2
        py: int = y + 91 + (404 - fitted.height) // 2
        if index == 4:
            px = x + 24 + (950 - fitted.width) // 2
            py = y + 92
        canvas.paste(fitted, (px, py))
        caption_y: int = y + 519
        if index == 4:
            caption_y = y + 705
        draw.text((x + 24, caption_y), GOALS[index], font=font(16, True), fill=INK)
        draw.text((x + 24, caption_y + 34), f"{int(data['seconds'] / 60)} minutes  |  {data['size'][0]} x {data['size'][1]} hexes", font=font(15), fill="#59675c")
        if index == 4:
            draw.text((x + 1000, y + 146), "The final battle", font=font(28, True), fill=INK)
            for row, line in enumerate(["Three rifle platoons", "Machine-gun and mortar support", "Three bridge approaches", "Three village objectives", "Enemy withdrawal and exit denial"]):
                draw.text((x + 1000, y + 211 + row * 43), line, font=font(19), fill="#59675c")
    draw.text((46, 2290), "Designer overview: blue Allied deployment, red Axis deployment, gold objectives and exits.", font=font(16), fill=INK)
    canvas.save(OUTPUT / "campaign_overview.png")


if __name__ == "__main__":
    rendered: list[tuple[dict, Image.Image]] = []
    for source in sorted(OUTPUT.glob("0*.json")):
        rendered.append(render_map(source))
    render_overview(rendered)
    print("Rendered five playable map overviews and the campaign overview.")
