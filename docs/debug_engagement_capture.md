# Debug map engagement capture

Every map game started from a debug build automatically opens an engagement capture. This uses the same `OS.is_debug_build()` gate as the existing debug controls. Editor scene inspection and release builds do not start captures or create capture directories. There is no extra switch to enable before reproducing a battle.

Captures are stored in:

```text
user://debug/engagements/<UTC timestamp>_<unique suffix>/
```

The game prints the absolute session path as `Engagement capture: ...` when capture starts. Each new map game gets a separate directory, including retries. Existing casualty and exit-history saves remain separate.

## Files

| File | Contents |
| --- | --- |
| `metadata.json` | Schema and engine versions, map/scenario identity, battle ID, player team and game mode, debug flags, physics rate/time scale, source-rule hashes, morale state modifiers and rank parameters. |
| `map.json` | Used cells in ground, building, wall, terrain and road layers, their tile sources/atlas coordinates, custom tile data, tileset references and layer positions. |
| `events.jsonl` | Ordered discrete combat and lifecycle events, with sequence numbers, capture time and physics-frame offsets. |
| `snapshots.jsonl` | Complete per-unit state at startup, every simulated second, results and finalization. |
| `summary.json` | Whether capture closed normally, the close reason, elapsed simulation time, event/sample counts and any match result. |

The entire session directory is the analysis artifact. JSONL files contain one JSON object per line and can be read incrementally without loading a whole match into memory.

## Combat evidence

`unit_registered` saves identity, initial full state and the exported stress, firing and combat-stat settings actually present on that unit. Runtime weapons receive session-local IDs and a `weapon_registered` definition containing their resource path and exported values. This preserves their configuration even after a gunner dies or a weapon is re-crewed.

`shot_committed` records the firing squad, soldier and role, physical weapon ID, rounds, target and target hex, captured origin, distance, cover, projectile delay, rifle-grenade state, magazine/ammunition after expenditure and firing multipliers. It is emitted from the real firing coroutine after ammunition is spent and before its flight timer.

`impact_resolved` records each affected target separately: hit and disable probabilities, hits and rolled casualties, actual resolved terrain defense, shared casualty shock, base suppression, surprise, crossfire and the final fast/slow stress passed to the deferred effect receiver. It records outcomes already rolled by the game and makes no additional rolls.

`incoming_effect_applied` refers back to the exact `impact_resolved` sequence number. It records before/after members and stress, whether damage was disabled, and whether the effect applied, eliminated the target or was ignored. Pending impacts are kept in target delivery order, including simultaneous volleys. If a target is freed first, `unit_removed` lists its undelivered impact IDs.

`stress_gain` records discrete raw inputs, bin values before/after, effective gain, gain scaling and leadership context. Continuous attention gains are aggregated into each unit's `attention_gain_since_sample` rather than generating an event every frame. Raw fast minus raw slow gives the switching contribution; raw slow gives overload input.

Other events include casualties with the soldier/weapon details, roster changes, morale changes, action-state changes, dispatched unit orders, surrender, elimination, map exit, results and session closure.

## State snapshots

Snapshots include both teams and remembered contacts, including units hidden by battlefield presentation. Each unit includes:

- Stable capture ID, formation identity, faction/loadout, hex/world position, cover, activity, movement, surrender, exit, broken and close-combat flags.
- Living roster, casualties, embedded leadership, cohesion/target cohesion, combat effectiveness and recent casualty shock.
- Every soldier's role/rank, weapon ID, ammunition and magazine, grenade state, setup/reload/acquisition readiness and remaining task times, and accuracy/fire-rate multipliers.
- Effective and fast/slow stress, incoming/actual-recovery/net rates, available recovery capacity, averaging-window duration, fire pressure, casualty-recovery shock, pin/unpin timers and leadership modifiers.
- Attention focus, width, quality, capacity, raw directional demand, adjusted required demand (`attention.required`), incoming bearings, overload, switching, surprise, crossfire and flank/surround conditions. Raw demand preserves observation information; adjusted required demand includes passive-contact weighting and shared effort across nearby bearings.
- Assigned HQ, actual command-link/presence strengths, target, action/order/task IDs, objective and movement targets, visible enemies and their remembered tracks.

Each snapshot also records match-clock/result state, continued-play state, time scale and relevant debug flags. The match result is an event; capture stays open while the result screen is shown and when play continues afterward.

## Persistence and limits

Streams flush once per simulated second and at results/closure. Metadata, terrain and summaries use a temporary file followed by rename. A new session starts with `complete: false`; closing or resetting the map, replacing capture, or exiting normally writes a final completed summary and closes streams. A missing final summary or `complete: false` identifies an interrupted/failed capture. A hard process kill can lose the last unflushed interval or leave a partial final JSONL line.

No per-frame history is accumulated in memory. Units are held through weak references. File failures disable capture and issue a warning without stopping the game. Session IDs use `Crypto`, and observation does not consume the gameplay random stream. Capture does not seed or sample that stream.

This is diagnostic telemetry, not a deterministic replay or a package of the game's assets. Resource references and hashes identify the rules available at capture start; source hashes may be unavailable in an exported package. Unit tunables are saved on registration, and ongoing state/ammunition are sampled. Mid-game edits of arbitrary exported tuning values are not recorded as a full configuration history.

## Verification

Run the dedicated regression with isolated user data:

```bash
capture_data="$(mktemp -d)"
env XDG_DATA_HOME="$capture_data/data" XDG_CONFIG_HOME="$capture_data/config" XDG_CACHE_HOME="$capture_data/cache" \
  godot --headless --path . --fixed-fps 60 tests/engagement_capture_regression.tscn
```

Checks cover the disabled-debug policy without file creation, metadata-write failure, unique sessions, incomplete/final manifests, periodic flushing, replacement and owner teardown, gameplay RNG preservation, automatic capture from a real map, full rosters/terrain, actual committed shots and delayed effects, casualties, attention aggregation, morale/orders/results and FIFO correlation for queued and ignored impacts.
