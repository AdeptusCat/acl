Casualties and their equipment are retained independently of battlefield nodes.

- `Globals.casualty_history.records` contains the history for both teams across battles and application restarts.
- `Globals.battle_casualties` contains casualties recorded in the current battle.
- `Unit.casualty_records` contains that unit's historical records and is included in `UnitSaveData`.
- `MatchSaveData.casualty_records` includes the battle's losses, including fully destroyed units. Loading a match imports these records into the archive without duplicating existing record IDs.

Each `CasualtyRecord` stores the soldier's name, ID, rank and role, unit designation, team, battle ID, scenario, location, timestamp, and an optional `CasualtyEquipment` snapshot. Equipment stores the weapon's name and source path, type and family, ammunition, magazine contents, grenade state, setup state, and jam state. Weapons shared by a crew have the same weapon ID within a battle; each casualty retains the state observed at their own death. These snapshots describe historical equipment and do not change when another soldier recovers and uses the weapon.

The archive saves automatically to `user://history/casualties.tres`, with writes collected at the end of the current frame. Saving writes a temporary resource before replacing the prior file. Normal application shutdown flushes pending records. An unreadable archive is reported and retained rather than overwritten. A battle reset clears the current battle list and preserves the archive.

Individual casualty selection, ranged casualties, and direct unit death all record losses. Death disables controllers and clears leadership effects while retaining the corpse and its runtime casualty roster. Clearing the battlefield frees those nodes; the resource records remain available.

Records are created from this version onward. Older saves load with an empty historical casualty list; past losses cannot be reconstructed from saves that omitted them.

Regression checks:

```sh
godot --headless --path . tests/unit_death_regression.tscn
godot --headless --path . tests/casualty_persistence_regression.tscn
godot --headless --path . tests/casualty_persistence_regression.tscn -- --verify-persistence
```

The regression scenes use separate files under `user://tests/` and preserve the normal casualty archive. The final command reads the fixtures produced by the preceding command in a fresh Godot process.
