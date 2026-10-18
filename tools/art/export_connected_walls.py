"""Build exact hex connection atlases from the generated wall and hedge materials."""
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/tiles/walls/connected"
DOCS = ROOT / "docs/art/connected_walls"
TILE_SIZE = 128
PADDING = 16
SIZE = TILE_SIZE + PADDING * 2
SCALE = 3
HALF_WIDTH = {"stone": 5.5, "hedge": 9.0}
VERTICES = np.array([[-32, -64], [32, -64], [64, 0], [32, 64], [-32, 64], [-64, 0]], dtype=float)
ENDS = np.array([[0, -64], [48, -32], [48, 32], [0, 64], [-48, 32], [-48, -32]], dtype=float)
LEGACY = {0: ("stone", 8), 1: ("stone", 16), 2: ("stone", 24), 3: ("hedge", 16),
          4: ("stone", 6), 5: ("hedge", 24), 6: ("hedge", 4), 7: ("hedge", 4),
          8: ("hedge", 6), 9: ("hedge", 8)}


def material(kind: str) -> np.ndarray:
    image = Image.open(OUT / "source" / f"{kind}.png").convert("RGBA")
    alpha = np.array(image)[:, :, 3]
    y, x = np.where(alpha > 180)
    left, right, top, bottom = int(x.min()), int(x.max()), int(y.min()), int(y.max())
    margin = (right - left) // 10
    image = image.crop((left + margin, top + 3, right - margin, bottom - 3))
    strip = np.array(image.resize((256, 64), Image.Resampling.LANCZOS))
    # Mirrored repetition gives identical boundary texels without painting new art.
    return np.concatenate((strip, strip[:, ::-1]), axis=1)


def tile(texture: np.ndarray, kind: str, mask: int) -> Image.Image:
    axis = (np.arange(SIZE * SCALE) + 0.5) / SCALE - SIZE / 2
    xx, yy = np.meshgrid(axis, axis)
    points = np.stack((xx, yy), axis=-1)
    # Keep both halves of the strip. Clipping to the owner hex hid half its
    # width and made the barrier visibly belong to that cell.
    radius = HALF_WIDTH[kind]
    nearest = np.full(xx.shape, np.inf)
    tex_x = np.zeros(xx.shape)
    tex_y = np.zeros(xx.shape)
    for side in range(6):
        if not mask & (1 << side):
            continue
        start, end = VERTICES[side], VERTICES[(side + 1) % 6]
        delta = end - start
        length = float(np.linalg.norm(delta))
        unit = delta / length
        canonical = unit.copy()
        canonical_start = start
        if side >= 3:
            canonical *= -1
            canonical_start = end
        normal = np.array([-canonical[1], canonical[0]])
        # The same physical corner anchors the material from either owner.
        # Canonical local offsets also avoid any texture jump across the spine.
        relative = np.round(points - canonical_start, 12)
        along = np.sum(relative * canonical, axis=-1)
        cross = np.sum(relative * normal, axis=-1)
        past_end = np.maximum(np.maximum(-along, along - length), 0)
        distance = np.hypot(cross, past_end)
        selected = distance < nearest
        nearest = np.minimum(nearest, distance)
        phase = np.round((along / (2 * length) + 0.5) % 1, 12)
        tex_x[selected] = phase[selected]
        tex_y[selected] = np.round(np.clip(cross[selected] / (2 * radius) + 0.5, 0, 1), 12)
    rows = np.minimum((tex_y * texture.shape[0]).astype(int), texture.shape[0] - 1)
    columns = (tex_x * texture.shape[1]).astype(int) % texture.shape[1]
    pixels = texture[rows, columns].copy()
    coverage = np.clip((radius - nearest) * SCALE + 0.5, 0, 1)
    pixels[:, :, 3] = np.round(pixels[:, :, 3] * coverage).astype(np.uint8)
    return Image.fromarray(pixels).resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    tiles = {}
    textures = {}
    for kind in ["stone", "hedge"]:
        textures[kind] = material(kind)
        atlas = Image.new("RGBA", (SIZE * 8, SIZE * 8))
        tiles[kind] = []
        for mask in range(64):
            image = Image.new("RGBA", (SIZE, SIZE))
            if mask > 0:
                image = tile(textures[kind], kind, mask)
            tiles[kind].append(image)
            atlas.paste(image, ((mask % 8) * SIZE, (mask // 8) * SIZE))
        atlas.save(OUT / f"{kind}_connections.png")
    for source, (kind, mask) in LEGACY.items():
        tile(textures[kind], kind, mask).save(OUT / f"legacy_{kind}_{source:02}.png")
    preview(tiles)
    (DOCS / "export.json").write_text(json.dumps({
        "tile_size": TILE_SIZE, "region_size": SIZE, "padding": PADDING,
        "alignment": "full strip centered on the shared hex spine",
        "visible_width_multiplier": 2, "widths": {kind: radius * 2 for kind, radius in HALF_WIDTH.items()},
        "columns": 8, "connections": ["n", "ne", "se", "s", "sw", "nw"],
        "styles": [{"name": "Stone Wall", "texture": "res://assets/tiles/walls/connected/stone_connections.png", "cover": 2},
                   {"name": "Hedge", "texture": "res://assets/tiles/walls/connected/hedge_connections.png", "cover": 1}],
        "legacy_sources": LEGACY,
    }, indent=2) + "\n")
    print("Exported 126 hex-edge tiles, 10 legacy edge sprites and a placement preview.")


def preview(tiles: dict) -> None:
    board = Image.new("RGBA", (1536, 1120), (40, 51, 33, 255))
    draw = ImageDraw.Draw(board)
    font_path = "/usr/share/fonts/TTF/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 25)
    title = ImageFont.truetype(font_path, 35)
    draw.text((40, 22), "Stone walls and hedgerows on hex edges", font=title, fill="#efe9d8")
    draw.text((40, 76), "Edge brush: draw along borders. All pieces meet at the same vertices.", font=font, fill="#b8c8aa")
    for kind, offset in [("stone", (96, 174)), ("hedge", (824, 174))]:
        draw.text((offset[0] - 32, offset[1] - 28), "Stone wall" if kind == "stone" else "Hedgerow", font=font, fill="#efe9d8")
        cells = {(x, y) for x in range(1, 5) for y in range(2, 5)}
        for x in range(7):
            for y in range(7):
                center = np.array([offset[0] + x * 96, offset[1] + y * 128 + (x % 2) * 64])
                draw.polygon([tuple(center + vertex) for vertex in VERTICES], outline=(87, 108, 64, 90))
        for cell in sorted(cells):
            x, y = cell
            center = np.array([x * 96, y * 128 + (x % 2) * 64])
            mask = 0
            for side, end in enumerate(ENDS):
                neighbor_center = center + end * 2
                nx = round(neighbor_center[0] / 96)
                ny = round((neighbor_center[1] - (nx % 2) * 64) / 128)
                if (nx, ny) not in cells:
                    mask |= 1 << side
            if x == 2:
                mask |= (1 << 1) | (1 << 2)
            board.alpha_composite(tiles[kind][mask], (int(center[0] + offset[0] - SIZE / 2), int(center[1] + offset[1] - SIZE / 2)))
    board.convert("RGB").save(DOCS / "preview.png")


if __name__ == "__main__":
    main()
