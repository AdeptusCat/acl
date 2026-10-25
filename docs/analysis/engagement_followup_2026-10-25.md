# Follow-up engagement analysis — Crossings, 25 October 2026

The tuning substantially reduces widespread attention-driven pinning and restores observable high-stress rallies after fire stops. Remaining stress plateaus are concentrated in units carrying large visible-contact demand. The new captures also reproduce same-team impact effects.

## Captures and method

Both captures are on Alderbrook Crossings / “4. Two Crossings,” with the same recorded rule hashes. All 13 recorded hashes match the corresponding sources in `f0e54bd` (isolated recovery and bounded HQ support). Exported tunables and recorded recovery limits confirm the new settings. Neither capture includes a `version` object, so this establishes matching recorded rule contents, not the full checkout's branch/commit or dirty state.

All **21,645 events and 510 snapshots** parse successfully. Both session manifests are complete, stream counts and contiguous sequence numbers match, and every pre-result impact/application pair correlates. Relevant debug flags remain false. Analysis ends at the first result, or closure if none occurs. The first capture runs to 358.85 seconds but its first result occurs at 356.02 seconds; later activity is excluded. All times identifying captures are UTC folder timestamps. Snapshot-based intervals are approximate to one second.

Paired values below are **Allies / Axis**. Casualties include every recorded soldier loss; committed rounds are counted once per shot event, not multiplied by affected targets. Pinned percentages use time-weighted active combat squads, excluding HQs, surrendered and exited units.

| Capture UTC | Time to result/closure (s) | Casualties | Committed rounds | Combat-squad time pinned | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| 17:54:06 | 356.0 | 15 / 43 | 4482 / 2495 | 4.8% / 26.6% | Allied major victory |
| 18:00:53 | 147.8 | 2 / 1 | 978 / 1750 | 20.0% / 13.4% | Closed without a result |

The short second match commits only four of the eight Allied combat squads to firing/receiving fire. Restricting its denominator to those four engaged squads raises Allied pinned time from **20.0% to 40.0%**. All six Axis combat squads fire. This matters when interpreting its lower whole-force averages or comparing it with the first capture. Closing the map without a result is not counted as a defeat.

These are observational matches with different orders, positions, exposures and random outcomes. They do not provide a controlled estimate of a tuning change's causal effect.

## Comparison with the earlier attention capture

The earlier 17:10:27 Crossings capture used the original attention/recovery rules. Across its full 237.88 seconds, Allied combat squads spent **59.2%** of active time pinned, versus **4.8%** in the new 17:54:06 match. Axis pinned time falls from **50.1% to 26.6%**. The newer match reaches an Allied major victory at 356.02 seconds; the older capture closed without a result.

The differing durations should not be treated as a win-time comparison. In an equal first-200-second window:

| Metric | Earlier attention 17:10:27 | Tuned 17:54:06 |
| --- | ---: | ---: |
| Allied combat-squad time pinned | 53.8% | 2.9% |
| Axis combat-squad time pinned | 47.0% | 27.4% |
| Allied rounds | 1,431 | 2,378 |
| Axis rounds | 1,197 | 1,712 |
| Allied casualties | 1 | 2 |
| Axis casualties | 5 | 18 |

The reduced pinned time is accompanied by more firing and a more lethal engagement. It does not establish whether overall casualty rates are now correct. In particular, the new larger match records 58 casualties, of which 30 are member losses attributable to incoming-fire applications; three unit-death events occur during close combat. Ranged, melee and direct-elimination losses still need separate interpretation.

Attention's share of cumulative combat-squad stress gain falls from **89.8%** in the earlier attention capture to **28.1%** in the new larger match and **31.7%** in the new shorter match. These are logged actual gains after modifiers and caps. They are sums across units and time; saturation can hide excess raw demand. Recovery subsequently removes some of those points.

## Recovery now occurs while contacts remain visible

The larger capture records **ten high-stress rallies to cautious**, including three from panic. Examples include:

- Axis P2 rifle squad 1: unpins at **101.78 s**, stress **81.8**, after 3.36 seconds of logged quiet time. From a sampled 81.5 stress at 102.01 seconds, it reaches 1.9 and normal morale by 157.01 seconds, with ten men and only 0.25 command presence.
- Axis P1 rifle squad 2: unpins at **181.28 s**, stress **92.4**, after 5.13 quiet seconds, with ten men. This demonstrates that the old above-65 unpin gate is no longer locking it in pinned morale.
- Allied P2 platoon HQ: unpins at **275.04 s**, stress **72.2**, with four men and **zero external command presence**. It subsequently reaches zero stress and normal morale while remaining active.
- Allied P2 rifle squad 1: a sampled **47.8 pinned stress at 181.03 s** reaches zero and normal morale by 290.02 seconds. It still has eleven men, with command presence 0.2 at the latter sample.

