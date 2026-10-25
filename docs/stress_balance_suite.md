# Squad stress balance suite

Run from the project root:

```bash
python3 tests/run_stress_suite.py
```

Use `--godot /path/to/godot` to select the Godot 4.7 executable and `--output /path/to/results` to change the report directory. The default is `/tmp/acl-stress-results`. Each scene runs in a fresh Godot process with temporary XDG user directories and a saved log. Timeouts are 120 seconds, or 600 seconds for whole-squad exchanges. A nonzero exit, any Godot `ERROR:`/`SCRIPT ERROR:`, or a missing successful completion summary fails the suite. This catches script aborts even when Godot exits with status zero.

The twelve-suite runner includes squad attention, integrated attention stress, passive-contact and clustered-bearing overload, high-stress pinning recovery after fire, stress balance/UI, stress recovery, stress input integration, stress resilience with live attention and morale, command connections, target hit probability, the weapon/scenario matrix, and [whole-squad reciprocal fire exchanges](squad_fire_exchange_tests.md). The exchange suite distinguishes mechanical failures from provisional balance alerts; use `--strict-balance` to fail on those alerts. Morale thresholds and directional attention costs are unchanged by the recovery rebalance.

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
| Resilience balance | Actual squad/platoon/company rank parameters, live visible contacts and bearing memories, and stochastic morale over eight paired seeds. One frontal threat must not pin an intact isolated squad under intermittent fire. Unsupported squads must recover below caution within 90 seconds after opposing threats stop; HQ must improve recovery. Concentrated three-direction fire must still overwhelm company-supported squads. |

## Scenario protocol and report

`stress_scenarios.csv` contains single-impact measurements plus 90 sustained scenarios. A fixed seed (`1234`) keeps casualty rolls reproducible. The impact matrix disables casualty-driven stress to isolate suppression and direction; it still records the casualty rolls. The separate casualty integration test enables the production casualty stress coefficients.

Sustained cases run 30 simulated seconds of fire, followed by 60 seconds with all attention input stopped. They use a 0.25-second simulation step and one configured weapon burst every two seconds; the high-volume profile fires every 0.5 seconds. Bearings alternate between the configured directions. Each impact waits for the production deferred effect callback before sampling. Nodes remain outside the scene tree so automatic processing cannot add extra simulation ticks.

These are controlled stress scenarios, not full squad DPS or ammunition simulations. They omit acquisition, setup, reload, projectile flight time, crew allocation, ammo exhaustion, movement, changing visibility and AI orders. Weapon differences enter through the real impact resolver and configured burst size. Impact casualties are recorded but do not remove soldiers during sustained suppression comparisons. The casualty and leader-loss profiles start with one loss and apply its recovery shock. Sustained morale is held fixed to separate stress accumulation from random morale transitions. Derived flank/surround conditions are tested separately against real contacts.

CSV columns include the scenario inputs, seed, step, volley size and interval, raw fast/slow impact gain, stress at the end of firing, peak stress, first pin/panic threshold crossing, stress after recovery, and time to fall below the normal-from-cautious threshold. Threshold crossings are stress measurements, not times when the fixed morale state changes. `-1` means a timing was not reached within the simulation or a metric does not apply. For impact rows, `stress_at_30s` holds immediate effective stress; `phase` identifies those rows. CSV values are measurements, not golden snapshots that would prevent intentional tuning.

## Recovery rebalance

Attention overload and switching retain their original costs. The rebalance strengthens the recovery available to every squad, gives command presence useful protection before pinning, and limits how far HQ can bypass morale impairment.

| Mechanic | Before | After |
| --- | ---: | ---: |
| Normal inherent recovery, stress/second | 1.00 | 1.50 |
| Cautious inherent recovery | 0.80 | 1.275 |
| Pinned inherent recovery | 0.35 | 0.825 |
| Panic inherent recovery | 0.10 | 0.45 |
| Light/heavy fire recovery multipliers | 0.40 / 0.10 | 0.65 / 0.25 |
| Full command presence | Restores the normal recovery factor | Adds 50% to the squad's morale-adjusted recovery |
| Incoming command protection | None beyond rank aura | Up to 15%, proportional to presence |
| Minimum incoming gain multiplier | 0.40 | 0.75 |

Recovery rates in the table assume full cohesion and no fire, casualties, aura or HQ-unit bonus. Rank aura gain protection and command presence multiply, then share the 25% cap. Recovery aura cohesion still uses the strongest source rather than stacking. Combat-ineffective squads retain limited command-assisted recovery. The HQ-unit panic floor is reduced to 0.6 before base-rate scaling, preventing the former extreme disparity with unsupported panic recovery.

## Measured results

Godot 4.7.2, seed 1234, cover 2, half weapon range, opposing directions, normal morale, default two-second volley interval:

| Weapon | Unsupported before | Unsupported after | Nearby HQ before | Nearby HQ after |
| --- | ---: | ---: | ---: | ---: |
| M1 Garand | 9.32 | 1.54 | 7.81 | 0.00 |
| MG34 | 34.74 | 25.00 | 31.00 | 9.80 |
| M2 60 mm mortar | 99.08 | 97.97 | 99.03 | 96.80 |

The mortar still approaches the cap under this controlled schedule. Use threshold times and recovery columns alongside end stress. Radio presence now improves gain protection and recovery even in normal morale, with a smaller benefit than nearby voice/sight presence. Zero end stress in the light supported rifle case means recovery offsets that controlled input; it does not imply immunity to individual hits or heavier fire.

The separate resilience regression runs eight paired seeds with live two-direction attention, incoming bearings and stochastic morale. Isolated squads retain their squad-leader aura; supported squads use actual platoon-leader parameters. Mean stress at 30 seconds is 86.87 isolated versus 63.26 supported. Mean time below the caution recovery threshold after pressure stops is 59.59 versus 21.44 seconds. This is a severe opposing-threat case with ongoing overload, distinct from the fixed-morale weapon matrix. One frontal threat stays below caution without pinning, while concentrated three-direction fire still exceeds 65 stress and pins a company-supported squad.

These live-attention checks use controlled suppression inputs rather than a complete weapon/loadout simulation. They keep squad size and cohesion intact, omit projectile travel, movement and casualty rolls, and do not exercise proximity routing. They validate bounded support and autonomous recovery, rather than claiming a full-match break probability.

Validation after the rebalance: all nine stress suites pass, with 1,370 CSV cases including 90 sustained scenarios. All 312 project scripts pass parsing and annotation checks. Unit-roster and active-match smoke assertions pass. The active-match test still reports the previously observed shutdown leaks (174 ObjectDB instances and one resource); no simulation script errors occurred.

These measurements include the fire-pressure correction. Each impact supplies a round count. A normalized triangular history over `under_fire_window_s` (two seconds by default) adds overlapping impacts and fades each contribution linearly to zero. Its integral equals the submitted rounds, so the resulting pressure has rounds/second units. Empty, negative and nonfinite inputs do not refresh fire pressure. The stress controller ages this history using simulation time.

Combat stats now publish base cohesion to the stress controller during unit setup and after cohesion updates. Leadership cohesion remains a separate multiplier. The controlled poor-cohesion scenarios still set the input directly; the stress input regression separately verifies the live stats-to-recovery connection. Unpin recovery now ramps using `_since_pinned`, independently of `_repin_since_unpin`.

## Existing tuning gaps exposed by inspection

Several exported values are not read by the active stress path. Changing them currently cannot balance the measured results:

- `SquadFireController`: `stress_scale`, `stress_slow_per_round`, `weapon_stress_mult`, `stress_resilience`, `stress_kill_fast_first`, `stress_kill_ratio_bonus`, and the legacy stress-cover curve parameters. The active resolver uses `cover_multiplier_exp` instead.
- `StressController`: the fast/slow half-lives and weights belong to commented-out decay code. Effective stress uses equal bin weights and active recovery is linear. Legacy panic fast-decay/freeze and heavy-fire freeze settings are also inactive.
- `get_rally_bonus()` exposes accumulated aura rally bonuses, but the active `_apply_recovery_bias()` does not consume them. It does consume HQ rally and situational recovery multipliers.

Defend orders and close-combat defense preparedness do not directly multiply ranged stress. Defense enters through actual cover, morale and attention geometry. These gaps are documented without adding assertions that would require the unused settings to remain ineffective. Passing the suite establishes integration and relative behavior; it does not establish desired gameplay balance.


## Passive contacts and clustered bearings

Overload now uses a separate demand from observation focus. Visible passive contacts contribute 0.2 demand before distance attenuation; recently firing contacts blend toward 2.0. Remembered contacts contribute half the passive weight, scaled by remaining awareness. Raw directional demand still drives focus, detection and known-bearing coverage, so reducing overload does not hide contacts or remove flank/surround information.

Nearby bearings share observation effort through an order-independent angular calculation. For contact i, its effective contribution is `weight_i / (1 + overlapping_weight_i / 1.5)`. Overlap uses the fourth power of positive directional alignment; opposing or perpendicular bearings do not overlap. Contributions from one identical bearing asymptotically approach 1.5 demand, rather than increasing linearly with every visible squad. Visibility and incoming-fire bearings use this same shared-effort calculation. Dispersion is derived from the effective contributions before comparison with actual squad capacity. No fixed angular bins decide overload, preserving behavior across rotations and display-sector boundaries.

The `passive_overload_regression` scene covers six frontal contacts, firing versus passive contact weights, known and anonymous incoming fire, rotation and enumeration invariance, remembered positions/awareness expiry, and 180-second simulations with contacts kept visible. It runs fresh and initially maximum-stress pinned 12-man squads across four seeds, both isolated and with full command presence. No casualty, HQ, recovery or morale-transition coefficients are changed by this overload adjustment.

