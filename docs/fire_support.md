# Fire support

Click a support weapon icon, click a target hex, then press **Enter** to assign a fire mission. Each onboard mortar or offboard battery has its own mortar/howitzer icon showing remaining rounds; active missions are highlighted. Clicking the same icon again closes the panel; clicking another icon switches batteries. Every battlefield click while the panel is open selects or replaces the target hex. **F** toggles the currently selected asset. Infantry selection is preserved. Use **Locate mortar** to center an onboard mortar.

Active weapon icons fill from left to right toward the next shell launch, with a small countdown. Offboard fill tracks the response delay and launch cadence; onboard fill follows crew setup, reload, aiming and scheduled pauses. Crew countdowns account for current stress and crew efficiency and may change when those conditions change. The fill resets at launch and disappears when the mission completes or is ceased; it does not track airborne shells.

After a mission is assigned, its icon displays **rounds remaining / mission total**, such as **3/6**, with **Ammo 24** underneath for total battery ammunition. Both counts update after each launch. The denominator stays fixed, and completed missions show **0/total**. Assets without a mission show their ammunition count.

Target shapes use direct battlefield gestures:

- **Point:** click a hex. Small pointer movements are ignored.
- **Line:** drag from the first hex to the last. Fire sweeps along the crossed hexes in that order, repeating when needed.
- **Area:** hold **Shift** and drag from the center to the edge, or select the **Area** button and drag without a modifier. Circular radius is limited to 1–3 hex spacings; only battlefield hex centers inside the circle are eligible. Rounds visit shuffled hexes without repeats until every hex has been covered.

Point, Line and Area buttons provide visible alternatives to the gestures. Releasing the mouse prepares the footprint; it never fires immediately. **Enter / Fire mission** confirms. Another click or drag replaces the preview. **Escape** cancels the preview first; a second Escape closes the panel. Releasing a drag over the HUD cancels it.

The live preview shades eligible hexes, shows line sweep direction or the area circle, highlights friendly troops inside it and reports rounds versus covered hexes. Broad footprints with fewer rounds than hexes show **sparse coverage**. The total mission ammunition is unchanged by target shape. Each round resolves through the existing single-hex HE system.

Mission settings are independent:

- **Length:** 15 seconds, 30 seconds, 1 minute, 2 minutes or 5 minutes, measured from the first shell launch. Call-in and initial crew preparation do not consume the firing window.
- **Intensity:** Intense (5 seconds per shot), Steady (10 seconds), Harassing (20 seconds) or Sporadic (40 seconds). These are minimum launch intervals; crew readiness and reload time can make them longer. Onboard crews prepare during the interval rather than waiting for it before reloading.

The preview shows the maximum planned rounds for the selected window and intensity, capped by available ammunition and weapon reload speed. Missions stop when their time expires, their planned rounds have fired, ammunition runs out or fire is ceased. Delayed shells are never launched after the firing window closes. Unfired planned rounds remain in battery ammunition; the icon's mission count reaches zero when the order ends.

Offboard batteries have an authored **gun_count** (1–24). **Guns firing** in the panel selects how many participate in the next mission, up to that battery's available count. Existing offboard batteries default to one gun.

Onboard mortar squads with the same **team, company and platoon** form one battery automatically. Their card stack represents the platoon's guns, and the battery ammunition counter sums their surviving weapons. Other companies and platoons stay separate. Gun selection assigns only the chosen number of crews that can reach the entire footprint. Each gun keeps its own ammunition and crew preparation; ammunition is not transferred between squads.

Selected onboard crews prepare together before each volley, then launch their own shells with a short stagger through the native firing system. Cease fire stops every assigned squad. A crew that becomes unavailable or receives another order drops out; remaining participants continue, and replacement orders are preserved. **Locate mortar** centers an active squad from the platoon.

With multiple guns selected, intensity is shown in seconds **per volley**. Each participating gun launches one shell in a staggered group lasting roughly half a second. Every shell follows the Point/Line/Area distribution and resolves independently. The next volley interval is measured from the first gun so stagger does not accumulate into cadence drift. The icon says **Volley** during the launch group, then resumes its next-volley countdown.

**rounds** is shared ammunition for the whole battery, not ammunition per gun. Planned ammunition scales with the selected gun count and remains capped by this shared stock; the last volley can be smaller if ammunition is low. Cease fire or the duration limit cancels guns that have not launched yet, without spending their shells. Airborne shells still land. Changing the selected gun count affects the next mission, not an active order.

Onboard missions use the existing gunner, ammunition, crew, setup, reload, projectile and impact systems. There is no additional call-in delay. Moving mortars halt and deploy; broken, surrendered, eliminated or close-combat squads cannot accept missions. Another fire order interrupts the support mission. Completed or ceased batteries remain silent until another fire order. Airborne rounds still land.

Targets need not be visible to the mortar. The preview identifies friendly observation and friendly troops in the target hex. Existing HE resolution affects the struck hex, so the mission marker represents that hex rather than promising damage to adjacent cells.

Mortar and artillery shells and explosions remain visible above fog of war, including enemy fire. These effects do not reveal units or terrain visibility.

Offboard rounds approach from the direction of the player's start hex, with their origin beyond the battlefield edge. Configured flight times are preserved. A target on the start hex uses the direction away from the enemy start as its fallback.

Offboard support is assigned per scenario through **offboard_batteries**, an array of **OffboardBattery** resources. Each definition specifies its faction, weapon, rounds, response delay and flight time. Definitions are copied into independent runtime batteries; they do not create battlefield counters, observers or objectives. Existing scenario balance is unchanged unless a designer assigns support.

In the battery inspector, **Weapon** is a dropdown of WeaponSpec resources in the **Mortar** and **Howitzer** families. It discovers resources across the project, including new weapons when the dropdown is opened. Selection uses the editor's normal undo and resource saving.

Examples:

- `res://resources/fire_support/example_81mm_battery.tres`
- `res://resources/fire_support/example_105mm_battery.tres`

Only HE missions are currently offered. Fire-support orders and offboard ammunition are match-local and are not restored by the existing match-save format.

Validation: `godot --headless --path . tests/fire_support_regression.tscn`. Add `-- --capture` with a rendering display to save `/tmp/acl-fire-support-hud.png`.
