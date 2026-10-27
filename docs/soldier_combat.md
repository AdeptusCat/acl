# Individual soldier combat

Squad morale, soldier behavior, and weapon handling are separate. The squad
provides morale and recent incoming fire; each living soldier independently
chooses sustained periods of engaging, taking cover, cowering, and recovering.
Weapon handling tracks lowered, ready, preparing, firing, cycling, restoring
aim, reloading, and deploying states.

## Reaction and readiness

Each soldier has a stable reaction tendency and a private seeded random stream.
A contact starts one reaction/aim task. Repeated target evaluation preserves
progress. New detections wake automatic selection immediately; a current target
receives a modest retention preference during periodic reconsideration.

Ready soldiers do not raise the weapon again. Movement lowers readiness;
stationary soldiers restore it while watching. Recognition overlaps raising and
initial aim. Close contacts (up to two hexes) shorten initial aim; peripheral
attention increases reaction time. The detection track preserves pre-contact
attention briefly so automatically turning attention toward a new contact does
not erase the initial peripheral reaction penalty. Switching between nearby
bearings requires less correction than switching to the opposite side.

Healthy, ready soldiers facing a close frontal contact have an initial reaction
spread of approximately 0.25–1.7 seconds, with most responding within 1.2 seconds.
These are initial balance values, not fixed firing waves. Actual readiness,
range, concealment, morale, and the target remaining visible still matter.

## Behavior under pressure

A pinned soldier initially has a 25% chance to engage, 45% to take cover, and
30% to cower. Engaging periods last 0.6–1.8 seconds, cover 0.6–1.6 seconds,
and cowering 1.5–3.5 seconds. Returning from shelter includes an individual
0.25–0.8 second recovery period. Panic/combat ineffectiveness sustain cowering.
Normal/cautious soldiers can also briefly take cover under actual incoming fire.
Decisions occur at timed state boundaries, not every frame.

Sheltering stops firing preparation and remaining burst rounds, preserving
ammunition and deployment work. A brief sight-picture correction is retained
for return to engagement. Handling speed is 1.0 normally, 0.95 when cautious,
and 0.9 when pinned; suppression primarily changes exposure behavior. Crew
availability still scales work in progress. Deployment retains its existing
morale progression rates. Reload duration is no longer divided by morale ROF
and slowed a second time. A magazine is refilled only when reload work finishes.

## Follow-up fire

| Weapon | Raise | Initial aim | Action cycle | Reaim | Burst pause |
| --- | ---: | ---: | ---: | ---: | ---: |
| Kar98k / Springfield 1903 | 0.7 | 0.9 | 0.9 | 0.9 | 0 |
| Enfield No. 4 | 0.7 | 0.9 | 0.7 | 0.8 | 0 |
| M1 Garand | 0.7 | 0.8 | 0 | 0.65 | 0 |
| M1 Carbine | 0.6 | 0.65 | 0 | 0.5 | 0 |
| BAR | 0.4 | 0.8 | 0 | 0.45 | 0.35 |
| MG34, bipod | 0.3 | 0.7 | 0 | 0.35 | 0.3 |
| MG34, tripod | 0.2 | 0.6 | 0 | 0.25 | 0.4 |
| M1919A4 | 0.2 | 0.6 | 0 | 0.25 | 0.5 |
| MP40 / M3 | 0.6 | 0.4 | 0 | 0.35 | 0.4 |

Values are seconds. Aim variation is proportional (default ±20%). Bolt-action
cycling and reaiming are sequential. Semi-automatic follow-up is bounded by
mechanical RPM. Automatic burst pauses overlap correction through `max(pause,
reaim)`, with rounds inside each burst following RPM. Setup and rifle-grenade
preparation remain separate weapon requirements.

## Scheduling and observation

The controller updates each soldier once in a synchronous pass. Active bursts
carry remaining rounds and elapsed time across updates. Each muzzle event
spends one round, updates recent firing, emits audio/visuals, and schedules its
own later impact. Losing the target, moving, taking cover, incapacitation, or
unsafe support fire stops remaining burst rounds. Already airborne rounds land
independently of subsequent shooter behavior or death.

Soldier rows show protective behavior and weapon recovery states. Engagement
captures include both state machines and their timing, without consuming the
soldier's random stream. Onboard mortar mission timing and crew preparation
continue to gate actual muzzle events.

The new focused regression scene is `tests/soldier_combat_regression.tscn`.
Existing setup/crew, fire-support, tracked-LOS, death, save, task-lifecycle, and
capture scenes exercise integration with the wider game.