Logged `time_without_fire_s` begins after the two-second incoming-fire window expires. Thus 3.36 quiet seconds corresponds to approximately 5.36 seconds after the most recent recorded impact. Morale recovery retains stochastic rolls and situational penalties; these examples are observed trajectories, not guaranteed fixed recovery durations.

The shorter match provides no long no-impact recovery interval for its worst affected combatants. Its Allied P1 MG team and Axis P1 rifle squad 1 continue receiving impacts, repeatedly resetting quiet time. Their continued pinning cannot be used as evidence that quiet recovery is broken.

## HQ bounds hold in observed live states

Reconstructed the leadership-free recovery baseline from each active snapshot's morale factor, base cohesion, casualty shock, fire pressure, global recovery scale and registered unit tunables. The highest observed direct multiplier is:

- **1.458× for ordinary squads**, below the 1.5× shared command/aura limit.
- **1.9683× for HQ units**, including both leadership support and their personal bonus, below the combined 2.25× limit.

There are **zero observed budget violations** in either capture. These comparisons hold the recorded base condition constant; command's indirect influence on evolving combat cohesion or fighting outcomes is separate. Recovering HQs are not immune: the Allied P2 HQ reaches approximately 78 stress and suffers a casualty, while Axis HQ units reach 100 and some are eliminated.

## Remaining issue: quiet rally does not ensure falling stress

Two Axis units in the larger capture remain heavily stressed during an **85.9-second gap without impacts**, from 174.15 to the 260.03-second sample:

| Unit at 260.03 s | Members | Morale | Stress | Logged quiet time | Required attention / capacity | Overload | Recovery capacity |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| Axis P1 rifle squad 2 | 10/10 | Cautious | 97.18 | 83.85 s | 2.96 / 1.36 | 4.0/s | 1.570/s |
| Axis company HQ | 7/7 | Cautious | 97.44 | 83.85 s | 3.07 / 1.14 | 4.0/s | 1.859/s |

They have recovered to cautious morale, but the stress meter remains high. Both still see eight contacts. In the preceding five seconds, those visible contacts commit five shots; their logged targets are other Axis units. Incoming bearing pressure is zero. The rifle squad is flagged flanked; the HQ is flagged flanked and surrounded, so these are dispersed contacts rather than the simple six-contact frontal cluster covered by the initial regression.

The source uses each visible enemy's global `fire_recent` as demand urgency, regardless of whether that firing is threatening the observing squad. Combined with dispersed contact geometry, this can sustain maximum overload during a genuine gap in incoming fire. At 220 seconds, the rifle squad's incoming stress rate is about 1.835/s while its actual recovery is 1.570/s; its meter can grow without any new impact.

**Next adjustment justified by these captures:** distinguish nearby observed firing activity from received or credibly threatening fire. A quiet squad should retain spotting and awareness of dispersed enemies without automatically paying the same sustained stress cost as a squad receiving their fire. Add a case with contacts firing at other targets on multiple bearings, and require a downward stress trend after the observing squad's incoming fire stops. Preserve meaningful overload under real crossfire. Further broad HQ buffs would not address this source.

## Small teams still deserve separate measurement

In the shorter match, the Allied P1 MG team remains **5/5** but spends approximately **92.8 seconds pinned**, with its longest sampled pin interval about 79.8 seconds. At 147 seconds it has full command presence, near-100 stress, required attention 1.85 against capacity 0.85, and maximum overload. Incoming impacts are still arriving, so its quiet recovery gate is correctly closed.

This shows a remaining vulnerability of small observer teams under multi-contact pressure, not a proven no-fire deadlock. The model intentionally reduces observation quality for teams below ten men; further tuning needs actual MG-team fire, setup/crew performance, bearings and exposure in the tests. The earlier intact 12-man recovery cases do not establish the appropriate suppression threshold for a five-man MG team.

## Friendly impact effects persist

The larger match contains **45 same-team incoming-effect applications**, producing approximately **82.5 cumulative effective stress gain and zero direct casualties**. The shorter match has none. The previous target-hex team-filtering issue therefore persists on the tuned branch and can affect stress even when no friendly soldiers die. Any friendly-fire policy fix must cover suppression and casualty shock as well as casualty recipients.

## Logging limitation

Both metadata files still omit the Git branch/commit object. Their matching recorded rule hashes are enough to classify these captures for this comparison. New captures on this branch should also record branch, full commit and dirty status, as the separate `debug_log` implementation already did.

## Sources

- [2026-10-25T17-54-06_6c7689b76d0a953d](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T17-54-06_6c7689b76d0a953d)
- [2026-10-25T18-00-53_0c4f76e958bbcfa8](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T18-00-53_0c4f76e958bbcfa8)

Earlier analysis: [engagement_analysis_2026-10-25.md](/home/blight/Documents/godot/Projects/acl/docs/analysis/engagement_analysis_2026-10-25.md). No gameplay code changed during this analysis.
