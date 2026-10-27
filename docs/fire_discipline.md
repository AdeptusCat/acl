# Fire discipline

Select a friendly squad and use **Fire discipline** in its details panel.

| Setting | Automatic shooting |
| --- | --- |
| Fire at will | Engage currently observed enemies using the existing target priorities. Default for new squads and older saves. |
| Return fire | Engage a currently observed enemy within 30° of a bearing from which the squad received fire during the last eight seconds. |
| Hold fire | Observe without automatic shooting, including close-range personal defence by support-weapon crews. |

Return fire uses received-fire directions recorded at impact, including
suppression without casualties. It does not obtain a hidden attacker's identity
or position. A contact still needs the squad's own current detection and current
line of sight. Being under stress, seeing an enemy fire elsewhere, or receiving
fire from a different direction does not authorize a shot. Several incoming
directions can authorize several bearings. A different visible enemy along the
same bearing can qualify; this is a directional response, not exact attacker
identification. Each incoming bearing refreshes its own permission.

The eight-second retaliation window is separate from the existing four-second
attention pressure memory. This gives slower weapon handling time to complete
without keeping permission indefinitely after firing stops. Individual reaction,
raise, aim, cycling, reloading, protection and thermal limits still apply.
Fire discipline does not alter detection or the assigned watch sector.

## Explicit Fire orders

An explicit **Fire** order temporarily overrides discipline for its tracked
target or ordered ground hex. It does not change the saved setting or authorize
support crew sidearms against unrelated contacts. Assigned mortar fire missions
also retain their explicit firing permission and scheduled cadence. The details
panel displays **Explicit Fire order overrides discipline** while this applies.

Losing a tracked target ends that override. Completing the ground-fire round
budget returns the squad to automatic targeting under its saved discipline.
**Stop** cancels the firing order and preserves discipline. Movement also
preserves the setting while retaining the existing prohibition on firing during
movement. A subsequent explicit Fire order can override it again.

Changing discipline immediately interrupts any active burst that is no longer
permitted, including its owned automatic sound. Return-fire expiry and contact
loss are checked before each subsequent round. Already airborne rounds still
land. Observation, weapon setup, reloading, barrel changes and cooling continue;
existing crew and soldier behaviour restrictions still govern that work.

## Persistence and controls

Unit saves store the setting. Older saves and invalid saved enum values use
Fire at will. Normally inspected enemies do not reveal their discipline or
provide controls. Mission completion blocks changes. Routed, surrendered,
inactive squads and squads in close combat reject changes; pinned squads may
receive them without bypassing individual protective behaviour.

`tests/fire_discipline_regression.tscn` checks actual ammunition use, observation
preservation, directional retaliation, permission expiry, burst/audio
interruption, airborne impacts, explicit orders, crew sidearms, maintenance,
morale restrictions, mortar missions, UI permissions, layout and disk saves.
