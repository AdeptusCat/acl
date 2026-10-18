"""Fit each new landmark wholly inside its three real hexes at all six angles."""

import copy
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from export_asl_buildings import triangle_views
from export_multihex_buildings import mass_center

ROOT: Path = Path(__file__).resolve().parents[2]
DOCS: Path = ROOT / "docs/art/three_hex_landmarks"
OUTPUT: Path = ROOT / "assets/tiles/buildings/multihex/three_hex_landmarks"
REGION: int = 384
INSET: int = 3
OFFSETS: list[tuple[int, int]] = sorted([(x, y) for y in range(-40, 41, 2) for x in range(-40, 41, 2)], key=lambda point: point[0] ** 2 + point[1] ** 2)


def isolated_roof(source: Image.Image) -> Image.Image:
    """Retain the connected generated building and its original alpha fringe."""
    alpha: Image.Image = source.getchannel("A")
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
            x, y = point % source.width, point // source.width
            for yy in range(max(0, y - 1), min(source.height, y + 2)):
                for xx in range(max(0, x - 1), min(source.width, x + 2)):
                    neighbor: int = yy * source.width + xx
                    if mask[neighbor]:
                        mask[neighbor] = 0
                        queue.append(neighbor)
        if len(component) > len(largest):
            largest = component
    if len(largest) < 2000:
        raise ValueError("Missing connected generated building")
    original: bytes = alpha.tobytes()
    clean: bytearray = bytearray(len(original))
    for point in largest:
        x, y = point % source.width, point // source.width
        for yy in range(max(0, y - 1), min(source.height, y + 2)):
            for xx in range(max(0, x - 1), min(source.width, x + 2)):
                neighbor: int = yy * source.width + xx
                clean[neighbor] = original[neighbor]
    source.putalpha(Image.frombytes("L", source.size, bytes(clean)))
    bounds: tuple[int, int, int, int] = source.getchannel("A").getbbox()
    if bounds[0] == 0 or bounds[1] == 0 or bounds[2] == source.width or bounds[3] == source.height:
        raise ValueError("The generated roof is clipped by its source image")
    return source.crop(bounds)


def masks_for(parts: list[dict]) -> tuple[list[np.ndarray], np.ndarray]:
    centers: np.ndarray = np.array([part["center"] for part in parts], dtype=int)
    center: np.ndarray = np.rint(centers.mean(axis=0)).astype(int)
    yy, xx = np.indices((REGION, REGION), dtype=float)
    x, y = xx + 0.5 - REGION / 2 + center[0], yy + 0.5 - REGION / 2 + center[1]
    masks: list[np.ndarray] = [(np.abs(y - cy) <= 64) & (np.abs(x - cx) + np.abs(y - cy) * 0.5 <= 64) for cx, cy in centers]
    union: np.ndarray = np.logical_or.reduce(masks)
    padded: np.ndarray = np.pad(union, INSET, constant_values=False)
    inset: Image.Image = Image.fromarray(padded.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(INSET * 2 + 1))
    for part, (cx, cy) in enumerate(centers):
        parts[part]["texture_origin"] = [int(cx - center[0]), int(cy - center[1])]
    return masks, np.asarray(inset)[INSET:-INSET, INSET:-INSET] > 0


def fit_view(sprite: Image.Image, scale: float, safe: np.ndarray) -> tuple[Image.Image, list[int]] | None:
    scaled: Image.Image = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.Resampling.LANCZOS)
    solid: np.ndarray = np.asarray(scaled.getchannel("A")) > 0
    padded: np.ndarray = np.pad(solid, 1, constant_values=False)
    eroded: np.ndarray = np.asarray(Image.fromarray(padded.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3)))[1:-1, 1:-1]
    edge: np.ndarray = solid & (eroded == 0)
    yy, xx = np.nonzero(edge)
    cx, cy = mass_center(scaled)
    origin_x, origin_y = round(REGION / 2 - cx), round(REGION / 2 - cy)
    for dx, dy in OFFSETS:
        px, py = xx + origin_x + dx, yy + origin_y + dy
        if px.min() < 0 or py.min() < 0 or px.max() >= REGION or py.max() >= REGION:
            continue
        if not safe[py, px].all():
            continue
        canvas: Image.Image = Image.new("RGBA", (REGION, REGION))
        canvas.alpha_composite(scaled, (origin_x + dx, origin_y + dy))
        # Check every nonzero alpha value, including resampling fringes. The
        # boundary-only search is an optimization, never the final guarantee.
        if np.any((np.asarray(canvas)[..., 3] > 0) & ~safe):
            continue
        if np.count_nonzero(np.asarray(canvas)[..., 3]) != np.count_nonzero(solid):
            raise ValueError("Atlas canvas cropped the generated roof")
        return canvas, [dx, dy]
    return None


def fit_design(canonical: Image.Image, views: list[dict], footprint: str) -> tuple[float, list[tuple[Image.Image, list[int]]], list[list[np.ndarray]]]:
    sprites: list[Image.Image] = [canonical.rotate(-angle * 60, resample=Image.Resampling.BICUBIC, expand=True) for angle in range(6)]
    masks_and_safe: list[tuple[list[np.ndarray], np.ndarray]] = [masks_for(view["parts"]) for view in views]
    low: float = 0.0
    high: float = 330.0 / canonical.height
    if footprint == "triangle":
        high = 240.0 / canonical.height
    best: list[tuple[Image.Image, list[int]]] = []
    # One scale for the entire design. Translate whole roofs within the target
    # footprint; never trim eaves, chimneys or wings to force a fit.
    for attempt in range(12):
        scale: float = (low + high) * 0.5
        fitted: list[tuple[Image.Image, list[int]]] = []
        for sprite, (masks, safe) in zip(sprites, masks_and_safe):
            result = fit_view(sprite, scale, safe)
            if result is None:
                break
            fitted.append(result)
        if len(fitted) == 6:
            low = scale
            best = fitted
        else:
            high = scale
    if len(best) != 6:
        raise ValueError("No complete six-angle fit inside the three-hex footprint")
    return low, best, [masks for masks, safe in masks_and_safe]


