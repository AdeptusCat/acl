# Move command routes

Normal move commands keep the clicked destination and choose the route with the lowest combined travel and exposure cost:

```text
cost = travel_seconds + 4 × exposure_seconds
```

Each crossing uses the squad's movement speed, destination terrain and wall or hedge crossing factor. Planning and execution share `UnitMovement.crossing_movement_factor()`. Reissued orders estimate the first crossing from the squad's actual position. The route search preserves the battlefield's directed connections and disabled cells without changing the shared graph's weights.

Exposure is crossing time multiplied by the average incoming risk at its endpoints. Incoming risk combines captured enemy weapon capability at that distance, ammunition, morale, effectiveness, line of sight, directional target cover and hindrance. Risk is normalized to 0–1, so additional travel has a finite cost and cover alone does not justify a detour through an unthreatened area. Dangerous routes remain available when they are the only connected route; defensive AI exposure budgets do not cancel an explicit move command.

Routing always uses the issuing side's observed contacts and existing six-second contact memory, even when the AI influence-map inspector uses omniscient knowledge. A hidden enemy's last observed position, range-specific firepower and effectiveness remain frozen while confidence decays. A never-observed enemy contributes no risk. Newly issued orders capture current knowledge; an accepted path is not continuously replaced by background threat updates.

When engagement capture is enabled, `move_route` records the selected hex path, target, estimated travel time, exposure time, cost, risk weight and the captured contacts used to choose it. Rule hashes include the movement and threat scripts.

Run `tests/move_path_regression.tscn` for knowledge, capability, route tradeoffs, crossing times, move-command integration, disconnected terrain and a 600-hex route. Existing `unit_movement_regression.tscn`, `influence_positions_regression.tscn` and `engagement_capture_regression.tscn` cover execution and shared knowledge/recording behavior.
