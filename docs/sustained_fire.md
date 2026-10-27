# Sustained automatic fire

The bipod MG34, tripod MG34, M1919A4 and BAR use controlled bursts with observation
pauses. RPM still controls round spacing inside a burst. Other weapons retain
their existing cadence unless `sustained_pause_s` is configured above zero.

## Initial profiles

| Weapon | Controlled rounds | Observation pause | Rapid rounds | Rapid pause | Controlled rounds in first minute |
| --- | ---: | ---: | ---: | ---: | ---: |
| MG34, bipod | 4 | 2.0 s | 7 | 0.35 s | 100 |
| MG34, tripod | 7 | 2.2 s | 12 | 0.4 s | 162 |
| M1919A4 | 6 | 3.5 s | 10 | 0.5 s | 91 |
| BAR | 3 | 2.1 s | 5 | 0.45 s | 68 |

Bursts vary by one round; pauses vary by ±15% using the soldier's private random
stream. These are initial game tuning values. The measured rates use a ready,
fully crewed gun against a stationary unsuppressed target at four hexes, with
real magazine capacities, reloads and handling at 60 updates/second. Pressure,
crew losses, opportunities and accumulated heat change actual output.

## Opportunities and suppression

A currently visible enemy within two hexes, or a moving enemy in an unobscured
open sight line, permits rapid fire. Pinned/panicked/combat-ineffective targets
do not trigger this mode. An exposed sight line requires both zero target
concealment and zero intervening hindrance. Ground fire defaults to controlled
fire, without inventing a visible enemy.

Each physical gun has a three-second rapid-fire allowance, with an eighteen-second
recovery. Changing targets cannot reset it. A new opportunity can shorten an
existing observation pause to the rapid pause; a burst already underway can
finish when the allowance expires. Rapid fire requires heat below the soft
threshold. Controlled fire at already suppressed targets lengthens pauses by
75%. Aiming, setup, ammunition, LOS, safety and soldier behavior still gate fire.

Observation pauses count down during reloads, cover and movement. They overlap
mechanical recovery rather than stacking another full delay after it.

## Heat and barrels

Heat represents equivalent rounds above ambient, not a measured temperature.
Each emitted round adds heat. All carried barrels continuously lose heat during
reloads, movement, cover, deployment and idle time. Only new physical weapon
instances start cold. Reloading, losing a target and replacing a gunner preserve
the runtime state. Match save/load retains its existing weapon-definition
semantics; this change does not add a mid-engagement runtime save format.

| Weapon | Heat per round | Cooling per second | Soft threshold | Hard stop | Resume threshold | Spare barrels |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MG34, either mount | 1 | 1 | 160 | 250 | 110 | 2 |
| M1919A4 | 1 | 1.25 | 280 | 450 | 200 | 0 |
| BAR | 1 | 0.8 | 70 | 110 | 45 | 0 |

At the soft threshold the gun loses rapid fire, shortens bursts and progressively
lengthens pauses up to three times normal. The hard threshold interrupts even an
ongoing burst. A locked barrel must cool to its lower resume threshold before
firing again. Unfired rounds are retained and airborne rounds resolve normally.

Both MG34 mounts have identical barrel heating and cooling. Their burst profiles,
feed capacities and support crew requirements account for their different roles.
At soft heat the MG34 selects the coolest spare at or below the resume threshold.
A barrel change requires five seconds of handling work with an available helper;
missing help and support crew reduce work speed. The removed barrel keeps its
heat and cools independently. Hot spares cannot produce an unlimited succession
of cold barrels. Spare count and change time are weapon/loadout settings.

The gunner and one living, engaging loader/assistant are occupied during the
change. The helper cannot simultaneously fire their personal weapon. A cowering
helper slows existing work; a sheltering gunner pauses it. Movement and close
combat suspend barrel handling. Reloading and aiming cannot consume the same
update as barrel-change work. M1919A4 and BAR have no quick barrel-change action;
they manage heat through pauses and cooling.

## Observation and verification

Soldier rows distinguish observing between bursts, cooling a barrel and changing
a barrel. Engagement captures include each barrel's heat, installed barrel,
cooling lock, change progress, helper assignment, pause and rapid allowance.

Run `godot --headless --path . tests/automatic_fire_regression.tscn` for thermal
limits, barrel rotation, crew interruption, actual opportunity response, cyclic
spacing, ammunition accounting, 30/60/120 Hz comparisons and five-minute fire
checks for all four profiles. Weapon-state regression also verifies heat and
pause preservation through the production re-crewing path. Existing audio,
soldier reaction, weapon setup, fire support and tracked-LOS tests cover the
surrounding scheduler.
