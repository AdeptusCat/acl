"""Export generated spring/summer vegetation as 64-pixel hex sprites."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT: Path = Path(__file__).resolve().parents[2]
ASSETS: Path = ROOT / "assets/tiles/vegetation"
VARIANTS: dict[str, str] = {
    "open_ground_green": "Open ground",
    "woods_green": "Woods",
}


def visible_alpha(value: int) -> int:
    if value > 8:
        return 255
    return 0


def main() -> None:
    preview: Image.Image = Image.new("RGB", (560, 342), "#e9e4d7")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    font: ImageFont.ImageFont = ImageFont.load_default(size=20)
    for index, (name, label) in enumerate(VARIANTS.items()):
        source: Image.Image = Image.open(ASSETS / "source" / f"{name}.png").convert("RGBA")
        alpha: Image.Image = source.getchannel("A")
        bounds: tuple[int, int, int, int] | None = alpha.point(visible_alpha).getbbox()
        if bounds is None or alpha.getextrema()[0] != 0:
            raise ValueError(f"{name} must have a visible sprite and transparent surroundings")
        tile: Image.Image = source.crop(bounds).resize((64, 64), Image.Resampling.LANCZOS)
        tile.save(ASSETS / f"{name}.png")
        enlarged: Image.Image = tile.resize((256, 256), Image.Resampling.NEAREST)
        preview.paste(enlarged, (index * 280 + 12, 20), enlarged)
        draw.text((index * 280 + 140, 300), label, font=font, fill="#25352f", anchor="mm")
    output: Path = ROOT / "docs/art/vegetation_tiles"
    output.mkdir(parents=True, exist_ok=True)
    preview.save(output / "preview.png")
    print("Exported two transparent 64x64 vegetation tiles and their game-size preview.")


if __name__ == "__main__":
    main()
