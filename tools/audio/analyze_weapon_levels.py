"""Measure authored weapon playback levels with FFmpeg; never modify audio assets.

Run from the project root:
    python3 tools/audio/analyze_weapon_levels.py --output /tmp/weapon-levels.csv --check
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
from functools import lru_cache
import math
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SHOT_TARGET = -20.0
TAIL_TARGET = -24.0
PEAK_CEILING = -3.0


def properties(path: Path) -> dict[str, str]:
    return dict(re.findall(r"^(\w+) = (.+)$", path.read_text(), re.MULTILINE))


def streams(path: Path) -> dict[str, str]:
    return {identifier: asset for asset, identifier in re.findall(
        r'\[ext_resource type="AudioStream"[^\n]*path="(res://[^"\n]+)" id="([^"\n]+)"\]',
        path.read_text())}


def events() -> list[dict[str, str | float]]:
    defaults = dict(re.findall(
        r"@export var (\w+): float = (-?[\d.]+)",
        (ROOT / "resources/weapons/weapon_spec.gd").read_text()))
    audio_scene = ROOT / "scenes/game/audio/weapon_audio.tscn"
    scene_properties = properties(audio_scene)
    scene_streams = streams(audio_scene)

    def resolve(value: str, assets: dict[str, str]) -> str:
        return assets[re.fullmatch(r'ExtResource\("([^"\n]+)"\)', value)[1]]

    fallback_shot = resolve(scene_properties["snd_shot_default"], scene_streams)
    fallback_loop = resolve(scene_properties["snd_mg_loop_default"], scene_streams)
    fallback_decay = resolve(scene_properties["snd_mg_loop_decay_default"], scene_streams)
    result = []
    for path in sorted((ROOT / "resources/weapons").glob("*.tres")):
        values = properties(path)
        assets = streams(path)

        def add(role: str, sound: str, volume: str, fallback: str = "") -> None:
            asset = fallback
            if sound in values:
                asset = resolve(values[sound], assets)
            if asset:
                result.append({"weapon": path.name, "role": role, "asset": asset,
                               "gain_db": float(values.get(volume, defaults[volume]))})

        if values.get("fire_mode") == "1":
            add("fire", "snd_mg_loop", "volume_db", fallback_loop)
            add("tail", "snd_mg_loop_decay", "decay_volume_db", fallback_decay)
        elif values.get("family") != "6" or "snd_shot" in values:
            # Offboard artillery only emits impact audio.
            add("fire", "snd_shot", "volume_db", fallback_shot)
        add("impact", "snd_hit", "hit_volume_db")
        add("grenade_fire", "riflegrenade_shot", "riflegrenade_shot_volume_db")
        add("grenade_impact", "riflegrenade_hit", "riflegrenade_hit_volume_db")
    return result


@lru_cache(maxsize=None)
def measure(asset: str, gain_db: float = 0.0) -> tuple[float, float]:
    path = ROOT / asset.removeprefix("res://")
    loop = "loop=true" in Path(str(path) + ".import").read_text()
    command = ["ffmpeg", "-hide_banner", "-nostats", "-nostdin", "-threads", "1"]
    if loop:
        command += ["-stream_loop", "-1"]
    filters = [f"volume={gain_db}dB", "apad=whole_dur=4"]
    if loop:
        filters.append("atrim=duration=4")
    filters.append("ebur128=peak=true:dualmono=true")
    command += ["-i", str(path), "-af", ",".join(filters), "-f", "null", "-"]
    output = subprocess.run(command, capture_output=True, text=True, check=True,
                            timeout=30).stderr
    momentary = [float(value) for value in re.findall(r"\bM:\s*(-?[\d.]+)", output)]
    peak = re.findall(r"Peak:\s*(-?[\d.]+) dBFS", output)
    if not momentary or not peak:
        raise ValueError(f"Cannot measure {asset}")
    measured = max(momentary), float(peak[-1])
    if not all(math.isfinite(value) for value in measured) or measured[0] < -70:
        raise ValueError(f"Invalid/silent audio: {asset}")
    return measured


def analyze(event: dict[str, str | float]) -> dict[str, str | float]:
    raw_loudness, _ = measure(str(event["asset"]))
    # Measure decoded audio with its actual playback gain, including true peaks.
    loudness, peak = measure(str(event["asset"]), float(event["gain_db"]))
    return {**event, "source_max_m_lufs": raw_loudness,
            "playback_max_m_lufs": loudness, "playback_true_peak_dbfs": peak}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/acl-weapon-levels.csv"))
    parser.add_argument("--check", action="store_true",
                        help="Require loudness within 1 LU of target and true peaks below -3 dBFS")
    args = parser.parse_args()
    if shutil.which("ffmpeg") is None:
        parser.error("ffmpeg is required")
    with ThreadPoolExecutor(max_workers=4) as executor:
        rows = list(executor.map(analyze, events()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    failures = 0
    for row in rows:
        target = SHOT_TARGET
        if row["role"] == "tail":
            target = TAIL_TARGET
        if abs(float(row["playback_max_m_lufs"]) - target) > 1.0 or float(row["playback_true_peak_dbfs"]) > PEAK_CEILING:
            failures += 1
            print(f"Outside target: {row['weapon']} {row['role']}: {row['playback_max_m_lufs']} LUFS, {row['playback_true_peak_dbfs']} dBTP")
    firing = [float(row["playback_max_m_lufs"]) for row in rows if row["role"] == "fire"]
    print(f"Analyzed {len(rows)} playback events across {len({row['weapon'] for row in rows})} weapons")
    print(f"Firing loudness spread: {max(firing) - min(firing):.1f} LU; outside targets: {failures}")
    print(f"Report: {args.output}")
    return int(args.check and failures > 0)


if __name__ == "__main__":
    raise SystemExit(main())
