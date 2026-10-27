# Enemy detection

Detection uses the terrain LOS table to select candidates. Blocking terrain still
blocks sight; attention never grants sight through an obstruction. Acquired
contacts require enough observable evidence to remain visible. Losing either
geometric LOS or visual identification requires fresh acquisition, even if
confidence and remembered awareness survive.

For an undetected candidate, the acquisition rate per simulation second is:

```
(activity_rate * distance_factor * target_transmission * intervening_transmission
    + muzzle_flash_rate) * attention * observer_condition * search_bonus
```

`distance_factor = 1 / (1 + (distance_metres / 240)^3)`. A stationary target's
passive activity rate is `1 * distance_factor`; movement replaces that passive
rate with `3 * movement_speed_ratio`. Posture and the fraction of soldiers
exposing themselves multiply this passive/movement cue. A quiet stationary
silhouette therefore receives distance attenuation twice.

Muzzle flashes use a separate cue:
`18 * sqrt(fire_recent) * distance_factor * 0.7^concealment * 0.7^hindrances`.
One actual round adds 0.1 to `fire_recent`, capped at 1, and that signal decays
with a 1.5-second half-life. The square-root response makes the first round
noticeable without requiring the whole squad to fire. Concealment and intervening
vegetation attenuate the flash less than a quiet silhouette; target posture
does not hide an emitted flash. Observer attention and condition still apply.
Movement and muzzle flashes remain stronger long-range cues. All range curves
are continuous; there is no detection-range cutoff.

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
| Muzzle-flash base rate | `18 * sqrt(fire_recent)` per second |
| Target concealment transmission | `0.35 ^ concealment_strength` |
| Intervening concealment transmission | `0.55 ^ crossed_hex_count` |
| Muzzle-flash concealment transmission | `0.7 ^ concealment_strength` |
| Muzzle-flash intervening transmission | `0.7 ^ crossed_hex_count` |
| Moving observer | 0.65 multiplier |
| Observer under fire | 0.85 multiplier |
| Pinned observer | Additional 0.6 multiplier |

For a healthy, focused observer with no intervening hindrances, a single shot
from a house at 240 m now gives over 90% acquisition probability within three
seconds, including signal decay. Sustained firing there gives over 95% within
one second. A single shot in the open at 640 m gives about 50% within three
seconds. These probabilities apply to the first unidentified contact. Firing
does not accelerate the separate visual type/strength identification process
or reveal the stress bar before identification. Blocking LOS still prevents
acquisition altogether. Silent-target tuning remains as shown below.

## Movement pace and exposure

Friendly squad details include a **Movement pace** selector. Normal uses the
existing crossing speed, Cautious uses 60%, and Fast uses 160%. Pace affects both
live movement and route travel estimates and survives saves. Old saves default
to Normal. The existing prone stance is also supported at 30% speed. Morale and
terrain speed penalties continue to apply; pace cannot bypass movement locks.

Movement visibility uses actual unscaled speed relative to the squad's base
speed, including terrain, morale and pace, clamped to 0.1–2.0. Art resolution
does not affect it. Crouching multiplies silhouette exposure by 0.7, prone by
0.4, and running by 1.1. Default standing exposure is 1.0.

Living soldiers additionally contribute according to behavior: engaging 1.0,
taking cover 0.45, cowering 0.25 and recovering 0.6. The average multiplies
posture exposure. Dead soldiers do not contribute. These are target visibility
effects, separate from suppression's effects on the observer. Firing remains a
separate cue before distance and terrain attenuation.

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

## Reacquisition and contact information

A visible observation refreshes eight seconds of search memory. While hidden,
the advantage decays with simulation time, even if the target hex remains in
geometric LOS. Reacquiring within the last observed hex receives up to 3× the
normal rate; the immediately adjacent hexes receive half that additional bonus.
Outside that area the multiplier is 1. Last known coordinates do not follow
hidden movement. The bonus still requires valid LOS and multiplies the terrain,
activity and observer factors. It never inflates an already visible contact's
tracking allowance.

New contacts initially reveal a question mark and unknown strength. Maintained
visible observation accumulates evidence at
`2 * min(sqrt(distance_factor * terrain_factor * exposure * attention * observer_condition), 1)`
per simulation second. This measures the view of an acquired silhouette;
movement, muzzle flashes and search-memory bonuses cannot reveal its details
faster independently of that view. At 1.5 evidence, the report captures the
observed unit type and activity; at 4.0, it captures a strength range in groups
of four (for example 9–12 soldiers). A clear adjacent sighting with full observer
quality takes about 0.75 seconds for type and two seconds for strength after
acquisition. Poor views and distracted observers take longer. Acquisition does
not retroactively count time spent undetected. Same-hex contacts accumulate
evidence at 2 per second even when the LOS table omits its origin hex, without
double-counting the normal observation path. Brief LOS breaks retain observed facts.

Only visible observations can update type, strength or activity. Team reports
use the most identified still-remembered observation, preferring visible and
then more recent observations when identification is equal. Hidden roster
changes cannot alter them. Type identification replaces the question mark with
the existing faction-specific rifle, MG, antitank or mortar artwork. Its idle,
moving or firing pose follows observed activity. Identified enemies also show
their current stress bar; unidentified contacts conceal it. The details
panel shows type, estimated strength and observed activity; detailed morale,
formation, rank, orders and individual soldier rosters remain concealed.
Battlefield counters omit rank text for both teams. Friendly information remains
exact. Explicit debug enemy control permits full inspection.

## Spotting diagnostics

Expand **Debug**, enable **Spotting diagnostics**, select a friendly squad, then
expand **Spotting diagnostics** in its details panel and choose a candidate.
The display shows geometric LOS, distance, target concealment, intervening
hindrance count, movement/exposure, firing, attention, observer condition,
last-position search bonus, acquisition rate, ten-second probability, tracking
allowance and identification evidence. This development-only view includes
hidden candidates and defaults off.

Production acquisition and the diagnostic display share `detection_breakdown`.
Blocked lanes display zero effective acquisition. Engagement snapshots include
search memory, sanitized contact reports and spotting factors for visible
contacts. Hidden contacts retain recorded coordinates without live diagnostics.

## Attention and squad condition

Attention gives up to 1.35 times the neutral rate at its centre, fades to neutral
at its boundary, and falls toward 0.35 behind the squad. Focus strength blends
these rates toward neutral; ordinary pre-contact strength is at most 0.6.
Switching focus temporarily reduces observation by up to 35 percent.

Explicit [watch sectors](watch_sectors.md) replace the automatic expectation
with a persistent bearing and a 60°, 120° or 180° arc. Their centre/rear
multipliers range from 1.65/0.30 for narrow sectors to 1.15/0.65 for wide ones.
Nearby detected threats, received fire and explicit fire orders can temporarily
divert attention. Acquisition snapshots preserve the watch direction and width
for individual first reactions, before the squad turns toward the new contact.

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
- `tests/contact_observation_regression.tscn`: bounded/local search memory,
  movement speed and exposure, saved pace, observation-based reports and enemy
  UI restrictions, diagnostic controls, and freed AI roster/reservation entries.
