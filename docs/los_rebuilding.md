# LOS rebuilding

Runtime rebuilds and the campaign/standalone authoring tools share one bake
path. It preserves every directed shooter-to-target result, including cover,
concealment, hindrance, hex-spine checks, and the original first blocking pixel.
It does not assume that a reversed ray has the same cover.

## Calculation

`resources/los/los_bake_cache.gd` snapshots the map for one rebuild:

- Sprite bounds, atlas regions, flips, transposition and multihex ownership.
- One binary alpha mask per texture, using the existing alpha threshold of 0.1.
- Hex-neighbor rings, retaining the original candidate order and excluding empty
  cells from sprite checks.
- Hex-center positions, cover/concealment and directional wall metadata.

The alpha masks use Godot's
[BitMap API](https://docs.godotengine.org/en/stable/classes/class_bitmap.html#class-bitmap-method-create-from-image-alpha).
Sampling retains the original one-pixel interval and phase. Temporary caches
are released after the rebuild. Live combat and preview queries continue to
read the current layers.

`LOSHelper.begin_los_bake()` prepares a snapshot;
`bake_los_origin(cell)` calculates its complete visibility row;
`end_los_bake()` releases it. `prebake_los()` uses this path synchronously.
Campaign authoring yields between columns through the same row calculator.

## Reuse and invalidation

Automatically rebuilt tables are saved in `user://los_cache/`, with one file
per map identity. A fingerprint verifies the grid, tile geometry, vegetation
rules, wall directions, cover, atlas transforms, actual texture pixels, sample
spacing and cache version before reuse. A changed fingerprint replaces the
previous cached table. Project map scenes and authored LOS resources are not
written by runtime cache updates.

The loader validates the full input fingerprint for every authored LOS file,
including vegetation and artwork as well as buildings and walls. Legacy files
without that fingerprint cannot certify the current map: they rebuild once or
reuse a compatible runtime cache. This also detects terrain-only edits on older
campaign maps such as Roadblock. The rebuilt fingerprint is retained in memory
and in the runtime cache; the authored resource is not overwritten. Increment
`LosBakeCache.VERSION` when changing LOS rules or the meaning of cached results.

## Validation and timing

Measured in Godot 4.7.2 headless on the same machine and map snapshots:

| Map | Original full calculation | Optimized full calculation | Speedup |
| --- | ---: | ---: | ---: |
| Quiet Approach | 7.17 s | 3.96 s | 1.81× |
| Battle for Alderbrook | 72.34 s | 40.73 s | 1.78× |

All 243,996 directed hex pairs matched the frozen original implementation, as
did 4,000 additional offset rays. A separate isolated run saved the full final
map in 33.60 s and reloaded it from disk in 0.36 s with zero recalculated
origins. Timings depend on the machine and competing work; the comparison does
not reduce map size, sight range or precision.

The actual authoring builder also saved an identical 25,440-pair Quiet Approach
table to an isolated test file. No campaign maps or project LOS files were
regenerated for this optimization.

Run `tests/los_rebuild_regression.tscn` to compare optimized and live rays and
exercise disk reuse, changed vegetation, replaced artwork and incompatible
cache fingerprints. The pixel-terrain, connected-wall and multihex-placement
regressions cover the existing gameplay behavior.
