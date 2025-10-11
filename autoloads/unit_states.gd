extends Node
class_name UnitStates

enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

# Suggested multipliers (tune in playtests)
const STATE_MOD := {
	MoraleState.NORMAL: { "acc": 1.0, "rof": 1.0, "move": 1.0 },
	MoraleState.CAUTIOUS: { "acc": 0.9, "rof": 0.8, "move": 0.9 },
	MoraleState.PINNED: { "acc": 0.5, "rof": 0.3, "move": 0.35 }, # crawl-only
	MoraleState.PANIC: { "acc": 0.0, "rof": 0.0, "move": 1.2 },   # sprint to cover/retreat
	MoraleState.COMBAT_INEFFECTIVE: { "acc": 0.0, "rof": 0.0, "move": 0.8 },
}
