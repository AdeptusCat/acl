# Enemy detection

Detection uses the terrain LOS table to select candidates. Blocking terrain still
blocks sight; attention never grants sight through an obstruction. Acquired
contacts require enough observable evidence to remain visible. Losing either
geometric LOS or visual identification requires fresh acquisition, even if
confidence and remembered awareness survive.

For an undetected candidate, the acquisition rate per simulation second is:

```
activity_rate * distance_factor * target_transmission
    * intervening_transmission * attention * observer_condition
```

`distance_factor = 1 / (1 + (distance_metres / 240)^3)`. A stationary target's
passive activity rate is `1 * distance_factor`; movement replaces that passive
rate with `3`. Recent firing adds up to `6` before the other factors. A quiet
stationary silhouette therefore receives distance attenuation twice. Movement
and muzzle flashes remain stronger long-range cues. All curves are continuous;
there is no detection-range cutoff.

The probability for an elapsed interval is `1 - exp(-rate * elapsed_seconds)`.
One successful roll acquires the contact. Failed rolls do not subtract confidence.
The match accumulates simulation time between visibility refreshes, so timer
frequency does not change the underlying acquisition rate. Shooting affects the
normal acquisition rate through recent firing; its event cannot reveal an
undetected shooter independently of attention, terrain, or observer state.

## Current tuning

Constants live in `scenes/game/match/match_visibility_coordinator.gd`.

| Input | Value |
| --- | --- |
| Hex width | 40 metres |
| Distance factor | `1 / (1 + (distance_metres / 240)^3)` |
| Stationary target passive rate | `1 * distance_factor` per second |
| Moving target base rate | 3 per second |
| Recent firing | Adds up to 6 per second before other modifiers |
| Target concealment transmission | `0.35 ^ concealment_strength` |
| Intervening concealment transmission | `0.55 ^ crossed_hex_count` |
| Moving observer | 0.65 multiplier |
| Observer under fire | 0.85 multiplier |
| Pinned observer | Additional 0.6 multiplier |

Target concealment uses the existing terrain flags and actual opaque sprite
pixels: fields/orchards have strength 1, woods have strength 2, and buildings
have strength 3. Transparent gaps have no target concealment. Bullet cover is
not a substitute for concealment. LOS hindrance counts each intersected field
or orchard hex once, excluding the observer and target hexes. Those counts
already respect sprite silhouettes, including rays along hex boundaries.

A moving enemy at 640 metres in the open has a rate of approximately 0.15 per
second before observer modifiers. Normal pre-contact focus directly toward it
raises the rate to approximately 0.182: mean acquisition time 5.50 seconds and
59.7% probability within five seconds. Close exposed movement still acquires
quickly. These are game tuning values, not measured real-world spotting data.

The former squared distance curve with a 320 m reference was too generous to
quiet distant targets. A healthy squad looking directly toward either reported
case now has the following chance of first acquisition over 30 seconds:

| Stationary, non-firing target | Previous | Current | Five observing squads, current |
| --- | ---: | ---: | ---: |
| 14 hexes (560 m), five intervening hindrance hexes, open target hex | 64.54% | 0.97% | 4.75% |
| 17 hexes (680 m), building concealment strength 3, clear intervening lane | 24.59% | 0.28% | 1.37% |

These comparisons assume full observation quality, focus strength 0.6 aligned
with the target, no observer movement or incoming fire, and continuously valid
geometric LOS. Team visibility combines sightings from all eligible squads;
several squads can still detect more than one squad, especially at closer range.

## Maintaining visual contact

Acquisition initializes a five-second tracking allowance. Each visibility
refresh changes it by `elapsed_seconds * (10 * acquisition_rate - 1)`, clamped
between zero and five seconds. Knowing where to look makes tracking easier than
finding an unknown enemy, while the current terrain, distance, attention and
activity still matter. Rates of at least 0.1 per second sustain a contact;
weaker cues consume the allowance. Brief lulls do not produce a new random
visibility roll or immediate flicker. Stronger evidence can refill the allowance.

When the allowance expires, the enemy is removed from that observer's visible
list. Remembered awareness and the last observed location survive and decay
normally, but the hidden unit's live position no longer updates. Stationary
non-firing contacts in the two distant cases above fade after roughly five
seconds even while their hex remains geometrically visible. Clearly observable
nearby contacts remain stable. Same-hex enemies retain immediate detection.

Physics updates can refresh an already observed coordinate, but cannot reset
the tracking allowance. Geometric LOS loss clears the allowance immediately;
the old published visibility list cannot restore a lost contact without fresh
acquisition. Engagement snapshots record `is_visible` and
`visual_contact_remaining_s` for diagnosing retained and lost contacts.

## Attention and squad condition

Attention gives up to 1.35 times the neutral rate at its centre, fades to neutral
at its boundary, and falls toward 0.35 behind the squad. Focus strength blends
these rates toward neutral; ordinary pre-contact strength is at most 0.6.
Switching focus temporarily reduces observation by up to 35 percent.

Observation capacity uses the square root of surviving observers relative to
`max(original_size, 10)`. Cohesion contributes 0.75–1.0, stress contributes
1.0–0.9, and morale contributes normal 1.0, cautious 0.9, pinned 0.8, panic
0.25, or combat ineffective 0.15. Movement, current suppression, and the extra
pinned spotting penalty apply only to acquisition, preserving the existing
attention-capacity model for incoming-fire stress. Inactive, surrendered, or
empty squads cannot acquire contacts, including automatic same-hex contacts.

LOS cache version 2 invalidates previous baked concealment strengths. Maps
rebuild their LOS data on the next load.

## Regression scenes

- `tests/squad_attention_regression.tscn`: distance, attention boundaries,
  terrain attenuation, activity, observation capacity, and time-step composition.
- `tests/detection_acquisition_regression.tscn`: acquisition publication, elapsed
  time, the 14/17-hex cases, multiple observers, activity cues, retained/expired
  visual contact, hidden coordinates, LOS loss, firing, and same-hex eligibility.
- `tests/pixel_terrain_los_regression.tscn`: target concealment and unique
  intervening-hex counts at multiple tile sizes, including transparent gaps.
- `tests/attention_stress_regression.tscn`: incoming-fire stress behavior.
- `tests/tracked_target_los_regression.tscn`: firing and reacquisition across LOS loss.
