"""Fit independently rendered landmark views without rotating or clipping art."""

import copy
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from export_asl_buildings import triangle_views
from export_multihex_buildings import mass_center
from export_three_hex_landmarks import REGION, isolated_roof, masks_for

ROOT: Path = Path(__file__).resolve().parents[2]
DOCS: Path = ROOT / "docs/art/three_hex_landmarks/perspective"
OUTPUT: Path = ROOT / "assets/tiles/buildings/multihex/three_hex_landmarks/perspective"
INSET: int = 1
CENTER_ALPHA: int = 128


def center_alpha(canvas: Image.Image, parts: list[dict]) -> list[int]:
    """Require solid artwork on all four texels around every exact hex center."""
    alpha: np.ndarray = np.asarray(canvas.getchannel("A"))
    return [int(alpha[REGION // 2 + part["texture_origin"][1] - 1:REGION // 2 + part["texture_origin"][1] + 1,
                      REGION // 2 + part["texture_origin"][0] - 1:REGION // 2 + part["texture_origin"][0] + 1].min()) for part in parts]


def world_length(sprite: Image.Image, angle: int) -> float:
    """Measure the long-axis extent after undoing the hex ground projection."""
    yy, xx = np.nonzero(np.asarray(sprite.getchannel("A")) > 0)
    radians: float = math.radians(angle)
    x_weight: float = -math.sin(radians) * 2 / math.sqrt(3)
    y_weight: float = math.cos(radians)
    projected: np.ndarray = x_weight * xx + y_weight * yy
    return float(np.ptp(projected) + abs(x_weight) + abs(y_weight))


def fit_view(sprite: Image.Image, parts: list[dict], angle: int = 0, maximum_world_length: float | None = None) -> tuple[Image.Image, list[np.ndarray], dict]:
    masks, _ = masks_for(parts)
    union: np.ndarray = np.logical_or.reduce(masks)
    padded_union: np.ndarray = np.pad(union, INSET, constant_values=False)
    inset: Image.Image = Image.fromarray(padded_union.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(INSET * 2 + 1))
    safe: np.ndarray = np.asarray(inset)[INSET:-INSET, INSET:-INSET] > 0
    safe_fft: np.ndarray = np.fft.rfft2(safe.astype(float))
    centers: np.ndarray = np.array([part["texture_origin"] for part in parts]) + REGION // 2
    minimum_extent: int = int(max(np.ptp(centers[:, 0]), np.ptp(centers[:, 1]))) + 4
    # Center coverage creates a minimum size as well as a maximum. A binary
    # search from zero is invalid: tiny roofs fit the boundary but miss centers.
    # Search downward and select the largest complete, center-covering view.
    maximum_extent: int = REGION - INSET * 2
    if maximum_world_length is not None:
        maximum_extent = min(maximum_extent, math.floor(max(sprite.size) * maximum_world_length / world_length(sprite, angle)))
    for extent in range(maximum_extent, minimum_extent - 1, -1):
        scale: float = extent / max(sprite.size)
        scaled: Image.Image = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.Resampling.LANCZOS)
        alpha: np.ndarray = np.asarray(scaled.getchannel("A"))
        if maximum_world_length is not None and world_length(scaled, angle) > maximum_world_length + 0.5:
            continue
        solid: np.ndarray = alpha > 0
        padded: np.ndarray = np.zeros((REGION, REGION), dtype=float)
        padded[:scaled.height, :scaled.width] = solid
        # Correlate complete nonzero-alpha silhouettes against the safe union.
        # Only non-wrapping placements inside the atlas canvas are considered.
        overlap: np.ndarray = np.fft.irfft2(safe_fft * np.conj(np.fft.rfft2(padded)), s=(REGION, REGION))
        valid: np.ndarray = np.rint(overlap[:REGION - scaled.height + 1, :REGION - scaled.width + 1]).astype(int) == int(solid.sum())
        if not valid.any():
            continue
        py, px = np.indices(valid.shape)
        for cx, cy in centers:
            for ox, oy in [(-1, -1), (0, -1), (-1, 0), (0, 0)]:
                sx, sy = cx - px + ox, cy - py + oy
                valid &= (sx >= 0) & (sy >= 0) & (sx < scaled.width) & (sy < scaled.height)
                valid &= alpha[np.clip(sy, 0, scaled.height - 1), np.clip(sx, 0, scaled.width - 1)] >= CENTER_ALPHA
        yy, xx = np.nonzero(valid)
        if not len(xx):
            continue
        cx, cy = mass_center(scaled)
        closest: int = int(np.argmin((xx + cx - REGION / 2) ** 2 + (yy + cy - REGION / 2) ** 2))
        x, y = int(xx[closest]), int(yy[closest])
        canvas: Image.Image = Image.new("RGBA", (REGION, REGION))
        canvas.alpha_composite(scaled, (x, y))
        pixels: np.ndarray = np.asarray(canvas)
        if np.any((pixels[..., 3] > 0) & ~safe):
            raise ValueError("A fitted view crosses the inset footprint")
        if np.count_nonzero(pixels[..., 3]) != int(solid.sum()):
            raise ValueError("A fitted view cropped original building pixels")
        coverage: list[int] = center_alpha(canvas, parts)
        if min(coverage) < CENTER_ALPHA:
            raise ValueError("A fitted view misses an occupied hex center")
        return canvas, masks, {"scale": scale, "image_position": [x, y], "center_alpha": coverage}
    raise ValueError("The generated view cannot cover every center inside its three hexes; regenerate the view")


def main() -> None:
    definitions: list[dict] = json.loads((DOCS.parent / "prompts.json").read_text())["designs"]
    source_records: dict = json.loads((DOCS / "generation.json").read_text())
    sources: dict[str, dict] = {entry["id"]: entry for entry in source_records["designs"]}
    if set(sources) != {definition["id"] for definition in definitions}:
        raise ValueError("Every building needs a recorded generation source")
    lines: list[dict] = json.loads((ROOT / "docs/art/multihex_buildings/footprints.json").read_text())["3"]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    validation: list[dict] = []
    preview: Image.Image = Image.new("RGBA", (6 * 336, 6 * 440), "#303c32")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(preview)
    font: ImageFont.FreeTypeFont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    for index, definition in enumerate(definitions):
        view_sources: dict[int, Path] = {int(view["angle"]): ROOT / view["saved_source"] for view in sources[definition["id"]]["views"]}
        if set(view_sources) != set(range(0, 360, 60)):
            raise ValueError(definition["id"] + " needs exactly six recorded source views")
        sprites: list[Image.Image] = [isolated_roof(Image.open(view_sources[angle * 60]).convert("RGBA")) for angle in range(6)]
        views: list[dict] = copy.deepcopy(lines)
        if definition["footprint"] == "triangle":
            views = triangle_views()
        atlas: Image.Image = Image.new("RGBA", (6 * REGION, 3 * REGION))
        reference_length: float | None = None
        match_zero_scale: bool = sources[definition["id"]].get("world_size_reference_angle") == 0
        for orientation, (sprite, view) in enumerate(zip(sprites, views)):
            try:
                canvas, member_masks, placement = fit_view(sprite, view["parts"], orientation * 60, reference_length)
            except ValueError as error:
                raise ValueError(definition["id"] + " / " + str(orientation * 60) + " degrees: " + str(error)) from error
            view.update(placement)
            if match_zero_scale:
                if orientation == 0:
                    reference_length = world_length(canvas, 0)
                view["world_length"] = world_length(canvas, orientation * 60)
            view["source_image"] = str(view_sources[orientation * 60].relative_to(ROOT))
            original: np.ndarray = np.array(canvas)
            pieces: list[Image.Image] = []
            counts: list[int] = []
            for mask in member_masks:
                pixels: np.ndarray = original.copy()
                pixels[~mask] = 0
                count: int = int(np.count_nonzero(pixels[..., 3] > 26))
                if count < 512:
                    raise ValueError("Every occupied hex needs substantial building artwork")
                counts.append(count)
                pieces.append(Image.fromarray(pixels))
            reconstructed: Image.Image = Image.new("RGBA", (REGION, REGION))
            for piece in pieces:
                reconstructed.alpha_composite(piece)
            if np.any(np.asarray(reconstructed) != original):
                raise ValueError("Hex partition changed building pixels")
            pieces[0] = canvas.copy()
            sprite_directory: Path = OUTPUT / "sprites" / definition["id"]
            sprite_directory.mkdir(parents=True, exist_ok=True)
            canvas.save(sprite_directory / (str(orientation * 60) + ".png"))
            for part, piece in enumerate(pieces):
                atlas.alpha_composite(piece, (orientation * REGION, part * REGION))
            validation.append({"id": definition["id"], "angle": orientation * 60, "outside_pixels": 0, "canvas_cropped_pixels": 0, "roof_pixels_per_hex": counts, "center_alpha": placement["center_alpha"], "minimum_inset": INSET})
            cx, cy = orientation * 336 + 168, index * 440 + 236
            for part in view["parts"]:
                hx, hy = part["texture_origin"]
                vertices: list[tuple[int, int]] = [(cx + hx + x, cy + hy + y) for x, y in [(-64, 0), (-32, -64), (32, -64), (64, 0), (32, 64), (-32, 64)]]
                draw.polygon(vertices, fill="#3b4d3c", outline="#88a47a", width=1)
            preview.alpha_composite(canvas, (cx - REGION // 2, cy - REGION // 2))
            for part in view["parts"]:
                hx, hy = part["texture_origin"]
                draw.ellipse((cx + hx - 2, cy + hy - 2, cx + hx + 2, cy + hy + 2), fill="#f5d273")
            draw.text((orientation * 336 + 9, index * 440 + 8), definition["label"], fill="#efe5cf", font=font)
            draw.text((orientation * 336 + 9, index * 440 + 28), str(orientation * 60) + " degrees / 3 hexes", fill="#c0d3b9", font=font)
            print("Fitted", definition["id"], orientation * 60, "center alpha", placement["center_alpha"], flush=True)
        atlas.save(OUTPUT / (definition["id"] + ".png"))
        records.append({"id": definition["id"], "label": definition["label"], "material": definition["material"], "parent": definition["parent"], "pack": "three_hex_landmarks_perspective", "hexes": 3, "footprint": definition["footprint"], "strict_footprint": True, "footprint_inset": INSET, "orientation_method": "independently generated world orientations under a fixed camera", "region_size": REGION, "texture": "res://assets/tiles/buildings/multihex/three_hex_landmarks/perspective/" + definition["id"] + ".png", "views": views})
    preview.save(DOCS / "preview.png")
    preview.crop((0, 0, preview.width, 3 * 440)).save(DOCS / "wood.png")
    preview.crop((0, 3 * 440, preview.width, 6 * 440)).save(DOCS / "stone.png")
    (DOCS / "export.json").write_text(json.dumps({"tile_size": 128, "orientation_count": 6, "buildings": records}, indent=2) + "\n")
    (DOCS / "footprint_validation.json").write_text(json.dumps({"maximum_outside_pixels": 0, "minimum_inset": INSET, "minimum_center_alpha": CENTER_ALPHA, "views": validation}, indent=2) + "\n")


if __name__ == "__main__":
    main()
