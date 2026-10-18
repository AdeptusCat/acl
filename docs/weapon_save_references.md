Living soldiers' match-save loadouts now serialize their original weapon resource path. Runtime roster restoration resolves that path before creating an independent runtime weapon for each soldier. Loadout copies retain the path too.

Anonymous weapons and definitions built into another resource are saved as embedded `WeaponSpec` copies. These copies retain the weapon configuration without depending on a standalone weapon file or later changes to the live weapon. Restoring and resaving an anonymous weapon keeps it embedded instead of creating a reference to an earlier match file. Direct weapon references in older or authored loadouts continue to work.

The path uses Godot's [`@export_storage`](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_exports.html#export-storage), so it is serialized without adding an Inspector field. Weapon definitions use the existing runtime duplication logic; loading does not make squads share mutable ammunition or grenade state.

Older saves that already omitted both the weapon and its path cannot recover the original equipment. Those entries retain the configured default-rifle fallback. Missing or invalid weapon resource paths report a warning and use that same fallback.

Regression checks:

```sh
godot --headless --path . tests/weapon_save_regression.tscn
godot --headless --path . tests/weapon_save_regression.tscn -- --verify-persistence
```

The first command writes fixtures under `user://matches/tests/` and `user://tests/`. The second verifies the match in a fresh Godot process, so cached in-memory loadouts cannot hide serialization failures.

Coverage checklist:

- [x] Soldier save data, squad and unit serialization, and the match save/load API.
- [x] Rifle, SMG, MG, mortar, and antitank weapon references through a disk round trip.
- [x] Multiple soldiers and multiple restored units using the same weapon definition.
- [x] Embedded weapons, live mutations after saving, and repeated saves.
- [x] Authored direct references, path-only loadouts, loadout copies, and legacy fallback.
- [x] Recovered support weapons and their replacement gunner's role.
- [x] Missing and wrong-type weapon resources.

Verification limits: this fixes weapon identity and definitions. Runtime ammunition, magazine, jam, and readiness restoration retain their existing initialization behavior. Historical casualty equipment snapshots remain separate. The scenario's calls to `spawn_units_from_match_save` are still commented out; this change does not enable a new battle-loading flow.
