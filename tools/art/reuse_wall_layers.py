"""Reuse the wall scene without repacking authored maps or changing cell bytes."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://scenes/world/maps/layers/wall_tile_map_layer.tscn"


def migrate(path: Path) -> int:
    text = path.read_text()
    if SCENE in text or '[node name="WallTileMapLayer"' not in text:
        return 0
    lines = text.splitlines(keepends=True)
    output = []
    wall = False
    count = 0
    for line in lines:
        if line.startswith("[node "):
            wall = line.startswith('[node name="WallTileMapLayer"')
            if wall:
                line = line.replace(' type="TileMapLayer"', "").rstrip("\n")
                line = line[:-1] + ' instance=ExtResource("ConnectedWallLayer")]\n'
                count += 1
        if wall and (line.startswith("tile_set = ") or line.startswith("script = ")):
            continue
        output.append(line)
    result = "".join(output)
    first_resource = result.index("[ext_resource ")
    result = result[:first_resource] + '[ext_resource type="PackedScene" path="' + SCENE + '" id="ConnectedWallLayer"]\n' + result[first_resource:]
    result = re.sub(r"load_steps=(\d+)", lambda match: "load_steps=" + str(int(match[1]) + 1), result, count=1)
    # Verify all authored tile arrays, including walls, remain byte-for-byte intact.
    assert re.findall(r"^tile_map_data = .*", result, re.M) == re.findall(r"^tile_map_data = .*", text, re.M)
    path.write_text(result)
    return count


if __name__ == "__main__":
    count = 0
    for path in sorted((ROOT / "scenes").rglob("*.tscn")):
        if path == ROOT / SCENE.removeprefix("res://"):
            continue
        count += migrate(path)
    print(f"Reused the shared wall layer in {count} maps; all authored tile bytes preserved.")
