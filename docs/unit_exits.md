# Unit exits

During an active match, entering a side's EXIT marker retires that side's unit immediately. Exit and enemy-exit prevention conditions can also designate another marker ID as an exit. The opponent's exit does not retire friendly units. Surrendered or dead units cannot exit.

Exited units retain their living soldiers and equipment. They leave the active unit and leadership groups, stop movement, fire and setup, lose command effects, and cannot take damage, occupy objectives, block routes or enter close combat. Their dimmed squad sprite remains at the exit with an **Exited** label. Exits never grant destruction credit.

Every exit adds a dated `UnitExitRecord` containing the battle, scenario, side, squad identity, hex and surviving soldier count to `Globals.battle_exits` and `Globals.session_log`. The persistent session log is written to `user://history/session_log.tres` as exits occur. Repeated entry events and loading existing records do not duplicate the log.

At scenario end, match saves include `exit_records` and `exited_units` for both sides. The player's saved roster also includes its exited survivors, with `UnitSaveData.exited` and the exit record distinguishing them from active units. Saved equipment retains the existing ammunition and loadout serialization. Loading an exited unit restores its inactive map marker and preserves exit/prevention counting; it does not generate a new exit. Older saves default to no exits.
