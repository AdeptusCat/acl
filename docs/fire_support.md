# Fire support

Click a support weapon icon, click a target hex, then press **Enter** to assign a fire mission. Each onboard mortar or offboard battery has its own mortar/howitzer icon showing remaining rounds; active missions are highlighted. Clicking the same icon again closes the panel; clicking another icon switches batteries. Every battlefield click while the panel is open selects or replaces the target hex. **F** toggles the currently selected asset. Infantry selection is preserved. Use **Locate mortar** to center an onboard mortar.

- **Quick:** 3 rounds, as fast as the real weapon can prepare and reload.
- **Standard:** 6 rounds, at least 4 seconds between launches.
- **Harassing:** one round every 15–25 seconds until **Cease fire** or ammunition exhaustion.

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