def main() -> None:
    definitions: list[dict] = json.loads((DOCS / "prompts.json").read_text())["designs"]
    lines: list[dict] = json.loads((ROOT / "docs/art/multihex_buildings/footprints.json").read_text())["3"]
    records: list[dict] = []
    validation: list[dict] = []
    font_path: Path = Path("/usr/share/fonts/TTF/DejaVuSans.ttf")
    if not font_path.exists():
        font_path = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    font: ImageFont.FreeTypeFont = ImageFont.truetype(str(font_path), 15)
    preview: Image.Image = Image.new("RGBA", (6 * 336, len(definitions) * 440), "#303c32")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    for index, definition in enumerate(definitions):
        canonical: Image.Image = isolated_roof(Image.open(OUTPUT / "source" / (definition["id"] + ".png")).convert("RGBA"))
        views: list[dict] = copy.deepcopy(lines)
        if definition["footprint"] == "triangle":
            views = triangle_views()
        scale, fitted, masks = fit_design(canonical, views, definition["footprint"])
        atlas: Image.Image = Image.new("RGBA", (6 * REGION, 3 * REGION))
        for orientation, ((canvas, offset), view, member_masks) in enumerate(zip(fitted, views, masks)):
            original: np.ndarray = np.array(canvas)
            pieces: list[Image.Image] = []
            counts: list[int] = []
            for mask in member_masks:
                pixels: np.ndarray = original.copy()
                pixels[~mask] = 0
                count: int = int(np.count_nonzero(pixels[..., 3] > 26))
                if count < 512:
                    raise ValueError(definition["id"] + " must occupy substantial roof area in all three hexes")
                counts.append(count)
                pieces.append(Image.fromarray(pixels))
            reconstructed: Image.Image = Image.new("RGBA", (REGION, REGION))
            for piece in pieces:
                reconstructed.alpha_composite(piece)
            if np.any(np.asarray(reconstructed) != original):
                raise ValueError("Hex partition changed or removed building pixels")
            pieces[0] = canvas.copy()
            for part, piece in enumerate(pieces):
                atlas.alpha_composite(piece, (orientation * REGION, part * REGION))
            view["image_offset"] = offset
            union: np.ndarray = np.logical_or.reduce(member_masks)
            outside: int = int(np.count_nonzero((original[..., 3] > 0) & ~union))
            if outside != 0:
                raise ValueError("Building artwork extends into a fourth hex")
            validation.append({"id": definition["id"], "angle": orientation * 60, "outside_pixels": outside, "roof_pixels_per_hex": counts, "minimum_inset": INSET, "canvas_cropped_pixels": 0})
            cx, cy = orientation * 336 + 168, index * 440 + 236
            centers: np.ndarray = np.array([part["center"] for part in view["parts"]], dtype=int)
            center: np.ndarray = np.rint(centers.mean(axis=0)).astype(int)
            for hx, hy in centers:
                vertices: list[tuple[int, int]] = [(cx + int(hx - center[0]) + x, cy + int(hy - center[1]) + y) for x, y in [(-64, 0), (-32, -64), (32, -64), (64, 0), (32, 64), (-32, 64), (-64, 0)]]
                draw.polygon(vertices, fill="#3b4d3c", outline="#88a47a", width=1)
            preview.alpha_composite(canvas, (cx - REGION // 2, cy - REGION // 2))
            draw.text((orientation * 336 + 9, index * 440 + 8), definition["label"], fill="#efe5cf", font=font)
            draw.text((orientation * 336 + 9, index * 440 + 28), str(orientation * 60) + " degrees / 3 hexes", fill="#c0d3b9", font=font)
        atlas.save(OUTPUT / (definition["id"] + ".png"))
        records.append({"id": definition["id"], "label": definition["label"], "material": definition["material"], "parent": definition["parent"], "pack": "three_hex_landmarks", "hexes": 3, "footprint": definition["footprint"], "strict_footprint": True, "footprint_inset": INSET, "orientation_method": "rigid clockwise rotation of one generated canonical roof", "region_size": REGION, "texture": "res://assets/tiles/buildings/multihex/three_hex_landmarks/" + definition["id"] + ".png", "scale": scale, "views": views})
        print("Exported", definition["id"], "scale", round(scale, 4), "; outside pixels: 0", flush=True)
    preview.save(DOCS / "preview.png")
    preview.crop((0, 0, preview.width, 3 * 440)).save(DOCS / "wood.png")
    preview.crop((0, 3 * 440, preview.width, 6 * 440)).save(DOCS / "stone.png")
    overview: Image.Image = Image.new("RGBA", (3 * 336, 2 * 440))
    for row in range(6):
        canonical_preview: Image.Image = preview.crop((0, row * 440, 336, (row + 1) * 440))
        overview.alpha_composite(canonical_preview, ((row % 3) * 336, (row // 3) * 440))
    overview.save(DOCS / "overview.png")
    (DOCS / "export.json").write_text(json.dumps({"tile_size": 128, "orientation_count": 6, "buildings": records}, indent=2) + "\n")
    (DOCS / "footprint_validation.json").write_text(json.dumps({"maximum_outside_pixels": 0, "minimum_inset": INSET, "views": validation}, indent=2) + "\n")


if __name__ == "__main__":
    main()
