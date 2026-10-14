"""Export source art at 128 pixels and retain alpha for pixel-based line of sight."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageChops

ROOT: Path = Path(__file__).resolve().parents[2]
TILES: Path = ROOT / "assets/tiles"
CONNECTED: Path = TILES / "connected"
SIZE: int = 128


def solid_alpha(value: int) -> int:
    if value > 8:
        return 255
    return 0


def normalize(source: Path, size: tuple[int, int]) -> Image.Image:
    image: Image.Image = Image.open(source).convert("RGBA")
    bounds: tuple[int, int, int, int] | None = image.getchannel("A").point(solid_alpha).getbbox()
    if bounds is None:
        raise ValueError(f"Empty source sprite: {source}")
    return image.crop(bounds).resize(size, Image.Resampling.LANCZOS)


def main() -> None:
    # Keep a map-space texture independent of the final hex boundary.
    for family in ["woods", "wheat", "crops"]:
        image: Image.Image = Image.open(CONNECTED / "source" / f"{family}.png").convert("RGBA")
        image.resize((256, 256), Image.Resampling.LANCZOS).save(CONNECTED / f"{family}.png")
    # Orchard uses separated tree crowns, with transparent lanes between them.
    woods: Image.Image = Image.open(CONNECTED / "woods.png").convert("RGBA")
    orchard: Image.Image = Image.new("RGBA", (256, 256))
    crown: Image.Image = woods.crop((20, 20, 115, 115)).resize((58, 58), Image.Resampling.LANCZOS)
    for y in range(8, 256, 85):
        for x in range(8, 256, 85):
            orchard.alpha_composite(crown, (x, y))
    orchard.save(CONNECTED / "orchard.png")
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
                pattern: Image.Image = Image.open(CONNECTED / f"{family}.png").convert("RGBA")
                variant: int = 0
                if name[-2:].isdigit():
                    variant = int(name[-2:]) - 1
                image = pattern.crop((variant * 32, variant * 16, variant * 32 + SIZE, variant * 16 + SIZE))
                mask: Image.Image = Image.new("L", (SIZE, SIZE))
                ImageDraw.Draw(mask).polygon([(38, 12), (90, 12), (116, 64), (90, 116), (38, 116), (12, 64)], fill=255)
                image.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
            else:
                image = normalize(source, (SIZE, SIZE))
            image.save(TILES / folder / source.name)
    # Grid markers, walls and legacy terrain retain their shapes at the new spacing.
    for folder in [TILES, ROOT / "assets/objectives", ROOT / "assets/ui"]:
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
    print("Exported 128-pixel terrain, buildings, walls and grid markers.")


if __name__ == "__main__":
    main()
