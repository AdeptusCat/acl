"""Extract six generated views and partition each building into real hex cells."""

from collections import deque
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT: Path = Path(__file__).resolve().parents[2]
OUTPUT: Path = ROOT / "assets/tiles/buildings/multihex"
DOCS: Path = ROOT / "docs/art/multihex_buildings"
SIZE: int = 128


def extract(sheet: Image.Image, orientation: int) -> Image.Image:
    column, row = orientation % 3, orientation // 3
    cell: Image.Image = sheet.crop((max(0, round(column * sheet.width / 3) - 40), max(0, round(row * sheet.height / 2) - 40), min(sheet.width, round((column + 1) * sheet.width / 3) + 40), min(sheet.height, round((row + 1) * sheet.height / 2) + 40)))
    alpha: Image.Image = cell.getchannel("A")
    mask: bytearray = bytearray(alpha.point(lambda value: 255 * (value >= 128)).tobytes())
    largest: list[int] = []
    for start in range(len(mask)):
        if not mask[start]:
            continue
        queue: deque[int] = deque([start])
        mask[start] = 0
        component: list[int] = []
        while queue:
            point: int = queue.popleft()
            component.append(point)
            x, y = point % cell.width, point // cell.width
            for yy in range(max(0, y - 1), min(cell.height, y + 2)):
                for xx in range(max(0, x - 1), min(cell.width, x + 2)):
                    neighbor: int = yy * cell.width + xx
                    if mask[neighbor]:
                        mask[neighbor] = 0
                        queue.append(neighbor)
        if len(component) > len(largest):
            largest = component
    if len(largest) < 2000:
        raise ValueError(f"Missing building view {orientation}")
    # Preserve sprite pixels and their antialiased fringe; exclude sheet artifacts.
    original: bytes = alpha.tobytes()
    clean: bytearray = bytearray(len(original))
    for point in largest:
        x, y = point % cell.width, point // cell.width
        for yy in range(max(0, y - 1), min(cell.height, y + 2)):
            for xx in range(max(0, x - 1), min(cell.width, x + 2)):
                neighbor = yy * cell.width + xx
                clean[neighbor] = original[neighbor]
    cell.putalpha(Image.frombytes("L", cell.size, bytes(clean)))
    bounds = cell.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Empty generated building")
    if bounds[0] == 0 or bounds[1] == 0 or bounds[2] == cell.width or bounds[3] == cell.height:
        raise ValueError(f"Generated view {orientation} touches its sheet cell edge")
    return cell.crop(bounds)


def mass_center(sprite: Image.Image) -> tuple[float, float]:
    y, x = np.nonzero(np.asarray(sprite.getchannel("A")) >= 128)
    return float(x.mean() + 0.5), float(y.mean() + 0.5)


def scale_for(sprites: list[Image.Image], hexes: int, region: int) -> float:
    scale: float = (hexes * SIZE - 32) / sprites[0].height
    for sprite in sprites:
        x, y = mass_center(sprite)
        scale = min(scale, (region / 2 - 8) / max(x, sprite.width - x, y, sprite.height - y))
    return scale * 0.98


def angle_order(sprites: list[Image.Image]) -> list[Image.Image]:
    # Identify opposite diagonal columns without modifying the generated views.
    result: list[Image.Image] = list(sprites)
    for first, second in [(1, 2), (4, 5)]:
        directions: list[float] = []
        for index in [first, second]:
            y, x = np.nonzero(np.asarray(result[index].getchannel("A")) > 128)
            directions.append(float(np.cov(x, y)[0, 1]))
        if directions[0] > 0 and directions[1] < 0:
            result[first], result[second] = result[second], result[first]
        elif not (directions[0] < 0 and directions[1] > 0):
            raise ValueError("Generated diagonal angles are duplicated or ambiguous")
    return result


