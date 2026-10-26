# Mission reinforcements

The editor hierarchy is `Map → Scenarios → Mission → Reinforcements`.
The mission is the existing `Scenario` node; it retains its `Units`, objectives,
victory conditions, and AI settings.

1. Create and position ordinary units under the mission's `Units` node.
2. Select the mission or its `Reinforcements` branch and click **Add Reinforcement**
   in the Inspector. Existing missions receive the branch when needed.
3. Set the definition's team and select its units in **Unit IDs**. **Locate** selects
   the corresponding map unit. Units assigned to another definition are disabled.
4. Set **Expected Seconds** and **Variation Seconds**. For example, 900 ± 240 means
   an arrival between 11 and 19 minutes. **Near Expected** uses a triangular
   distribution; **Uniform** gives every time in the interval equal likelihood.
5. Enter an **Entry Zone** description or select an **Entry Location** map marker.
   These describe the entry point in the briefing. Each unit still arrives at its
   own authored map position; the marker does not teleport or rearrange units.
6. Enable **Staggered** to roll a delay between consecutive units. The selection
   order determines arrival order. Minimum and maximum delays are in seconds.
7. Enable **Show To Player** to show a rounded approximate ETA in the mission HUD.
   The estimate uses authored expected time, never the hidden runtime arrival roll.

The enabled Mission Reinforcements editor plugin creates persistent random unit
and definition IDs, repairs IDs on duplicated units/groups, removes missing unit
references, and enforces one definition per unit. Save the map scene to persist
these properties. Deleting a definition leaves its units under `Units`, so they
deploy normally next time. Deleting a unit removes its ID from definitions.

At mission initialization, assigned units move into a hidden, disabled runtime
holding container. They are absent from combat, visibility, objectives, AI rosters,
and initial deployment. At arrival they use the ordinary unit setup and registration
path, including command links, visibility, AI ownership, and roster refreshes.
Pending units count as future strength when deciding irreversible defeat.

Arrival time is measured in mission-clock seconds and pauses with that clock.
Zero-time groups activate during mission initialization. A mission with no initial
player units starts its clock automatically so pending reinforcements can arrive.
Arrivals stop when the match ends.

Authored timing remains on `ReinforcementDefinition`. `ReinforcementState` stores
the rolled arrival, per-unit stagger times, arrived IDs, and player estimate.
`MatchSaveData` stores independent copies of these states and elapsed reinforcement
time. The existing match save/load helpers export and restore them without rerolling;
pending units come from the authored mission, while arrived units use unit save data.
This extends the existing match persistence; it does not add a new save-game UI.

Run the integration regression with:

```sh
godot --headless --path . tests/reinforcements_regression.tscn
```
