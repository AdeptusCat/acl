# Engagement analysis — 25 October 2026

The strongest balance failure is sustained attention overload and its interaction with pinning. The large Crossings engagement suppresses healthy squads for minutes despite little lethal fire and intermittent or absent incoming fire. A general HQ recovery increase would amplify an already large difference between HQs and ordinary squads. A separate confirmed friendly-fire incident contaminates the older combat model's casualty results.

## Scope and reliability

Analyzed all nine supplied capture directories: **48,043 events and 2,321 snapshots**. All JSON/JSONL parsed successfully, all sessions closed with `complete: true`, and stream counts and contiguous event sequences match their manifests. Every pre-result impact has an applied/ignored effect record and every such effect has a matching impact. Relevant debug flags stayed false throughout, including `no_damage` and `dont_fire_weapons`.

Six captures share all 13 recorded rule hashes with the attention rules in Git commit `d5a8396`. They predate branch/commit recording, so this identifies captured source contents, not a provable whole-checkout commit. Three captures explicitly identify clean `debug_log` commit `9419c848bd745dc1a875606ed56c3e1f0c32e817`, and all their recorded rule hashes match that commit. The final 17:10:27 capture returns to the attention rule set.

These are observational matches with different orders, positioning, random outcomes and, between groups, several bundled code changes. They are **not controlled A/B trials**. Differences cannot be assigned solely to adding attention: the attention version also contains the recovery rebalance, accumulated fire pressure, cohesion synchronization and unpin-timer fix.

Unless stated otherwise, metrics stop at the **first match-result event**, or map closure if none occurred. For example, the 16:32:24 capture continued to 483.9 s after its first result at 183.7 s; post-result activity is excluded. Pin percentages below use time-weighted active rifle/MG/other combat squads, excluding HQs, surrendered and exited units. Snapshot-based timings have approximately one-second resolution; event timings are more precise. Casualties count recorded soldiers, including direct elimination, not just weapon impacts. Times identifying captures are their UTC folder timestamps.

## Match overview

All paired values are **Allies / Axis**. Duration is simulation time to result/closure, including time before first fire. “Closed without result” is not counted as a defeat.

| Capture UTC | Map | Rules | Duration (s) | Casualties | Committed rounds | Combat-squad time pinned | Recorded result |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 16:27:18 | Approach | attention | 162.0 | 1 / 5 | 293 / 221 | 18.2% / 19.7% | Allied major victory |
| 16:30:10 | Approach | attention | 125.1 | 0 / 6 | 289 / 83 | 0.0% / 29.6% | Allied major victory |
| 16:32:24 | Orchard | attention | 183.7 | 6 / 21 | 402 / 230 | 0.0% / 9.9% | Allied major victory |
| 16:40:35 | Approach | attention | 124.7 | 12 / 1 | 72 / 158 | 13.2% / 0.0% | Closed without result |
| 16:42:47 | Orchard | attention | 295.9 | 29 / 13 | 706 / 463 | 28.8% / 33.3% | Closed without result |
| 16:54:57 | Approach | debug_log | 273.0 | 5 / 6 | 713 / 409 | 13.9% / 10.8% | Allied major victory |
| 16:59:49 | Orchard | debug_log | 232.6 | 14 / 24 | 1915 / 518 | 6.7% / 18.4% | Allied major victory |
| 17:03:56 | Crossings | debug_log | 347.0 | 15 / 56 | 4265 / 2177 | 8.7% / 28.4% | Allied major victory |
| 17:10:27 | Crossings | attention | 237.9 | 1 / 6 | 1700 / 1313 | 59.2% / 50.1% | Closed without result |

The small Approach maps can remain playable under attention: the 16:30:10 match has no Allied pinning or casualties. The strongest failure appears as the number of visible squads increases in Orchard and especially Crossings. This points to how attention scales with enemy count and morale, rather than a universal inability to withstand the first burst.

## 1. Persistent attention overload is the main stress source

