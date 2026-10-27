# Move command routes

Normal move commands keep the clicked destination and choose the route with the lowest combined travel and exposure cost:

```text
crossing_cost = crossing_seconds / (1 + 2 × destination_cover) + 4 × crossing_exposure_seconds
cost = sum(crossing_cost)
```

Each crossing uses the squad's movement speed, destination terrain and wall or hedge crossing factor. Planning and execution share `UnitMovement.crossing_movement_factor()`. Reissued orders estimate the first crossing from the squad's actual position. The route search preserves the battlefield's directed connections and disabled cells without changing the shared graph's weights.

Exposure is crossing time multiplied by the average incoming risk at its endpoints. Incoming risk combines captured enemy weapon capability at that distance, ammunition, morale, effectiveness, line of sight, directional target cover and hindrance. Risk is normalized to 0–1. Destination cover also reduces the travel portion of route cost, so squads use covered terrain even when crossing it takes longer and no enemy has been observed. Actual movement speed and reported travel time retain the terrain slowdown. Cover comes from the destination terrain and directional LOS record; added distance still carries a positive cost. Dangerous routes remain available when they are the only connected route; defensive AI exposure budgets do not cancel an explicit move command.

Routing always uses the issuing side's observed contacts and existing six-second contact memory, even when the AI influence-map inspector uses omniscient knowledge. A hidden enemy's last observed position, range-specific firepower and effectiveness remain frozen while confidence decays. A never-observed enemy contributes no risk.

## Detection during movement

An accepted normal move watches team observations every half-second. A new contact, newly observed position or changed observed firing capability triggers reassessment only if it can threaten the remaining route. Other squads can supply the observation. Hidden movement and unrelated sightings do not trigger a search.

Alternative searches share a two-millisecond frame budget across moving squads and run backward from the destination. The squad keeps moving; the completed search can supply a route from whichever hex it reaches next. At a hex center, both the old remaining route and the alternative are checked again against current observed/remembered threats and actual crossing times. The route changes only if exposure decreases and the combined cost improves by at least two weighted seconds and 15 percent. A three-second cooldown limits repeat searches and route switches; detections during cooldown remain pending.

Rerouting preserves the clicked destination and action order. Stop, pinning, close combat, route completion and newer movement orders release the watcher. Tactical AI paths use their existing planner and do not acquire manual-move watchers. If no better valid route exists, the current move continues under the ordinary morale rules.

When engagement capture is enabled, `move_route` records the selected hex path, target, estimated travel time, exposure time, cost, risk weight and the captured contacts used to choose it. Reassessment events include `reason: detected_threat`, the disposition, previous/candidate paths and costs, exposure values and required improvement. Rule hashes include the movement, replanning and threat scripts.

Run `tests/move_path_regression.tscn` for knowledge, capability, route tradeoffs, crossing times, detections during movement, cooldowns, order cancellation, directed connections and a budgeted 600-hex search. Existing `unit_movement_regression.tscn`, `influence_positions_regression.tscn` and `engagement_capture_regression.tscn` cover execution and shared knowledge/recording behavior.
