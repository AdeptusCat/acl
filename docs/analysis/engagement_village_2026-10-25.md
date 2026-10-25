# Alderbrook Village engagement — 25 October 2026, 19:32 UTC

The observation/suppression separation works in this capture. Stress falls during genuine lulls despite visible contacts. The clearest remaining correctness problem is indiscriminate same-hex friendly impact effects, now including casualties. This match does not justify another broad increase to recovery or HQ support.

## Capture and scope

Analyzed `2026-10-25T19-32-52_a04b535f6154c3d9` on **5. Battle for Alderbrook / Alderbrook Village**. The complete session lasts 819.75 seconds; the first result is a **draw at 732.90 seconds**, with `winner=-1`, minor outcome level and `timeout=false`. Combat metrics stop at that result, excluding later result-screen time. This is a different map from the earlier Crossings captures, so changes in aggregate combat performance cannot be attributed solely to tuning.

All 39,864 events and 822 snapshots parse; manifest counts and contiguous sequence numbers match. Every pre-result impact and incoming-effect application correlates. All 13 recorded rule hashes match the current files at commit `19cbbcf` (`fix: base attention stress on received fire`). Metadata still omits branch, commit and dirty status, so matching rule hashes establish recorded rules rather than the complete build identity.

Damage and weapon firing are enabled throughout. `show_enemies=true` is recorded; this is a debug play session. Snapshot intervals are approximately one second, so sampled durations and stress peaks are approximate.

## Engagement totals

| Metric, through first result | Allies | Axis |
| --- | ---: | ---: |
| Starting soldiers | 150 | 117 |
| Soldier losses, all causes | 40 | 65 |
| Committed rounds | 8,646 | 5,183 |
| Active combat-squad time pinned | 11.1% | 15.6% |
| Active combat-squad time in panic | 0.4% | 4.8% |
| Units recorded destroyed | 2 | 4 |
| Units recorded exited | 0 | 5 |

Morale percentages integrate active squad time and exclude HQs, surrendered units and exited units. Restricting the Allied denominator to combat squads that ever fired or received an effect raises its pinned fraction to 12.0%. Casualties include close combat and direct unit elimination as well as ranged fire.

Across combat squads, cumulative logged attention gain is 388.85 stress versus 3,505.75 from incoming fire: **10.0% of those combined actual stress gains comes from attention**. Saturation and recovery affect these values; they are not raw pressure or final stress. Earlier Crossings captures had attention shares around 28–32% after the earlier tuning. The difference is consistent with the intended mechanism but is not a controlled balance comparison across maps.

## Quiet recovery is repaired

Settled quiet samples require expired incoming pressure and at least two seconds of logged quiet time. Across these samples:

- Continuous attention gain is **zero**, including roughly 5,916 accumulated squad-seconds with visible enemies.
- Maximum sampled overload rate is **zero**.
- There are **1,314 successive comparisons with positive previous stress in which stress declines**, and zero increases or positive-stress plateaus. These comparisons require unchanged member count and no close combat in either sample.

Examples:

| Unit | Interval | Stress | Members | Observation/support |
| --- | --- | --- | --- | --- |
| Allied P1 rifle squad 3 | 150.02–167.00 s | 64.06 → 41.00 | 12/12 throughout | Three contacts visible at both ends; command presence 0.25 |
| Axis P2 platoon HQ | 408.01–540.03 s | 61.25 → 0 | Six survivors throughout | Three → four visible contacts; command presence 0.25 → 0 |
| Axis P3 platoon HQ | 693.01–717.01 s | 31.84 → 8.01 | 7/7 throughout | Zero command presence |

The previous no-impact stress plateau does not recur. No additional global recovery buff is supported by this capture.

## Long pins now coincide with received fire

Two heavily affected MG teams illustrate different exposure from the quiet cases:

- **Axis P2 MG:** approximately 384–551 s pinned, receiving **933 incoming applications** during that sampled interval. Mean sampled pressure is 9.94 rounds/s; logged quiet time never exceeds 0.50 s. Members fall from seven to five. Incoming weapons include the M1919, Garand, BAR and rifle grenades.
- **Allied P3 MG:** approximately 493–584 s pinned, with **159 incoming applications**, mean sampled pressure 4.93 rounds/s, three survivors and full command presence throughout the sampled interval. There are brief gaps; maximum logged quiet time is 5.21 s, followed by renewed pressure.

These are repeated-fire pins rather than sustained observation stress. Intact teams can also operate without collapsing: Allied P1 MG loses nobody, fires 992 rounds, peaks at sampled stress 18.1 and never pins. Axis P3 MG loses nobody, fires 1,531 rounds, peaks at 14.2 and never pins. Exposure and damage matter more than the MG label alone.

If further balancing is needed, reproduce the damaged three-survivor MG under intermittent 5-round/s pressure, varying cover, incoming bearings and actual HQ presence. Evaluate its weapon output and time pinned before changing small-team recovery globally.

## HQ remains bounded and vulnerable

Reconstructing leadership-free recovery from registered morale factors, base cohesion, casualty shock and received-fire slowdown gives maximum observed multipliers of **1.458× for ordinary squads** and **1.9683× for HQs**, including their personal bonus. There are **zero observed violations** of the respective 1.5× and 2.25× combined bounds.

Both Axis P1 and P2 HQs reach 100 stress and are destroyed. The Allied P1 HQ also loses all five soldiers. Supported units still pin under actual fire, while HQs recover during quiet periods. This supports retaining the current recovery/support bounds. It does not isolate HQ's causal effect on combat outcomes.

## Highest-priority correction: friendly hex recipients

There are **37 same-team incoming-effect applications**, causing **five direct soldier losses** and **32.01 effective stress gain**. All five losses are Axis:

| Time | Shooter → friendly recipient | Weapon | Losses |
| --- | --- | --- | ---: |
| 145.51 s | P1 rifle 2 → P1 rifle 1 | MP40 | 3 |
| 167.07 s | Mortar → P1 rifle 1 | 81 mm mortar | 1 |
| 334.70 s | P2 MG → P2 rifle 1 | MG34 tripod | 1 |

The MP40 and MG applications are ordinary bullet fire, not rifle-grenade explosions. The source adds every active unit occupying the target hex to `batch_targets`, without a team check, then marks those recipients under fire and applies casualties, suppression and attention-bearing effects. See [squad_hit_resolver.gd:50](/home/blight/Documents/godot/Projects/acl/scenes/game/units/combat/squad_hit_resolver.gd:50).

Address recipient eligibility before tuning more suppression constants. Define and test bullet versus explosive friendly-fire behavior, including friendly-only and mixed-team target hexes and projectile travel. Filtering only casualty recipients would leave spurious pressure, stress, casualty shock and incoming bearings active.

## Priority order

1. Correct/define friendly recipient eligibility for all incoming effects. This capture proves unintended-looking bullet losses, beyond the earlier stress-only cases.
2. Add a captured-pressure regression for damaged MG teams and repeated short gaps; retain the demonstrated quiet recovery.
3. Record branch, full commit and dirty status on this branch too. Rule hashes identify the stress implementation here, but do not identify the full build.

No gameplay code changed during this analysis. No simulation rerun was necessary to establish these recorded behaviors.

Capture: [2026-10-25T19-32-52_a04b535f6154c3d9](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T19-32-52_a04b535f6154c3d9). Machine-readable results: [engagement_village_metrics_2026-10-25.json](/home/blight/Documents/godot/Projects/acl/docs/analysis/engagement_village_metrics_2026-10-25.json).
