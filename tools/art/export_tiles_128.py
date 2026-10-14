"""Export whole terrain stamps and 128-pixel tiles with alpha for pixel-based LOS."""

from math import sqrt
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


def export_stamps() -> None:
    STAMPS.mkdir(exist_ok=True)
    trees: Image.Image = Image.open(CONNECTED / "source/tree_crowns.png").convert("RGBA")
    # Gutters separate complete silhouettes, including the elongated third crown.
    regions: list[tuple[int, int, int, int]] = [(0, 0, 700, 610), (700, 0, 1254, 640), (0, 610, 700, 1254), (700, 640, 1254, 1254)]
    for index, region in enumerate(regions, 1):
        fit_sprite(trees.crop(region), 64).save(STAMPS / f"tree_{index:02}.png")
    for family, source in [("wheat", "wheat_clump"), ("crops", "crop_clump")]:
        fit_sprite(Image.open(CONNECTED / f"source/{source}.png").convert("RGBA"), 32).save(STAMPS / f"{family}.png")


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
    if family in ["woods", "orchard"]:
        spacing: int = 24
        if family == "orchard":
            spacing = 60
        for y in range(12, size, spacing):
            for x in range(12, size, spacing):
                crown: Image.Image = Image.open(STAMPS / f"tree_{random.randrange(1, 5):02}.png").convert("RGBA")
                extent: int = random.randrange(22, 39)
                crown = crown.resize((extent, extent), Image.Resampling.LANCZOS)
                origin: tuple[int, int] = (x + random.randrange(-5, 6) - extent // 2, y + random.randrange(-5, 6) - extent // 2)
                if whole_stamp_fits(origin, crown, size, 6):
                    tile.alpha_composite(crown, origin)
    else:
        plant: Image.Image = Image.open(STAMPS / f"{family}.png").convert("RGBA").resize((6, 6), Image.Resampling.LANCZOS)
        for row in range(-size // 9, size // 9 + 1):
            for column in range(-size // 4, size // 4 + 1):
                x: int = round((column * 4 + row * 9) / sqrt(2)) + size // 2
                y: int = round((-column * 4 + row * 9) / sqrt(2)) + size // 2
                origin = (x - 3, y - 3)
                if whole_stamp_fits(origin, plant, size, 6):
                    tile.alpha_composite(plant, origin)
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