In the 17:10:27 Crossings capture, recorded attention gains total **5,882.6 effective stress points**, versus **485.8 from incoming-fire stress events** across all units. Restricting to combat squads excludes HQs absorbing and recovering large amounts: **3,662.9 attention versus 417.8 incoming-fire**, or **89.8% attention**. These are cumulative gains across units and time, not a single meter value; recovery can remove points and later gains can add them again. At bin saturation, recorded actual gains are capped and understate excess raw demand.

Raw attention input to combat squads is **98.8% overload and 1.2% switching**. Lowering the switching cost alone will have little effect. Of approximately 2,466 combat-squad seconds at the maximum overload rate, **74.9% have both zero crossfire pressure and `flanked: false`**. Maximum attention stress does not require actual flanking.

The source sums each visible enemy as a separate demand and additionally adds incoming bearing demand. A contact contributes baseline demand even while not firing. Several visible squads in a narrow forward arc can overwhelm capacity; the same firing threat can also contribute to visibility demand and incoming-bearing demand. Suppression from an impact is then charged separately.

Evidence: [contact demand](/home/blight/Documents/godot/Projects/acl/ai/squad/squad_tactical_state.gd:98), [overload calculation](/home/blight/Documents/godot/Projects/acl/ai/squad/squad_tactical_state.gd:177).

**Adjustment priority:** reduce sustained demand from non-firing contacts; apply diminishing demand for contacts sharing an angular sector; retain a stronger penalty for separated active firing directions. Avoid counting a known firing contact and its bearing as two independent full threats. Tune overload against sustainable recovery before changing weapon suppression globally.

## 2. Pinning creates a feedback loop and an unpin dead end

Attention quality falls with current stress and is multiplied by **0.55 when pinned**. Capacity drops, producing more overload. Pinned recovery is also weaker. That makes one pin event capable of becoming self-sustaining.

`CA_P1_S3_Allies_Rifle` in 17:10:27 illustrates it:

- **39.05 s:** pinned at stress 37.24, with all 12 men.
- **47.67 s:** unpins at stress 52.67, still 12 men.
- **65.36 s:** repins at stress 73.17, still 12 men.
- **237.02 s:** remains pinned near stress 100, still 12 men and cohesion 1.0. HQ presence is 1.0. Incoming fire and crossfire are both zero, `flanked` is false, but overload remains 4.0/s.

**A longer no-fire case:** Allied P1 rifle squad 2 receives its last recorded impact at **152.40 s** and no further impact before closure at 237.88 s. Every sampled state from **155.03 to 237.02 s** remains pinned at stress above 99, with all 12 men alive. Its overload input is still 4.0/s. This is approximately 82 sampled seconds of failed recovery after the incoming-fire window expired.

At 200 s, **seven of eight Allied combat squads** are pinned; **six pinned squads are still at full strength**. Seven of eight have stress at least 99.

The ordinary PINNED→CAUTIOUS transition is only evaluated below stress 65. At or above 65 the code evaluates PINNED→PANIC, whose configured rate is zero. There is a separate adjacency-based rout path, but no ordinary unpin path while stress remains above that threshold. Continued overload can hold a squad in this region indefinitely, even after bullets stop arriving.

Evidence: [capacity penalties](/home/blight/Documents/godot/Projects/acl/ai/squad/squad_tactical_state.gd:296), [pin transition gate](/home/blight/Documents/godot/Projects/acl/scenes/game/units/combat/unit_stress_controller.gd:680).

**Fix priority:** reduce the morale-to-attention feedback and provide a route out of pinning after fire subsides, with a bounded recovery delay and clear hysteresis. Recovery should not require first escaping a stress region maintained by the pinning penalty itself. Preserve heavy-fire suppression and legitimate multi-direction pressure.

## 3. HQs already have substantial personal resilience; their presence does not solve overload

At **237.02 s** in the final Crossings capture, two units occupy hex **[9, 5]**:

| Unit | Members | HQ presence | Morale | Stress | Recovery capacity | Overload input |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| Allied P1 platoon HQ | 5/5 | 1.0 | Normal | 0.00 | 4.86/s | 4.0/s |
| Allied P1 rifle squad 3 | 12/12 | 1.0 | Pinned | 99.96 | 1.3365/s | 4.0/s |

Both have no incoming fire, no crossfire, no casualties, and cohesion 1.0. Their exact visible-contact lists differ (five versus six), but both already receive maximum overload. The HQ recovers fast enough to remain normal, while the rifle squad cannot escape its pinned state. The logged overload is a raw input rate; stress gain modifiers apply afterward. It should not be subtracted directly from a bin-limited, smoothed recovery measurement.

HQs are not universally immune: the second Allied platoon HQ reaches approximately 100 stress in this same match, and other captures show HQs pinned or eliminated. The evidence supports **uneven resilience and recovery-state feedback**, not a claim that every HQ is invulnerable.

**Adjustment priority:** retain meaningful command support but do not globally multiply HQ recovery further. First make healthy isolated squads stable against observation-only contact demand, then calibrate the extra support needed under actual fire. HQ personal resilience and the benefit delivered to surrounding squads should have separate limits.

## 4. The Crossings comparison shows less shooting but much more suppression

For the **first 200 simulation seconds** of the two Crossings captures:

| Metric | `debug_log` 17:03:56 | Attention 17:10:27 |
| --- | ---: | ---: |
| Allied committed rounds | 2,102 | 1,431 |
| Axis committed rounds | 1,597 | 1,197 |
| Allied casualties | 5 | 1 |
| Axis casualties | 14 | 5 |
| Allied active unit time pinned, including HQs | 5.0% | 42.3% |
| Axis active unit time pinned, including HQs | 17.6% | 35.8% |

These percentages include HQs to match the independently calculated equal-window sample; they use a different denominator from the combat-squad percentages in the overview. The attention match has fewer shots and casualties but far more pinned time. This is consistent with the directly logged attention gains and feedback loop, though the match pair is not a controlled experiment.

For the complete pre-result/closure periods, Allied combat-squad pinned time rises from **8.7% in the older Crossings match to 59.2% in the attention match**. The latter was closed without a result, so comparing victory speed is inappropriate.

## 5. Confirmed same-team fire causes real casualties

At **270.1748 s** in the `debug_log` Crossings capture:

- Shooter: `CA_P1_S3_Axis_MG`, MG34 (Tripod).
- Target: `CA_P2_S1_Axis_Rifle`, also Axis, at hex [15, 5].
- Eight-round burst, five rolled hits, four requested casualties.
- The applied effect confirms **7 → 3 members**, with damage enabled.

There are **56 same-team impact/effect pairs** before the result in that match, causing four casualties and approximately 25.2 cumulative effective stress gain. The older Orchard match contains another 13 same-team pairs, with no casualties and approximately 2.3 stress gain. None occur in the supplied attention captures; this does not establish that their resolver is safe. The current attention resolver also adds every active unit in the target hex without filtering teams.

Evidence: [impact event 14712](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T17-03-56_6567ac2017357fdd/events.jsonl:14712), [applied event 14721](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T17-03-56_6567ac2017357fdd/events.jsonl:14721), [target collection](/home/blight/Documents/godot/Projects/acl/scenes/game/units/combat/squad_hit_resolver.gd:50).

**Fix priority:** define and enforce same-team impact policy. If ordinary small-arms friendly fire is unintended, exclude friendlies at resolution, including units that enter the hex during flight. If intended, distinguish it explicitly in targeting, logs and balance tests rather than treating all target-hex occupants as enemy recipients.

## 6. Casualty totals mix ranged fire, close combat and direct elimination