In the seed-zero fixtures, six passive frontal contacts leave fresh isolated and supported squads at zero stress. An isolated squad starting pinned at stress 100 returns to normal at 80.25 seconds; full command presence shortens this to 52.5 seconds. Both end at zero after 180 seconds with contacts still visible. These are controlled no-incoming-fire cases, not a forecast for squads under continuous weapon fire.

For six actively firing contacts at 200 pixels arranged over a 40-degree forward arc, required demand is approximately 1.552, below intact normal capacity 2.0. Splitting the same six contacts into opposing groups raises required demand to 4.084 and reaches the 4.0/s overload cap. These are observation-demand measurements; normal projectile suppression, surprise, casualties, fire-pressure recovery slowdown and switching costs continue to apply.

Engagement snapshots now include `attention.required`, the adjusted demand compared with `attention.capacity`. Existing `attention.demand` and `attention.sectors` remain raw observation inputs and can exceed capacity without implying an overload deficit. Historical measurements above predate this adjustment.


Validation of this adjustment: all 11 stress suites pass, including 49 passive-overload checks, 48 whole-squad exchanges (104 combatant result rows), and the 1,370-case weapon/scenario matrix. Whole-squad provisional balance alerts fall from three to zero. Mean midrange-duel stress at 45 seconds, averaged over both sides and four seeds, falls from 62.39 to 32.66; the corresponding attention-disabled control is 32.64. Mean defender stress in crossfire 2v1 remains 100.0 at 45 seconds, so separated firing directions can still suppress fully. The exchange comparison uses the same scenario definitions and seed set; changed morale can alter later random-stream consumption, so it is not an identical casualty-roll replay. All 316 project scripts parse and pass convention checks. The 41-check real-map capture regression also passes; it retains the existing map shutdown resource-leak warnings.


## Pinning feedback and recovery after fire

Pinned squads now retain 80% of their stressed observation capacity instead of 55%. Existing stress, casualties and cohesion still affect capacity; cautious, panic and combat-ineffective factors remain unchanged. Pinning still uses the same weapon accuracy, firing-rate and movement penalties. This reduces the extra overload created by becoming pinned without granting full observation performance.

`StressController.unpin_no_fire_delay_s` defaults to 3.0 seconds. After the incoming-fire history expires, a quiet-time accumulator advances using simulation time. It counts only the portion of a tick after the last fire sample expires, including ticks spanning that boundary. A new valid impact resets quiet time immediately; invalid or empty impacts do not. With the default two-second fire window, high-stress quiet recovery becomes eligible approximately five seconds after the last impact.

A pinned squad at or above `panic_threshold` can now use the existing PINNED→CAUTIOUS rally roll after this quiet interval. It retains the normal refractory time, time-pinned ramp, cohesion/casualty modifiers and repin protection. Recovery is probabilistic, not a guaranteed transition exactly at the eligibility time. Returning to cautious restores its ordinary higher recovery capacity. During actual fire or a shorter lull, the high-stress unpin gate remains closed. Below `panic_threshold`, the existing unpin behavior remains available. High residual stress by itself cannot repin a cautious squad without renewed incoming fire.

No baseline recovery rates, command bonuses, casualty shocks or projectile suppression values are increased for this change. The dedicated `pinning_recovery_regression` verifies the attention factor; quiet timing at four step sizes; interruption by renewed fire; invalid impacts; high-stress recovery and repeated pinning; and 64 seeded live-attention cases with six contacts remaining visible. Those cases run 10 seconds of heavy pressure from an initially pinned, maximum-stress 12-man squad, followed by 180 seconds without further firing. Both clustered and opposing contact layouts are covered, with no command support or full command presence. Recently firing contacts fade through the production `update_fire_recent()` method.

Across 16 seeds per layout/support combination, high-stress unpinning occurs an average of 7.64 seconds after the firing phase ends. Every tested squad remains pinned during the heavy-fire phase and unpins while residual stress is still above 65. Isolated squads return to normal after 67.08 seconds with frontal contacts or 70.81 seconds with opposing contacts; full command presence shortens these to 46.39 and 49.73 seconds respectively. These controlled cases keep cohesion and the 12-man roster intact, with prescribed suppression inputs. They do not model casualty-driven recovery shock or a replay of the captured engagements.

Engagement snapshots record `stress.time_without_fire_s`, measured after expiry of the incoming-fire window. The configured quiet delay is included in each unit's exported stress tunables.

Validation after the pinning-recovery change: all 12 stress suites pass, including 285 targeted pinning-recovery checks, 48 whole-squad exchanges and zero provisional balance alerts. All 317 project scripts parse and pass explicit-type/no-ternary checks. The real-map capture test passes all 41 checks and retains its previously observed shutdown resource-leak warnings.
