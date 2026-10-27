# Debug map engagement capture

Capture is disabled by default. Enable **Capture logs** in battle settings before reproducing a problem. Enabling it during a battle starts a fresh capture; disabling it flushes and closes the capture. The preference persists across launches. Editor scene inspection does not start capture.

Captures are stored in:

```text
user://debug/engagements/<UTC timestamp>_<unique suffix>/
```

The game prints the absolute session path as `Engagement capture: ...` when capture starts. Each new map game gets a separate directory, including retries. Existing casualty and exit-history saves remain separate.

## Files

| File | Contents |
| --- | --- |
| `metadata.json` | Schema and engine versions, map/scenario identity, battle ID, player team and game mode, debug flags, physics rate/time scale, source-rule hashes, morale state modifiers, rank parameters and the hard leadership/personal-HQ recovery limits. |
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
- Effective and fast/slow stress, incoming/actual-recovery/net rates, available recovery capacity, averaging-window duration, fire pressure, casualty-recovery shock, pin/unpin timers, quiet time since the incoming-fire window expired (`stress.time_without_fire_s`) and leadership modifiers.
- Attention focus, width, quality, capacity, raw directional demand, adjusted required demand (`attention.required`), incoming bearings, overload, switching, surprise, crossfire and flank/surround conditions. Raw demand preserves observation information; required demand contains only received-fire bearings, with shared effort across nearby bearings. `attention.suppression_activity` records received-fire freshness over the local pressure window; bearing awareness can persist longer without maintaining stress.
- Assigned HQ, actual command-link/presence strengths, target, action/order/task IDs, objective and movement targets, visible enemies and their remembered tracks.

Each snapshot also records match-clock/result state, continued-play state, time scale and relevant debug flags. The match result is an event; capture stays open while the result screen is shown and when play continues afterward.

## AI evidence and schema version 2

New captures identify `schema_version: 2` in metadata, map, summaries, events and snapshots. Older recordings are unchanged and retain their original limitations.

Unit `cover` now samples physical protection at the unit's hex center using the same terrain lookup as combat. It no longer reads the unmaintained `current_cover_bonus`. `terrain_defense` retains the gameplay cached value, allowing stale terrain state to be detected. `cover_context.local_terrain` repeats the sampled value explicitly. It does not include directional walls.

`cover_context.lanes` records visible or positively remembered enemies, their observed/remembered hexes, LOS availability, and `local_wall_cover` facing each source. `incoming_target_cover` and `incoming_hindrance` preserve the separate incoming LOS values. Target/shooter cover from a LOS record can include intervening vegetation; it must not be interpreted as local terrain protection. A hedge can protect one bearing while `cover` remains zero.

Each snapshot adds:

- `objectives`: condition identity, side, outcome level, deadline-only flag, hexes, required/held time, secured flags, controlling sides, enemy recapture time, remaining unit requirements and completion state.
- `ai.planners`: main, company subordinate and headquarters planners; missions, per-unit goal/role/position assignments, accepted destinations, reservations, planning progress, reserve reasons and defensive coverage gaps.
- Captured AI contacts with observed/remembered status, confidence, captured hex and last-seen time; delayed aggregate sector pressure is separate. These describe AI knowledge, not proof that every battlefield unit was observed.
- Company formation roles, assigned objectives, reasons and goal tasks. Snapshot position traces omit detailed scoring profiles and alternatives to reduce repeated data.
- Unit movement paths, path indices and remaining waypoints, including exposed assault legs. These are actual movement state; planned paths are recorded separately.

`ai_decision` is emitted at the AI execution entry point after its safety checks. It includes the proposed/selected target, duty, profile/mode, scoring weights and features, current/previous scores, rejection counts, up to four available alternatives, planned path, contact/approach evidence, previous accepted destination, actual movement target and before/after action order IDs. Relevant current/proposed/previous cells retain their eligibility explanations. `candidate_cover_inputs` records the selected hex’s terrain layer and directional wall/hindrance values toward captured contacts and the objective, with the diagnostic snapshot version. This permits checking cover orientation without treating distant vegetation as local protection. Non-finite scores serialize as strings such as `inf` and `-inf`.

`disposition` separates accepted execution from no candidate/executor rejection and explicit blocks: missing company support, another platoon's position claim, unsafe approach, unsafe open HQ position, or retaining the last covering squad. `accepted` means the executor accepted the advice; it does not necessarily issue a new order. Compare the before/after order IDs and movement state. `ai_plan_cancelled` records pending plans discarded by objective/context changes, invalid movement origins or failed validation.

The recorder reads existing decisions and knowledge. It does not run additional tactical searches, select targets, reserve positions or roll random numbers. Alternatives represent the planner's available shortlist, not an exhaustive ranking of every map hex. Rule hashes include AI selection, coordination, execution and recording scripts; metadata also records the baked LOS resource hash.

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
