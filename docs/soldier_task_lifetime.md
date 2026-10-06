Soldier tasks store action state and countdowns; no production caller uses scene-tree callbacks or Node methods on them. `SoldierTask` now inherits `RefCounted`, so its six instances are released when their references are discarded. This follows Godot's [reference-counted object lifetime](https://docs.godotengine.org/en/4.7/classes/class_refcounted.html).

Living soldiers and retained casualties keep their task state. Roster replacement, save application, freeing a unit, and battlefield restart can discard the soldiers without leaving task nodes behind. An explicit task reference keeps that task alive until its holder releases it. Tasks have no reference back to their owning soldier.

Casualty records and equipment snapshots remain independent persistent resources. Releasing runtime soldiers and tasks does not discard that history. Existing regression fixtures no longer manually free tasks or retain soldiers solely for that workaround.

Regression check:

```sh
godot --headless --path . tests/soldier_task_lifecycle_regression.tscn
```

The test uses [weak references](https://docs.godotengine.org/en/4.7/classes/class_weakref.html) to observe cleanup without keeping the objects alive. Capturing references happens in separate helper scopes so iterator temporaries cannot retain a roster across an asynchronous restart.

Coverage checklist:

- [x] All six task types, display metadata, and setup/reload/acquisition countdowns.
- [x] Standalone soldier disposal and an explicitly retained task.
- [x] Repeated replacement of living and casualty rosters.
- [x] Save application and freeing an unparented unit.
- [x] Three actual Try Again restarts, including individual casualties and eliminated squads.
- [x] Runtime soldiers and tasks are released while casualty/equipment history remains saved.
- [x] All ten regression suites and parser checks for fourteen scripts.

On Godot 4.7.2, the original code retains 318 of 318 task objects after each restart and reports eleven failed assertions. With the fix, every restart retains zero of those tasks and the suite passes. Tests ran in an isolated project copy with separate user data.

Verification limits: simulation is frozen after scenario setup while the real restart flow runs. The global orphan-node monitor still grows from other unparented nodes, including the separate `SquadFireCalculator.new()` in `squad_fire_controller.gd`. Missing-debug-save messages and shutdown resource warnings remain. This regression verifies soldier/task lifetime directly rather than asserting that every project node leak is fixed.
