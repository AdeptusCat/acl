# Whole-squad fire exchanges

Run with the complete stress suite:

```bash
python3 tests/run_stress_suite.py --output /tmp/acl-stress-results
```

The new exchange scene runs at 60 fixed frames per second; the other stress scenes keep their existing 120-frame test cadence. The runner gives the exchange scene a 600-second timeout, captures its log, and rejects script errors or missing completion summaries.

Run the exchange scene directly with isolated save data:

```bash
mkdir -p /tmp/acl-stress-results
exchange_data="$(mktemp -d)"
env XDG_DATA_HOME="$exchange_data/data" XDG_CONFIG_HOME="$exchange_data/config" XDG_CACHE_HOME="$exchange_data/cache" \
  godot --headless --path . --fixed-fps 60 tests/squad_fire_exchange_regression.tscn \
  -- --output=/tmp/acl-stress-results
```

`--quick` selects one seed for the covered duel and HQ comparison. `--case=midrange_duel --seed=101` reproduces a specific exchange; supported seeds are 101, 202, 303 and 404. Empty filter selections fail explicitly.

## What actually runs

The fixture instantiates the production unit scene and its complete faction loadouts: twelve US rifle-squad members, ten German rifle-squad members, or the authored MG team. Every soldier has an independent runtime weapon, magazine, reload and acquisition tasks. MG setup, crew roles, burst variation, projectile-delay timers and deferred impact effects execute their production implementations. Morale changes affect subsequent firing, so return fire can suppress the original attacker.

The fixture also runs actual casualty removal, leader promotion, weapon re-crewing, combat cohesion updates, attention geometry, fire-pressure history, morale transitions, leader auras and command connectivity. A platoon HQ is a real separate squad with the authored leadership roster and a one-hex command link. HQ does not contribute fire or appear in the enemy target list, isolating the support benefit.

Units remain stationary in a uniform test field. The fixture supplies prescribed, continuous LOS and cover values rather than relying on a campaign map or a spotting roll. Strategic AI, movement, objective selection, audio playback and visual projectile spawning are excluded. Visual signals are observed without resolving them into extra damage: the real firing coroutine performs each impact exactly once. Complete combat behavior therefore does not imply a complete tactical match or a test of retreat pathfinding.

Normal node processing and component timers are stopped, then relevant components are explicitly advanced at their simulation cadence. SceneTreeTimers used by the firing coroutines remain active. The fixture validates that its process delta matches 1/60 second. Each case has 45 seconds of reciprocal fire followed by 60 seconds with visibility and targets cleared. In-flight impacts and bearing memories are allowed to expire during recovery. Both sides start with normal morale and real weapon setup/acquisition delays; readiness is not forced complete. Processing order alternates each frame.

## Matrix

Each case runs four seeds. The focal squad is Allies in two seeds and Axis in two, giving 48 exchanges and 104 combatant summary rows. HQ support units are simulated but excluded from combatant averages.

| Case | Configuration |
| --- | --- |
| `covered_duel` | Rifle squad versus rifle squad, cover 2, four hexes |
| `open_duel` | Same duel in cover 0 |
| `hard_cover_duel` | Same duel in cover 4 |
| `close_duel` | Cover 2, two hexes; short-range weapons and rifle grenades operate normally |
| `midrange_duel` | Cover 2, three hexes |
| `midrange_without_attention_costs` | Paired three-hex counterfactual with the four new attention stress costs disabled |
| `far_duel` | Cover 2, six hexes; only weapons with sufficient range can engage |
| `defender_hq` | Four-hex covered duel with platoon HQ support for the focal squad |
| `mg_vs_rifle` | Authored MG team versus full rifle squad, four hexes |
| `frontal_2v1` | Two full enemy squads at equal range within the frontal arc |
| `crossfire_2v1` | Two full enemy squads on opposing bearings |
| `one_way_fire` | Focal squad receives fire without returning it |

