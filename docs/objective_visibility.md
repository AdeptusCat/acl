Match startup initializes objective layers once for the selected player faction. It explicitly shows that faction's layer and hides the enemy's layer. Objective hexes for both factions remain available to gameplay and AI, and visibility changes leave objective definitions and tiles intact.

This removes the extra Allied initialization that hid Axis objectives. Explicitly showing the player layer also makes repeated setup recover from a previously hidden layer.

Assumption: the selected faction sees its own objectives in both attack and defend modes, following the active faction-to-layer mapping.

Regression checks:

```sh
godot --headless --path . tests/objective_visibility_regression.tscn
godot --headless --path . tests/objective_visibility_regression.tscn -- --allies
godot --headless --path . tests/objective_visibility_regression.tscn -- --defend
godot --headless --path . tests/objective_visibility_regression.tscn -- --allies --defend
```

Coverage checklist:

- [x] Scenario-selection signal, World startup, objective reparenting, and GameController startup.
- [x] Axis and Allied starts in attack and defend modes.
- [x] Repeated initialization, switching visible factions, and empty objective layers.
- [x] Both factions' objective hexes, authored tile preservation, and victory-condition definitions.
- [x] Parser checks and existing unit-arrival and close-combat integration regressions.

The Axis regression reports 14 failures on the original code and zero with the fix. All four faction/mode cases and both existing suites pass on Godot 4.7.2. Tests ran in an isolated project copy with separate user data.

Verification limits: headless checks verify layer visibility in the scene tree; they do not inspect rendered pixels. The fixture adds an Axis Objective A tile using the scenario's existing tileset because that scenario normally supplies Axis only a start marker. Existing missing-debug-save messages and shutdown resource warnings also occur on the baseline and remain outside this change.
