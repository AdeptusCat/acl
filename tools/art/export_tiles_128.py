"""Export whole terrain stamps and 128-pixel tiles with alpha for pixel-based LOS."""

from collections import deque
from pathlib import Path
from random import Random
from PIL import Image

ROOT: Path = Path(__file__).resolve().parents[2]
TILES: Path = ROOT / "assets/tiles"
CONNECTED: Path = TILES / "connected"
STAMPS: Path = CONNECTED / "stamps"
SIZE: int = 128


def solid_alpha(value: int) -> int:
    if value > 8:
        return 255
    return 0


def fit_sprite(image: Image.Image, size: int) -> Image.Image:
    bounds: tuple[int, int, int, int] | None = image.getchannel("A").point(solid_alpha).getbbox()
    if bounds is None:
        raise ValueError("Empty source sprite")
    sprite: Image.Image = image.crop(bounds)
    sprite.thumbnail((size - 4, size - 4), Image.Resampling.LANCZOS)
    tile: Image.Image = Image.new("RGBA", (size, size))
    tile.alpha_composite(sprite, ((size - sprite.width) // 2, (size - sprite.height) // 2))
    return tile


def normalize(source: Path, size: tuple[int, int]) -> Image.Image:
    image: Image.Image = Image.open(source).convert("RGBA")
    bounds: tuple[int, int, int, int] | None = image.getchannel("A").point(solid_alpha).getbbox()
    if bounds is None:
        raise ValueError(f"Empty source sprite: {source}")
    return image.crop(bounds).resize(size, Image.Resampling.LANCZOS)


def crown_regions(image: Image.Image) -> list[tuple[int, int, int, int]]:
    """Extract the four full sprites independently of their sheet's gutters."""
    mask: bytearray = bytearray(image.getchannel("A").point(solid_alpha).tobytes())
    components: list[tuple[int, tuple[int, int, int, int]]] = []
    width: int = image.width
    for start in range(len(mask)):
        if mask[start] == 0:
            continue
        queue: deque[int] = deque([start])
        mask[start] = 0
        count: int = 0
        left: int = width
        top: int = image.height
        right: int = 0
        bottom: int = 0
        while queue:
            point: int = queue.popleft()
            x: int = point % width
            y: int = point // width
            count += 1
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x), max(bottom, y)
            neighbors: list[int] = []
            if x > 0:
                neighbors.append(point - 1)
            if x + 1 < width:
                neighbors.append(point + 1)
            if y > 0:
                neighbors.append(point - width)
            if y + 1 < image.height:
                neighbors.append(point + width)
            for neighbor in neighbors:
                if mask[neighbor] != 0:
                    mask[neighbor] = 0
                    queue.append(neighbor)
        if count > 1024:
            components.append((count, (max(0, left - 4), max(0, top - 4), min(width, right + 5), min(image.height, bottom + 5))))
    components.sort(reverse=True)
    if len(components) < 4:
        raise ValueError("Fruit crown sheet must have four separate full trees")
    regions: list[tuple[int, int, int, int]] = [component[1] for component in components[:4]]
    regions.sort(key=lambda region: (region[1] + region[3], region[0]))
    return sorted(regions[:2]) + sorted(regions[2:])


def export_stamps() -> None:
    STAMPS.mkdir(exist_ok=True)
    trees: Image.Image = Image.open(CONNECTED / "source/tree_crowns.png").convert("RGBA")
    # Gutters separate complete silhouettes, including the elongated third crown.
    regions: list[tuple[int, int, int, int]] = [(0, 0, 700, 610), (700, 0, 1254, 640), (0, 610, 700, 1254), (700, 640, 1254, 1254)]
    for index, region in enumerate(regions, 1):
        fit_sprite(trees.crop(region), 64).save(STAMPS / f"tree_{index:02}.png")
    fruit: Image.Image = Image.open(CONNECTED / "source/fruit_crowns.png").convert("RGBA")
    for index, region in enumerate(crown_regions(fruit), 1):
        fit_sprite(fruit.crop(region), 64).save(STAMPS / f"fruit_{index:02}.png")
    for family, source in [("wheat", "wheat_stand"), ("crops", "crop_stand")]:
        fit_sprite(Image.open(CONNECTED / f"source/{source}.png").convert("RGBA"), 64).save(STAMPS / f"{family}.png")


def whole_stamp_fits(origin: tuple[int, int], stamp: Image.Image, size: int, fringe: float) -> bool:
    alpha = stamp.getchannel("A")
    for y in range(stamp.height):
        for x in range(stamp.width):
            if alpha.getpixel((x, y)) > 0:
                px: float = origin[0] + x + 0.5 - size / 2
                py: float = origin[1] + y + 0.5 - size / 2
                if abs(py) > size / 2 - fringe or abs(px) + abs(py) * 0.5 > size / 2 - fringe:
                    return False
    return True


def terrain_tile(family: str, variant: int, size: int = SIZE) -> Image.Image:
    tile: Image.Image = Image.new("RGBA", (size, size))
    random: Random = Random(713 + variant * 479)
    if family == "orchard":
        for row in range(-size // 34, size // 34 + 1):
            for column in range(-size // 36, size // 36 + 1):
                x: int = size // 2 + column * 36 + row % 2 * 18 + random.randrange(-3, 4)
                y: int = size // 2 + row * 34 + random.randrange(-3, 4)
                crown: Image.Image = Image.open(STAMPS / f"fruit_{random.randrange(1, 5):02}.png").convert("RGBA")
                extent: int = random.randrange(32, 41)
                crown = crown.resize((extent, extent), Image.Resampling.LANCZOS)
                origin: tuple[int, int] = (x - extent // 2, y - extent // 2)
                if not whole_stamp_fits(origin, crown, size, 4):
                    crown = crown.resize((24, 24), Image.Resampling.LANCZOS)
                    origin = (x - 12, y - 12)
                if whole_stamp_fits(origin, crown, size, 4):
                    tile.alpha_composite(crown, origin)
    elif family == "woods":
        spacing: int = 24
        for y in range(12, size, spacing):
            for x in range(12, size, spacing):
                crown = Image.open(STAMPS / f"tree_{random.randrange(1, 5):02}.png").convert("RGBA")
                extent: int = random.randrange(22, 39)
                crown = crown.resize((extent, extent), Image.Resampling.LANCZOS)
                origin: tuple[int, int] = (x + random.randrange(-5, 6) - extent // 2, y + random.randrange(-5, 6) - extent // 2)
                if whole_stamp_fits(origin, crown, size, 6):
                    tile.alpha_composite(crown, origin)
    else:
        stand: Image.Image = Image.open(STAMPS / f"{family}.png").convert("RGBA").resize((32, 32), Image.Resampling.LANCZOS)
        fringe: Image.Image = stand.resize((16, 16), Image.Resampling.LANCZOS)
        for y in range(0, size, 14):
            for x in range(0, size, 14):
                origin = (x + random.randrange(-3, 4) - 16, y + random.randrange(-3, 4) - 16)
                if whole_stamp_fits(origin, stand, size, 6):
                    tile.alpha_composite(stand, origin)
                else:
                    origin = (origin[0] + 8, origin[1] + 8)
                    if whole_stamp_fits(origin, fringe, size, 6):
                        tile.alpha_composite(fringe, origin)
    return tile


def main() -> None:
    export_stamps()
    for family in ["woods", "wheat", "crops", "orchard"]:
        terrain_tile(family, 0, 256).save(CONNECTED / f"{family}.png")
    for folder in ["vegetation", "fields", "orchard"]:
        for source in (TILES / folder / "source").glob("*.png"):
            name: str = source.stem
            family: str = ""
            if name.startswith("woods"):
                family = "woods"
            elif name.startswith("field_wheat"):
                family = "wheat"
            elif name.startswith("field_green_rows"):
                family = "crops"
            elif name.startswith("orchard"):
                family = "orchard"
            if family:
                variant: int = 0
                if name[-2:].isdigit():
                    variant = int(name[-2:]) - 1
                image: Image.Image = terrain_tile(family, variant)
            else:
                image = normalize(source, (SIZE, SIZE))
            image.save(TILES / folder / source.name)
    # Scale grid art only. Unit markers and other HUD textures keep their UI size.
    for folder in [TILES, ROOT / "assets/objectives"]:
        for path in folder.rglob("*.png"):
            if "source" in path.parts or "connected" in path.parts:
                continue
            image = Image.open(path).convert("RGBA")
            if image.size == (64, 64):
                image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(path)
            elif image.size == (128, 64):
                image.resize((SIZE * 2, SIZE), Image.Resampling.LANCZOS).save(path)
    buildings: Image.Image = Image.open(CONNECTED / "source/buildings.png").convert("RGBA")
    regions: list[tuple[int, int, int, int]] = [(15, 40, 490, 490), (505, 60, 1020, 480), (1020, 10, 1536, 510), (15, 535, 470, 1010), (470, 535, 1030, 1010), (1040, 535, 1536, 1024)]
    names: list[str] = ["building_stone_01", "building_stone_02", "big_building", "building_wood_01", "building_wood_02", "building_wood_03"]
    for name, region in zip(names, regions):
        sprite: Image.Image = buildings.crop(region)
        bounds = sprite.getchannel("A").point(solid_alpha).getbbox()
        assert bounds is not None
        sprite = sprite.crop(bounds)
        sprite.thumbnail((88, 96), Image.Resampling.LANCZOS)
        tile: Image.Image = Image.new("RGBA", (SIZE, SIZE))
        tile.alpha_composite(sprite, ((SIZE - sprite.width) // 2, (SIZE - sprite.height) // 2))
        tile.save(TILES / "buildings" / f"{name}.png")
    for alias, name in [("house", "building_stone_01"), ("house2", "building_stone_02")]:
        Image.open(TILES / "buildings" / f"{name}.png").save(TILES / "buildings" / f"{alias}.png")
    Image.open(TILES / "vegetation/woods_green_01.png").save(TILES / "buildings/woods.png")
    Image.open(TILES / "orchard/orchard_green_01.png").save(TILES / "buildings/orchard.png")
    print("Exported whole terrain stamps and 128-pixel terrain tiles.")


if __name__ == "__main__":
    main()