def render_view(sprite: Image.Image, scale: float, parts: list[dict], region: int) -> tuple[Image.Image, list[Image.Image]]:
    centers: np.ndarray = np.array([part["center"] for part in parts], dtype=int)
    # Non-collinear footprints can have fractional centroids. Keep the common
    # drawing origin on whole pixels so every cell aligns exactly in Godot.
    center: np.ndarray = np.rint(centers.mean(axis=0)).astype(int)
    canvas: Image.Image = Image.new("RGBA", (region, region))
    scaled: Image.Image = sprite.resize((round(sprite.width * scale), round(sprite.height * scale)), Image.Resampling.LANCZOS)
    cx, cy = mass_center(scaled)
    canvas.alpha_composite(scaled, (round(region / 2 - cx), round(region / 2 - cy)))
    yy, xx = np.indices((region, region), dtype=float)
    x, y = xx + 0.5 - region / 2 + center[0], yy + 0.5 - region / 2 + center[1]
    distances: np.ndarray = np.array([(x - cx) ** 2 + (y - cy) ** 2 for cx, cy in centers])
    ownership: np.ndarray = distances.argmin(axis=0)
    tiles: list[Image.Image] = []
    for part, (cx, cy) in enumerate(centers):
        pixels: np.ndarray = np.array(canvas)
        pixels[ownership != part] = 0
        tile = Image.fromarray(pixels)
        px, py = np.abs(x - cx), np.abs(y - cy)
        inside: np.ndarray = (py <= 64) & (px + py * 0.5 <= 64)
        if np.count_nonzero((pixels[..., 3] > 26) & inside) < 512:
            raise ValueError("The building must occupy visible roof area in every footprint hex")
        parts[part]["texture_origin"] = [int(cx - center[0]), int(cy - center[1])]
        tiles.append(tile)
    # Reconstruct the exact pattern rendering for the exported designer preview.
    pattern: Image.Image = Image.new("RGBA", canvas.size)
    for tile in tiles:
        pattern.alpha_composite(tile)
    if np.any(np.asarray(canvas) != np.asarray(pattern)):
        raise ValueError("Hex pieces changed the complete building silhouette")
    # Draw the roof once; the remaining pieces supply cell-specific cover pixels.
    # This avoids filtering seams when zooming between adjacent fragments.
    tiles[0] = canvas.copy()
    return pattern, tiles


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    parser.add_argument("--partial", action="store_true")
    args: argparse.Namespace = parser.parse_args()
    definitions: list[dict] = json.loads((DOCS / "prompts.json").read_text())["designs"]
    footprints: dict = json.loads((DOCS / "footprints.json").read_text())
    records: list[dict] = []
    font_path: Path = Path("/usr/share/fonts/TTF/DejaVuSans.ttf")
    if not font_path.exists():
        font_path = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    font: ImageFont.FreeTypeFont = ImageFont.truetype(str(font_path), 14)
    preview: Image.Image = Image.new("RGBA", (6 * 336, len(definitions) * 420))
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    for index, definition in enumerate(definitions):
        source: Path = OUTPUT / "source" / (definition["id"] + ".png")
        if not source.exists():
            if args.partial:
                continue
            raise ValueError(f"Missing generated source sheet: {source}")
        sheet: Image.Image = Image.open(source).convert("RGBA")
        try:
            sprites: list[Image.Image] = angle_order([extract(sheet, orientation) for orientation in range(6)])
            views: list[dict] = footprints[str(definition["count"])]
            region: int = definition["count"] * SIZE
            scale: float = scale_for(sprites, definition["count"], region)
            rendered: list[tuple[Image.Image, list[Image.Image]]] = []
            for orientation, (sprite, view) in enumerate(zip(sprites, views)):
                rendered.append(render_view(sprite, scale, view["parts"], region))
        except ValueError as error:
            if args.partial:
                print(f"FAILED {definition['id']}: {error}", flush=True)
                continue
            raise ValueError(f"{definition['id']}: {error}") from error
        atlas: Image.Image = Image.new("RGBA", (6 * region, definition["count"] * region))
        variant: str = "three hexes"
        if definition["count"] == 2:
            variant = "two hexes " + definition["variant"][-1].upper()
        label: str = definition["material"].title() + " Building " + definition["type"] + " - " + variant
        for orientation, (pattern, tiles) in enumerate(rendered):
            for part, tile in enumerate(tiles):
                atlas.alpha_composite(tile, (orientation * region, part * region))
            pattern = pattern.crop(pattern.getchannel("A").getbbox())
            point: tuple[int, int] = (orientation * 336 + (336 - pattern.width) // 2, index * 420 + 30 + (384 - pattern.height) // 2)
            preview.alpha_composite(pattern, point)
            draw.text((orientation * 336 + 6, index * 420 + 5), label + f" / {orientation * 60} degrees", fill="#e8ddc1", font=font, stroke_width=1, stroke_fill="#28322c")
        atlas.save(OUTPUT / (definition["id"] + ".png"))
        records.append({"id": definition["id"], "label": label, "material": definition["material"], "parent": "building_" + definition["material"] + "_" + definition["type"], "hexes": definition["count"], "region_size": region, "texture": "res://assets/tiles/buildings/multihex/" + definition["id"] + ".png", "scale": scale, "views": views})
        print(f"Exported {definition['id']}: {definition['count']} hexes, scale {scale:.4f}")
    preview.save(DOCS / "preview.png")
    for index in range(0, len(definitions), 3):
        name: str = definitions[index]["material"] + "_" + definitions[index]["type"]
        preview.crop((0, index * 420, preview.width, (index + 3) * 420)).save(DOCS / (name + ".png"))
    (DOCS / "export.json").write_text(json.dumps({"tile_size": SIZE, "orientation_count": 6, "buildings": records}, indent=2) + "\n")
    print(f"Exported {len(records)} designs and {len(records) * 6} complete building patterns.")


if __name__ == "__main__":
    main()
