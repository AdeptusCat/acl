"""Create fixed-camera construction guides for image-generated factory views.

These flat-color guides are generation inputs, never exported game artwork.
One roof model and camera supply every orientation; only world rotation changes.
"""

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT: Path = Path(__file__).resolve().parents[2]
OUTPUT: Path = ROOT / "docs/art/three_hex_landmarks/perspective/textile_camera_revision"
SIZE: int = 1152
ZOOM: int = 3
WALL: float = 3.0
RIDGE: float = 13.0


def draw_guide(angle: int, view: dict) -> Image.Image:
    radians: float = math.radians(angle)
    # The game uses vertically stretched flat-top hexes. This is the exact
    # ground-plane rotation in that grid, shared by the footprint exporter.
    rotation: np.ndarray = np.array([[math.cos(radians), -math.sin(radians) * math.sqrt(3) / 2],
                                    [math.sin(radians) * 2 / math.sqrt(3), math.cos(radians)]])
    image: Image.Image = Image.new("RGB", (SIZE, SIZE), "#26332c")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(image)
    centers: np.ndarray = np.array([part["center"] for part in view["parts"]])
    centroid: np.ndarray = centers.mean(axis=0)
    for cx, cy in centers - centroid:
        draw.polygon([(SIZE / 2 + (cx + x) * ZOOM, SIZE / 2 + (cy + y) * ZOOM) for x, y in [(-64, 0), (-32, -64), (32, -64), (64, 0), (32, 64), (-32, 64)]], fill="#334735", outline="#8ca581", width=3)

    def project(point: tuple[float, float, float]) -> tuple[float, float]:
        x, y = rotation @ np.array(point[:2])
        return SIZE / 2 + x * ZOOM, SIZE / 2 + (y - point[2]) * ZOOM

    faces: list[tuple[float, list, str]] = []

    def face(points: list, color: str) -> None:
        depth: float = sum(float((rotation @ np.array(p[:2]))[1]) + p[2] * 0.15 for p in points) / len(points)
        faces.append((depth, points, color))

    width: float = 18.0
    start: float = -150.0
    length: float = 75.0
    # Front and side masonry walls are short, independent of orientation.
    for x, normal in [(-width, -1.0), (width, 1.0)]:
        if (rotation @ np.array([normal, 0.0]))[1] > 0.001:
            face([(x, -150, 0), (x, 150, 0), (x, 150, WALL), (x, -150, WALL)], "#c4b79a")
    for y, normal in [(-150.0, -1.0), (150.0, 1.0)]:
        if (rotation @ np.array([0.0, normal]))[1] > 0.001:
            top: float = WALL
            if y > 0:
                top = RIDGE
            face([(-width, y, 0), (width, y, 0), (width, y, top), (-width, y, top)], "#b9ad94")
    for bay in range(4):
        north, south = start + bay * length, start + (bay + 1) * length
        face([(-width, north, WALL), (width, north, WALL), (width, south, RIDGE), (-width, south, RIDGE)], "#929ba3")
        # Glazing faces all share one world normal; the reverse views occlude
        # them naturally instead of moving glass to the opposite roof face.
        if (rotation @ np.array([0.0, 1.0]))[1] > 0.001 and bay < 3:
            face([(-width, south, WALL), (width, south, WALL), (width, south, RIDGE), (-width, south, RIDGE)], "#668b97")
        for x, normal in [(-width, -1.0), (width, 1.0)]:
            if (rotation @ np.array([normal, 0.0]))[1] > 0.001:
                face([(x, north, WALL), (x, south, WALL), (x, south, RIDGE)], "#b9ad94")
    for depth, points, color in sorted(faces, key=lambda entry: entry[0]):
        draw.polygon([project(p) for p in points], fill=color, outline="#273235", width=3)
    # The single north-west chimney is a world-vertical cylinder. Its screen
    # vertical never rotates with the roof plan.
    cx, cy = project((-9, -129, 7))
    radius: int = 12
    chimney_top: float = cy - 36
    draw.rectangle((cx - radius, chimney_top, cx + radius, cy), fill="#cfbea0", outline="#343b37", width=2)
    draw.ellipse((cx - radius, chimney_top - 5, cx + radius, chimney_top + 5), fill="#ded0af", outline="#343b37", width=2)
    draw.ellipse((cx - radius + 4, chimney_top - 3, cx + radius - 4, chimney_top + 2), fill="#26332c")
    for cx, cy in centers - centroid:
        px, py = SIZE / 2 + cx * ZOOM, SIZE / 2 + cy * ZOOM
        draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill="#e8c768")
    font: ImageFont.FreeTypeFont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    draw.text((24, 20), str(angle) + " degrees - fixed high camera / four connected roof bays", fill="#eceddd", font=font)
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    views: list[dict] = json.loads((ROOT / "docs/art/multihex_buildings/footprints.json").read_text())["3"]
    for view in views:
        draw_guide(int(view["angle"]), view).save(OUTPUT / (str(view["angle"]) + "_construction.png"))
    reference: Image.Image = Image.open(ROOT / "assets/tiles/buildings/multihex/three_hex_landmarks/source/building_stone_textile_factory_3hex.png").convert("RGBA")
    reference.thumbnail((190, 470))
    for angle in [60, 120, 180, 240, 300]:
        guide: Image.Image = Image.open(OUTPUT / (str(angle) + "_construction.png")).convert("RGBA")
        if angle == 180:
            guide.alpha_composite(reference, (15, 140))
            guide.save(OUTPUT / "180_portrait_target.png")
            continue
        target: Image.Image = Image.new("RGBA", (1536, 1024), "#26332c")
        target.alpha_composite(guide.crop((0, 180, 1152, 1000)), (240, 170))
        target.alpha_composite(reference, (15, 100))
        target.save(OUTPUT / (str(angle) + "_landscape_target.png"))


if __name__ == "__main__":
    main()
