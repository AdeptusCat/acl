# Squad stress balance suite

Run from the project root:

```bash
python3 tests/run_stress_suite.py
```

Use `--godot /path/to/godot` to select the Godot 4.7 executable and `--output /path/to/results` to change the report directory. The default is `/tmp/acl-stress-results`. Each scene runs in a fresh Godot process with temporary XDG user directories, a 120-second timeout and a saved log. A nonzero exit, any Godot `ERROR:`/`SCRIPT ERROR:`, or a missing successful completion summary fails the suite. This catches script aborts even when Godot exits with status zero.

The runner includes squad attention, integrated attention stress, stress balance/UI, stress recovery, stress input integration, command connections, target hit probability, and the weapon/scenario matrix. HQ multipliers and morale thresholds are unchanged by the input correctness fixes.

## Coverage

| Influence | Checks |
| --- | --- |
| Weapon definitions | Discover every `.tres` in `resources/weapons`; use actual accuracy, range, burst count, ammo type and HE suppression in `SquadHitResolver` through `SquadFireController.fire_at`. Includes both factions' rifles, SMGs, MGs, launchers, mortars and rifle grenades. |
| Distance | Point blank, half range, three-quarter range and maximum range, deduplicated for short-range weapons. Longer range must not increase suppression. |
| Defense | Cover 0–5; stronger cover reduces suppression, with the existing mortar cover-one airburst exception. Mortar checks independently vary ordinary terrain cover and actual building tile custom data. |
| Direction | Expected frontal fire, unexpected rear fire, known frontal bearing followed by rear crossfire; sustained single, opposing and three-direction fire. Surprise changes fast stress; crossfire changes both bins. Existing attention tests check expiry, near-aligned bearings, pressure bounds and no duplicate geometry penalty from tactical flags. |
| HQ | Unsupported squads, radio presence, nearby voice/sight plus aura, platoon HQ and company HQ. Presence comes from real `CommandConnectivity` calculations; the existing command scene exercises world connectivity. Nearby aura coefficients use the current default values (0.15 gain bonus, 0.1 rally, 1.05 cohesion). |
| Morale | Fixed normal, pinned and panic sustained scenarios; recovery capacity in every morale state. Existing integrated tests separately exercise morale transitions using final stress. |
| Cohesion and casualties | Poor cohesion, one casualty, casualty plus leader loss, reduced observation capacity after losses, compounded casualty recovery slowdown and expiry. A seeded real-impact test enables casualty stress, verifies the suppression/casualty caps and unchanged casualty rolls, and applies recovery shock. |
| Attention | Real surrounding visible contacts, overload, observer losses, combat cohesion, existing stress, pinned observation penalties and repeated focus switches. |
| Volume and attacker | Normal versus high-frequency volleys; heavy-fire recovery slowdown; stressed attacker accuracy and HE suppression. |
| Integration and boundaries | Incoming scaling, leadership gain reduction, existing-stress resistance, caps, negative input, empty bins, disabled damage, surrender, smoothing expiry, measured net rate and different simulation steps are covered by the existing suites included in the runner. |
| Input correctness | First and repeated pinning use time spent pinned; repinning retains its separate ramp. Simultaneous and successive impacts accumulate into a normalized, fading rounds/second history. Pressure expires consistently at different simulation steps. Combat cohesion reaches recovery at setup and during live updates without compounding aura bonuses. |

## Scenario protocol and report

`stress_scenarios.csv` contains single-impact measurements plus 90 sustained scenarios. A fixed seed (`1234`) keeps casualty rolls reproducible. The impact matrix disables casualty-driven stress to isolate suppression and direction; it still records the casualty rolls. The separate casualty integration test enables the production casualty stress coefficients.

Sustained cases run 30 simulated seconds of fire, followed by 60 seconds with all attention input stopped. They use a 0.25-second simulation step and one configured weapon burst every two seconds; the high-volume profile fires every 0.5 seconds. Bearings alternate between the configured directions. Each impact waits for the production deferred effect callback before sampling. Nodes remain outside the scene tree so automatic processing cannot add extra simulation ticks.

These are controlled stress scenarios, not full squad DPS or ammunition simulations. They omit acquisition, setup, reload, projectile flight time, crew allocation, ammo exhaustion, movement, changing visibility and AI orders. Weapon differences enter through the real impact resolver and configured burst size. Impact casualties are recorded but do not remove soldiers during sustained suppression comparisons. The casualty and leader-loss profiles start with one loss and apply its recovery shock. Sustained morale is held fixed to separate stress accumulation from random morale transitions. Derived flank/surround conditions are tested separately against real contacts.

CSV columns include the scenario inputs, seed, step, volley size and interval, raw fast/slow impact gain, stress at the end of firing, peak stress, first pin/panic threshold crossing, stress after recovery, and time to fall below the normal-from-cautious threshold. Threshold crossings are stress measurements, not times when the fixed morale state changes. `-1` means a timing was not reached within the simulation or a metric does not apply. For impact rows, `stress_at_30s` holds immediate effective stress; `phase` identifies those rows. CSV values are measurements, not golden snapshots that would prevent intentional tuning.

## Initial balance observations

Godot 4.7.2, seed 1234, cover 2, half weapon range, opposing directions, normal morale, default two-second volley interval:

| Weapon | Stress after 30 s, unsupported | Stress after 30 s, nearby HQ |
| --- | ---: | ---: |
| M1 Garand | 9.32 | 7.81 |
| MG34 | 34.74 | 31.00 |
| M2 60 mm mortar | 99.08 | 99.03 |

The mortar reaches the cap under this controlled schedule; HQ gain protection has little room to separate the end values once saturated. Use threshold times and recovery columns alongside end stress. Radio presence alone does not improve normal-state recovery because normal morale already provides the full base recovery capacity. It improves recovery for impaired morale states.

These measurements include the fire-pressure correction. Each impact supplies a round count. A normalized triangular history over `under_fire_window_s` (two seconds by default) adds overlapping impacts and fades each contribution linearly to zero. Its integral equals the submitted rounds, so the resulting pressure has rounds/second units. Empty, negative and nonfinite inputs do not refresh fire pressure. The stress controller ages this history using simulation time.

Combat stats now publish base cohesion to the stress controller during unit setup and after cohesion updates. Leadership cohesion remains a separate multiplier. The controlled poor-cohesion scenarios still set the input directly; the stress input regression separately verifies the live stats-to-recovery connection. Unpin recovery now ramps using `_since_pinned`, independently of `_repin_since_unpin`.

## Existing tuning gaps exposed by inspection

Several exported values are not read by the active stress path. Changing them currently cannot balance the measured results:

- `SquadFireController`: `stress_scale`, `stress_slow_per_round`, `weapon_stress_mult`, `stress_resilience`, `stress_kill_fast_first`, `stress_kill_ratio_bonus`, and the legacy stress-cover curve parameters. The active resolver uses `cover_multiplier_exp` instead.
- `StressController`: the fast/slow half-lives and weights belong to commented-out decay code. Effective stress uses equal bin weights and active recovery is linear. Legacy panic fast-decay/freeze and heavy-fire freeze settings are also inactive.
- `get_rally_bonus()` exposes accumulated aura rally bonuses, but the active `_apply_recovery_bias()` does not consume them. It does consume HQ rally and situational recovery multipliers.

Defend orders and close-combat defense preparedness do not directly multiply ranged stress. Defense enters through actual cover, morale and attention geometry. These gaps are documented without adding assertions that would require the unused settings to remain ineffective. Passing the suite establishes integration and relative behavior; it does not establish desired gameplay balance.
