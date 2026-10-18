"""Extract the approved generated building views into transparent 128-pixel atlases."""

from pathlib import Path
from collections import deque
import json
from PIL import Image, ImageDraw, ImageFont

ROOT: Path = Path(__file__).resolve().parents[2]
OUTPUT: Path = ROOT / "assets/tiles/buildings/rotated"
DOCS: Path = ROOT / "docs/art/building_rotations"
SOURCE: Path = OUTPUT / "source/approved_roofs.png"
NAMES: list[str] = ["building_wood_01", "building_wood_02", "building_wood_03", "building_stone_01", "building_stone_02", "building_stone_03"]
COLUMNS: list[int] = [100, 280, 473, 671, 855, 1051, 1254]
ROWS: list[int] = [83, 269, 440, 625, 800, 993, 1222]
SIZE: int = 128


def extract(sheet: Image.Image, row: int, column: int) -> Image.Image:
    columns: list[int] = COLUMNS
    if row == 5:
        columns = [100, 289, 476, 671, 855, 1051, 1254]
    sprite: Image.Image = sheet.crop((columns[column], ROWS[row], columns[column + 1], ROWS[row + 1]))
    alpha: Image.Image = sprite.getchannel("A")
    threshold: int = 8
    if row == 5:
        # Separate the large buildings where their translucent shadows touch.
        threshold = 64
    mask: bytearray = bytearray(alpha.point(lambda value: 255 * (value > threshold)).tobytes())
    largest: list[int] = []
    for start in range(len(mask)):
        if not mask[start]:
            continue
        component: list[int] = []
        queue: deque[int] = deque([start])
        mask[start] = 0
        while queue:
            point: int = queue.popleft()
            component.append(point)
            x, y = point % sprite.width, point // sprite.width
            for ny in range(max(0, y - 1), min(sprite.height, y + 2)):
                for nx in range(max(0, x - 1), min(sprite.width, x + 2)):
                    neighbor: int = ny * sprite.width + nx
                    if mask[neighbor]:
                        mask[neighbor] = 0
                        queue.append(neighbor)
        if len(component) > len(largest):
            largest = component
    # Ignore labels and tiny pieces of neighboring rows without touching the sprite.
    original_alpha: bytes = alpha.tobytes()
    clean: bytearray = bytearray(len(original_alpha))
    for point in largest:
        x, y = point % sprite.width, point // sprite.width
        for ny in range(max(0, y - 1), min(sprite.height, y + 2)):
            for nx in range(max(0, x - 1), min(sprite.width, x + 2)):
                neighbor = ny * sprite.width + nx
                clean[neighbor] = original_alpha[neighbor]
    sprite.putalpha(Image.frombytes("L", sprite.size, bytes(clean)))
    bounds: tuple[int, int, int, int] | None = sprite.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"Missing building at row {row}, column {column}")
    return sprite.crop(bounds)


def hex_extent(sprite: Image.Image) -> float:
    alpha: Image.Image = sprite.getchannel("A")
    extent: float = 0.0
    for y in range(sprite.height):
        for x in range(sprite.width):
            if alpha.getpixel((x, y)) <= 8:
                continue
            px: float = abs(x + 0.5 - sprite.width / 2)
            py: float = abs(y + 0.5 - sprite.height / 2)
            extent = max(extent, py, px + py * 0.5)
    return extent


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    sheet: Image.Image = Image.open(SOURCE).convert("RGBA")
    if sheet.size != (1254, 1254):
        raise ValueError("Crop coordinates are for the approved 1254-pixel sheet")
    preview: Image.Image = Image.new("RGBA", (6 * SIZE, len(NAMES) * (SIZE + 26)))
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    font: ImageFont.FreeTypeFont = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 13)
    manifest: dict = {"source": "res://assets/tiles/buildings/rotated/source/approved_roofs.png", "tile_size": SIZE, "orientation_count": 6, "buildings": []}
    for row, name in enumerate(NAMES):
        sprites: list[Image.Image] = [extract(sheet, row, column) for column in range(6)]
        original_name: str = name
        if name == "building_stone_03":
            original_name = "big_building"
        original: Image.Image = Image.open(ROOT / "assets/tiles/buildings" / f"{original_name}.png").convert("RGBA")
        bounds = original.getchannel("A").point(lambda value: 255 * (value > 8)).getbbox()
        if bounds is None:
            raise ValueError(f"Missing original building bounds for {name}")
        # One common scale per building keeps all six approved views consistent.
        scale: float = min((bounds[2] - bounds[0]) / sprites[0].width, (bounds[3] - bounds[1]) / sprites[0].height, 59.0 / max(hex_extent(sprite) for sprite in sprites))
        atlas: Image.Image = Image.new("RGBA", (6 * SIZE, SIZE))
        for orientation, sprite in enumerate(sprites):
            sprite = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.Resampling.LANCZOS)
            tile: Image.Image = Image.new("RGBA", (SIZE, SIZE))
            tile.alpha_composite(sprite, ((SIZE - sprite.width) // 2, (SIZE - sprite.height) // 2))
            atlas.alpha_composite(tile, (orientation * SIZE, 0))
            preview.alpha_composite(tile, (orientation * SIZE, row * (SIZE + 26) + 26))
        atlas.save(OUTPUT / f"{name}.png")
        draw.text((4, row * (SIZE + 26) + 4), name.replace("building_", "").replace("_", " "), font=font, fill="#e8ddc1", stroke_width=1, stroke_fill="#28322c")
        manifest["buildings"].append({"name": name, "texture": f"res://assets/tiles/buildings/rotated/{name}.png", "scale": scale})
    preview.save(DOCS / "preview.png")
    (DOCS / "export.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Exported six approved building types with six orientations each.")


if __name__ == "__main__":
    main()
