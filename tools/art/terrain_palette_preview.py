"""Render the campaign's RGB palette materials without modifying source artwork."""

from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT: Path = Path(__file__).resolve().parents[2]
PALETTES: dict = json.loads((ROOT / "assets/palettes/terrain_palettes.json").read_text())["families"]


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    factor: np.ndarray = np.clip((value - edge0) / (edge1 - edge0), 0, 1)
    return factor * factor * (3 - 2 * factor)


def color(hex_value: str) -> np.ndarray:
    return np.array([int(hex_value[index:index + 2], 16) / 255 for index in [1, 3, 5]], dtype=np.float32)


def mix(first: np.ndarray, second: np.ndarray, amount: np.ndarray) -> np.ndarray:
    amount = amount[..., None]
    return first * (1 - amount) + second * amount


def ramp(brightness: np.ndarray, family: str) -> np.ndarray:
    palette: dict = PALETTES[family]
    levels: list[float] = palette["levels"]
    result: np.ndarray = np.broadcast_to(color(palette["colors"][0]), (*brightness.shape, 3)).copy()
    for index in range(1, 5):
        amount: np.ndarray = np.clip((brightness - levels[index - 1]) / (levels[index] - levels[index - 1]), 0, 1)
        result = mix(result, color(palette["colors"][index]), amount)
    return result


def family_for_cell(layer: str, cell: dict) -> str:
    if cell["texture"].startswith(("res://assets/tiles/buildings/rotated/", "res://assets/tiles/buildings/multihex/")):
        return ""
    family: str = cell.get("art_family", "")
    if family == "crops":
        return "green_crops"
    if family:
        return family
    if layer == "GroundTileMapLayer":
        return "open_ground"
    path: str = cell["texture"]
    for needle, family in [("bridge", "bridge"), ("river", "water"), ("road", "roads"),
                           ("building_stone", "stone"), ("building_wood", "timber"),
                           ("hedge", "hedges"), ("wall", "stone"), ("stubble", "stubble"),
                           ("ploughed", "ploughed"), ("green_rows", "green_crops"), ("wheat", "wheat")]:
        if needle in path:
            return family
    return ""


def apply_palette(image: Image.Image, family: str) -> Image.Image:
    if not family:
        return image
    primary: str = family
    if family == "bridge":
        primary = "timber"
    pixels: np.ndarray = np.array(image.convert("RGBA"))
    original: np.ndarray = pixels[:, :, :3].astype(np.float32) / 255
    brightness: np.ndarray = original @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    result: np.ndarray = ramp(brightness, primary)
    red, green, blue = original[:, :, 0], original[:, :, 1], original[:, :, 2]
    warm: np.ndarray = smoothstep(.02, .09, red - green)
    kind: int = PALETTES[primary]["mode"]
    if family == "bridge":
        kind = 7
    if kind == 1:
        result = mix(color(PALETTES["grid_fog"]["colors"][0]), result, smoothstep(.17, .28, brightness))
    elif kind == 2:
        result = mix(result, ramp(brightness, "timber"), warm)
    elif kind == 3:
        accents: list[np.ndarray] = [color(value) for value in PALETTES["fruit_blossom"]["colors"]]
        ratio: np.ndarray = green / np.maximum(red, .001)
        apple: np.ndarray = warm * (1 - smoothstep(.45, .65, ratio))
        pear: np.ndarray = warm * smoothstep(.45, .65, ratio)
        flower: np.ndarray = smoothstep(.48, .72, original.min(axis=2))
        result = mix(result, mix(accents[0], accents[1], np.clip((brightness - .12) / .34, 0, 1)), apple)
        result = mix(result, mix(accents[2], accents[3], np.clip((brightness - .25) / .45, 0, 1)), pear)
        result = mix(result, accents[4], flower)
    elif kind == 4:
        result = mix(result, ramp(brightness, "ploughed"), warm)
    elif kind in [5, 6]:
        cool: np.ndarray = smoothstep(0, .06, blue - red)
        clay: np.ndarray = warm.copy()
        if kind == 6:
            clay *= smoothstep(.02, .08, red - 2 * green + blue)
        result = mix(result, ramp(brightness, "clay_roofs"), clay)
        result = mix(result, ramp(brightness, "slate_roofs"), cool)
    elif kind == 7:
        result = mix(result, ramp(brightness, "water"), smoothstep(.01, .06, blue - red))
    pixels[:, :, :3] = np.clip(np.rint(result * 255), 0, 255).astype(np.uint8)
    return Image.fromarray(pixels)
