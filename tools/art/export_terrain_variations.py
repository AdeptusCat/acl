"""Export the five terrain families as three game-ready hex variations each."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT: Path = Path(__file__).resolve().parents[2]
FAMILIES: dict[str, tuple[str, str]] = {
    "open_ground_green": ("vegetation", "Open ground"),
    "woods_green": ("vegetation", "Woods"),
    "field_wheat": ("fields", "Wheat"),
    "field_green_rows": ("fields", "Green crops"),
    "orchard_green": ("orchard", "Orchard"),
}


def visible_alpha(value: int) -> int:
    if value > 8:
        return 255
    return 0


def main() -> None:
    preview: Image.Image = Image.new("RGB", (840, 1580), "#e9e4d7")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    font: ImageFont.ImageFont = ImageFont.load_default(size=22)
    for row, (family, (directory, label)) in enumerate(FAMILIES.items()):
        draw.text((18, row * 316 + 12), label, font=font, fill="#25352f")
        for column in range(3):
            name: str = f"{family}_{column + 1:02d}"
            folder: Path = ROOT / "assets/tiles" / directory
            source: Image.Image = Image.open(folder / "source" / f"{name}.png").convert("RGBA")
            alpha: Image.Image = source.getchannel("A")
            bounds: tuple[int, int, int, int] | None = alpha.point(visible_alpha).getbbox()
            if bounds is None or alpha.getextrema()[0] != 0:
                raise ValueError(f"{name} must have transparent surroundings")
            tile: Image.Image = source.crop(bounds).resize((64, 64), Image.Resampling.LANCZOS)
            tile.save(folder / f"{name}.png")
            enlarged: Image.Image = tile.resize((256, 256), Image.Resampling.NEAREST)
            preview.paste(enlarged, (column * 280 + 12, row * 316 + 48), enlarged)
    output: Path = ROOT / "docs/art/terrain_variations"
    output.mkdir(parents=True, exist_ok=True)
    preview.save(output / "preview.png")
    print("Exported 15 transparent 64x64 terrain variations and their preview.")


if __name__ == "__main__":
    main()
