"""Check visible road continuity using the exported game atlas regions."""

from pathlib import Path
import json
import math
import sys
from PIL import Image, ImageDraw, ImageOps

ROOT: Path = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/campaigns"))
from render_alderbrook_maps import texture


def check_map(path: Path) -> int:
    data: dict = json.loads(path.read_text())
    width: int = data["size"][0] * 96 + 32
    height: int = data["size"][1] * 128 + 64
    overlay: Image.Image = Image.new("RGBA", (width, height))
    footprint: Image.Image = Image.new("L", (width, height))
    mask: ImageDraw.ImageDraw = ImageDraw.Draw(footprint)
    cache: dict[str, Image.Image] = {}
    assert sum(layer["name"] == "RoadTileMapLayer" for layer in data["layers"]) == 1, f"{data['id']}: roads need a separate layer"
    for layer in data["layers"]:
        for cell in layer["cells"]:
            px, py = cell["position"]
            if layer["name"] == "GroundTileMapLayer":
                mask.polygon([(px - 32, py - 64), (px + 32, py - 64), (px + 64, py), (px + 32, py + 64), (px - 32, py + 64), (px - 64, py)], fill=255)
            name: str = Path(cell["texture"]).stem
            if not name.startswith("road_") and name != "bridge":
                continue
            if name.startswith("road_"):
                assert layer["name"] == "RoadTileMapLayer", f"{data['id']}: road art remains in {layer['name']}"
            tile: Image.Image = texture(cell["texture"], cache)
            x, y, w, h = cell.get("texture_region", [0, 0, tile.width, tile.height])
            tile = tile.crop((x, y, x + w, y + h))
            if cell["flip_h"]:
                tile = ImageOps.mirror(tile)
            if cell["flip_v"]:
                tile = ImageOps.flip(tile)
            overlay.alpha_composite(tile, (round(px - 64), round(py - 64)))
    samples: set[tuple[int, int]] = set()
    for line in data["road_centerlines"]:
        for first, second in zip(line, line[1:]):
            length: int = math.ceil(math.dist(first, second))
            for step in range(length + 1):
                fraction: float = step / max(1, length)
                x: int = round(first[0] + (second[0] - first[0]) * fraction)
                y: int = round(first[1] + (second[1] - first[1]) * fraction)
                if 0 <= x < width and 0 <= y < height and footprint.getpixel((x, y)) == 255:
                    samples.add((x, y))
    gaps: list[tuple[int, int]] = []
    for point in samples:
        red, green, blue, alpha = overlay.getpixel(point)
        if alpha < 190 or red <= green or green <= blue:
            gaps.append(point)
    assert not gaps, f"{data['id']}: visible road gaps at {sorted(gaps)[:12]}"
    assert len(samples) > width * 0.75, f"{data['id']}: road continuity check needs a complete route"
    print(f"{data['id']}: {len(samples)} road centerline pixels; no gaps")
    return len(samples)


if __name__ == "__main__":
    sources: list[Path] = [path for path in sorted((ROOT / "docs/campaigns/road_to_alderbrook/maps").glob("0*.json")) if "layers" in json.loads(path.read_text())]
    assert len(sources) == 5, "Road continuity must cover all five campaign maps"
    total: int = sum(check_map(path) for path in sources)
    print(f"Road art checks: {total} centerline pixels across five maps")
