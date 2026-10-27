# Area suppression

Select a stationary squad, hold right click over a battlefield hex, choose
**Suppress**, and release. The squad keeps firing into that hex until **Stop**,
a replacement movement or fire order, routing, surrender, loss of line of sight,
friendly entry into the target area, or exhaustion of usable ammunition.

The target is one hex: approximately a forty-metre area. No detected enemy is
required. Soldiers fire into the position rather than following a contact.
An empty hex still consumes ammunition. Ordinary **Fire** retains its tracked
target or fifty-round ground-fire behaviour; **Suppress** continues without that
round limit.

## Effects and limits

- Actual incoming rounds apply the existing stress, under-fire recovery penalty,
  attention pressure and protective behaviour to occupants of the target hex.
  There is no guaranteed pin or immediate movement lock.
- Area fire uses 25% of normal hit probability, while retaining the existing
  incoming-volume suppression calculation. Casualties remain possible; spreading
  fire across a position is less precise than aimed fire.
- Arrival determines who receives the effects. Hidden occupants and troops
  entering the area can be affected. Units that leave before impact are not
  followed. Impacts do not create contact or identification records.
- Individual reactions, raising, aiming, cycling, reloads, crew efficiency,
  protective behaviour, automatic burst pauses, cooling and barrel changes all
  remain in effect. Suppress does not force continuous machine-gun fire.
- The order uses small arms with bullet ammunition. Rifle grenadiers reload
  ordinary ammunition when necessary. Mortars and anti-tank launchers retain
  their existing Fire/fire-mission commands. Support crews retain their gun
  duties and existing short personal-weapon range restrictions.
- Range and current line of sight are required. The squad's own hex, off-map
  areas and friendly-occupied areas are rejected. Friendly entry or blocked LOS
  ceases further rounds; bullets already airborne still arrive.

## Controls and attention

Suppress is an explicit order and temporarily overrides **Hold fire** and
**Return fire** for its selected area. Cancelling it restores automatic fire
under the saved discipline. Changing discipline alone does not cancel the order.
Use **Stop** to cease.

Squad details display **Suppress (x, y) · Stop to cease** and explain the
discipline override. The selected squad shows an orange target-hex outline and
a dashed line to the area. This marker represents the order, including when no
enemy is detected, and supplies no confirmation that the hex is occupied.
Normal enemy inspection reveals no enemy suppression orders.

The watch assignment is retained. As with other explicit Fire orders, actual
attention can turn toward the ordered area. Suppression cannot bypass a
soldier's cowering, cover, weapon setup or cooling restrictions. Mission-end and
enemy-control restrictions also apply to Suppress.

`tests/area_suppression_regression.tscn` exercises sustained ammunition use,
individual reactions, weapon cadence, hidden and moving occupants, airborne
rounds, friendly safety, LOS/range restrictions, cancellation, ordinary-ammunition
reloads, casualty accuracy, command permissions and marker geometry.
`tests/command_interaction_regression.tscn` exercises Suppress and Stop through
actual right-click wheel input.
