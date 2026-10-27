# Enemy detection

Detection uses the terrain LOS table to select candidates. Blocking terrain still
blocks sight; attention never grants sight through an obstruction. An acquired
contact remains visible while LOS holds. Losing LOS requires fresh acquisition,
even if confidence and remembered awareness survive.

For an undetected candidate, the acquisition rate per simulation second is:

```
activity_rate * distance_factor * target_transmission
    * intervening_transmission * attention * observer_condition
```

The probability for an elapsed interval is `1 - exp(-rate * elapsed_seconds)`.
One successful roll acquires the contact. Failed rolls do not subtract confidence.
The match accumulates simulation time between visibility refreshes, so timer
frequency does not change the underlying acquisition rate. Shooting affects the
normal acquisition rate through recent firing; its event cannot reveal an
undetected shooter independently of attention, terrain, or observer state.

## Initial tuning

Constants live in `scenes/game/match/match_visibility_coordinator.gd`.

| Input | Value |
| --- | --- |
| Hex width | 40 metres |
| Distance factor | `1 / (1 + (distance_metres / 320)^2)` |
| Stationary target base rate | 1 per second |
| Moving target base rate | 3 per second |
| Recent firing | Adds up to 6 per second before other modifiers |
| Target concealment transmission | `0.35 ^ concealment_strength` |
| Intervening concealment transmission | `0.65 ^ crossed_hex_count` |
| Moving observer | 0.65 multiplier |
| Observer under fire | 0.85 multiplier |
| Pinned observer | Additional 0.6 multiplier |

Target concealment uses the existing terrain flags and actual opaque sprite
pixels: fields/orchards have strength 1, woods have strength 2, and buildings
have strength 3. Transparent gaps have no target concealment. Bullet cover is
not a substitute for concealment. LOS hindrance counts each intersected field
or orchard hex once, excluding the observer and target hexes. Those counts
already respect sprite silhouettes, including rays along hex boundaries.

A moving enemy at 640 metres, in the open, has a rate of 0.6 per second before
observer modifiers: mean acquisition time 1.67 seconds. Normal pre-contact
focus directly toward it raises the rate to 0.726: mean 1.38 seconds. These are
balance defaults, not guarantees or a claim of measured real-world accuracy.

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
  time, retained visibility, LOS loss, firing, and same-hex eligibility.
- `tests/pixel_terrain_los_regression.tscn`: target concealment and unique
  intervening-hex counts at multiple tile sizes, including transparent gaps.
- `tests/attention_stress_regression.tscn`: incoming-fire stress behavior.
- `tests/tracked_target_los_regression.tscn`: firing and reacquisition across LOS loss.