The 16:42:47 Orchard capture records **42 casualties**, but only **three** are member losses in incoming-fire applications. Its three eliminated rifle squads are in close combat when their death events are recorded. They account for 34 initial men; additional non-impact casualties also occur. This is evidence that the overall casualty count cannot be interpreted as ranged-weapon lethality.

Other matches have similar mismatches: 16:40:35 records 13 casualties versus three from incoming effects; 16:59:49 records 38 versus five. Close-combat code applies specific casualties and adds a separate fixed 10/10 stress event for surviving units. The capture records these as generic `cause: event` gains, with no attacker or close-combat roll attribution. Some direct elimination records can also include every remaining soldier.

**Telemetry limitation:** the logs can reconcile casualties against ranged-fire member changes, but cannot assign every remaining casualty to an exact source. Add causal fields for close-combat participants/rolls/kills, direct elimination reasons and debug casualty actions before balancing all lethality from these sessions.

## Concrete regression cases justified by the captures

1. **Full-strength frontal contact:** a 12-man squad observes several enemies in one forward arc for 180 s, with no incoming fire. Require bounded observation stress, retained firing ability and no permanent pin loop. Repeat without HQ and with strong HQ support.
2. **Fire stops while enemies remain visible:** pin a healthy squad, reach stress above 65, stop actual fire but keep contacts visible. Require downward stress trend and an eventual unpin path; cover both first and later pin cycles.
3. **Same visible count, different bearings:** compare clustered frontal contacts, two separated firing directions and surrounding fire. Distinct geometry should matter more than adding another passive contact in the same sector.
4. **Headquarters versus supported squads:** use the same contacts and firing schedule; record recovery for isolated infantry, supported infantry and HQs. Assert a useful bounded support advantage and survival of isolated squads under intermittent light fire.
5. **Friendly unit enters during flight:** fire at an enemy hex, move a friendly squad into it before impact, and assert the intended casualty/stress policy. Include stacked enemy/friendly occupants and rifle, MG and explosive cases.
6. **Close-combat attribution:** reconcile every casualty and generic stress gain to ranged fire, close combat or direct elimination. Preserve small-unit and crew-served weapon behavior.

Exact numerical acceptance limits need explicit design targets and controlled simulations. These nine matches support the scenarios and failure mechanisms above, not a uniquely correct new constant or a general weapon nerf.

## Source captures

- [2026-10-25T16-27-18_f6e6cf5707df649a](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-27-18_f6e6cf5707df649a) — Alderbrook Approach, attention.
- [2026-10-25T16-30-10_ebde77c4529dbe56](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-30-10_ebde77c4529dbe56) — Alderbrook Approach, attention.
- [2026-10-25T16-32-24_29af77955503ce04](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-32-24_29af77955503ce04) — Alderbrook Orchard, attention.
- [2026-10-25T16-40-35_9a60bf3ef11b8982](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-40-35_9a60bf3ef11b8982) — Alderbrook Approach, attention.
- [2026-10-25T16-42-47_ef7e9a610a16fc8d](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-42-47_ef7e9a610a16fc8d) — Alderbrook Orchard, attention.
- [2026-10-25T16-54-57_a279d16ddd41d173](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-54-57_a279d16ddd41d173) — Alderbrook Approach, debug_log.
- [2026-10-25T16-59-49_63fb4a404982972c](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T16-59-49_63fb4a404982972c) — Alderbrook Orchard, debug_log.
- [2026-10-25T17-03-56_6567ac2017357fdd](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T17-03-56_6567ac2017357fdd) — Alderbrook Crossings, debug_log.
- [2026-10-25T17-10-27_786ef7127bf5b649](/home/blight/.local/share/godot/app_userdata/AdvancedCompanyLeader/debug/engagements/2026-10-25T17-10-27_786ef7127bf5b649) — Alderbrook Crossings, attention.

Derived per-unit and per-weapon metrics are saved in [engagement_metrics_2026-10-25.json](/home/blight/Documents/godot/Projects/acl/docs/analysis/engagement_metrics_2026-10-25.json). No gameplay code was changed.