In 2v1 cases the focal squad targets the first attacker; both attackers target the focal squad. The second attacker can therefore fire without receiving fire. This is deliberate target concentration, not an assertion that all squads exchange fire with every opponent.

The attention counterfactual preserves focus, directional demand and observation quality calculations. It disables surprise/crossfire additions at impacts and overload/switching gains between impacts. All other mechanics remain active. Subsequent morale, fire rates and casualties may diverge, so this comparison measures the total downstream effect rather than promising identical casualty rolls throughout the engagement.

## Reports and checks

- `squad_fire_exchange.csv`: one row per combatant, including roster size, faction, resolved rounds and volleys, number of distinct firing weapons, incoming effects, stress at 5/10/30/45 seconds, peak stress, first pin time and losses at that point, time pinned/panicked, final casualties/cohesion, post-fire stress and recovery time.
- `squad_fire_exchange_timeline.csv`: one-second samples of stress, morale, casualties, cohesion, resolved rounds, incoming rounds/second, raw attention demand, switching stress, surprise, crossfire pressure and recovery capacity. Raw attention fields remain visible in the counterfactual even though their stress contributions are disabled.

Recovery time identifies the start of the final continuous period below the normal-from-cautious threshold. A later incoming projectile or lingering attention burden can invalidate an earlier apparent recovery. Eliminated squads report no recovery. Peak stress includes both firing and recovery phases.

Mechanical assertions require complete authored rosters, actual resolved fire from each active firing squad, receipt of effects by deliberately selected targets, roster/casualty conservation, bounded finite stress, and multiple independently firing weapons in each ordinary covered squad. The one-way control must resolve no return fire.

Balance alerts are separate from mechanical assertions. The ordinary covered four-hex and three-hex duels flag:

- Pinning before five seconds without a casualty.
- More than 70% of the firing phase spent pinned.
- A surviving squad still above the caution recovery threshold after 60 seconds without new targets.
- Panic-level stress by ten seconds with at most one casualty.

These are provisional gameplay targets, not automatic justification to change production tuning. The default suite reports alerts while requiring mechanical correctness. Add `--strict-balance` to either the runner or scene to make alerts fail the run. A mechanical pass does not mean the combat balance passes.

## Initial findings

Means for the focal squad across four seeds, with current production tuning:

| Case | Stress at 45 s | Time pinned during fire | Casualties |
| --- | ---: | ---: | ---: |
| Covered duel, four hexes | 44.04 | 5.89 s | 0.25 |
| Covered duel, three hexes | 82.33 | 15.91 s | 0.75 |
| Three hexes, attention costs disabled | 46.35 | 13.43 s | 0.50 |
| Covered duel with HQ | 4.59 | 0.00 s | 0.25 |
| Two frontal attackers | 100.00 | 30.35 s | 0.00 |
| Opposing attackers | 100.00 | 34.46 s | 0.00 |

The controlled single-weapon matrix underestimated the accumulated burden on whole squads. The three-hex comparison shows a large downstream effect from attention costs. Two attackers can cap the focal squad's stress without causing any casualties in these seeds. HQ strongly improves the ordinary covered duel; unsupported recovery still fails the provisional target in three combatant runs: covered duel seed 202 and midrange seeds 101 and 404, all on the focal side. Those squads finish the recovery phase at approximately 53.14, 81.08 and 51.96 stress.

Four seeds are an initial diagnostic sample. Short-range rifle grenades, faction loadouts and the return-fire feedback are part of these results. The test adds evidence for subsequent tuning; it makes no production combat changes.

Validation: all ten suites pass their mechanical checks. The full exchange matrix produces 104 summary rows and 10,920 one-second samples, with three balance alerts. Two complete runs reproduced all summary measurements exactly. Strict mode was verified against the flagged covered-duel seed 202 and returned failure as intended. All 313 project scripts pass parsing and convention checks.
