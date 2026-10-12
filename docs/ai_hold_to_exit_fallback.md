# Hold objective, then exit

In a scenario's Inspector, open **AI → AI Fallback Policies** and add a
`HoldToExitFallbackPolicy` resource. Link **Hold Condition** and **Exit Condition**
to the existing resources in that scenario's **Victory Conditions** array.
Both conditions must belong to the same side, and the exit must have a lower
victory level: for example, MAJOR occupation of A and MINOR exit.

For a mission requiring occupation at the deadline, enable **Test at Scenario
End** on the hold condition. Enable it on the exit condition as well if the
match should continue after the exit quota is reached. Victory conditions at
the same level still form an AND package; the policy changes AI orders, not
victory evaluation.

The AI keeps the hold as its primary own objective until one of these occurs:

- It loses a previously secured objective for the confirmation period.
- Too few eligible combat squads remain, no eligible squad can reach the hold,
  or reaching and securing it cannot finish before the deadline, continuously
  for the confirmation period.
- The hold is unsecured and only estimated exit travel plus the withdrawal
  margin remains. This transition is immediate.

**Confirmation Seconds** defaults to 5; recovery resets that timer.
**Withdrawal Margin Seconds** defaults to 10. Travel estimates use known routes
and squad movement times. A secured objective is kept near the deadline.

Withdrawal remains committed until a new match begins. Changing ATTACK/DEFEND
or switching AI OFF/ON preserves it. Enemy denial duties do not pull withdrawing
squads back to the abandoned hold. Safe accepted moves finish before their
squad changes duty; movement and route safety checks continue to apply.

**Withdraw Entire Force** defaults to ON and includes rifles, MG, and HQ.
Squads stay assigned to the exit after they have been counted. Pinned squads
join when they recover. With this setting OFF, only the remaining distinct-unit
exit quota is assigned, using ordinary combat squads.

Add separate policies for separate hold conditions that should trigger the
same exit. An empty policy array leaves ordinary goal selection unchanged.
Invalid links or missing objective markers appear in the goal director's
diagnostics.
