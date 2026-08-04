# Recompute the council upgrade delay at execution

The [ADR-07](./07-council-backup-upgrade-module.md) guarantee — the voter body can always cancel a scheduled council upgrade — is a race between two clocks evaluated at different times. `TimelockController` stores a scheduled operation as `block.timestamp + delay` and never consults the governor again, while a cancellation computes `votingDelay + votingPeriod + minDelay` live, when the cancelling proposal is created. Computing the delay live at `scheduleUpgrade` is therefore not enough: a settings raise landing *after* the upgrade was scheduled stretches every later cancel cycle past a deadline that no longer moves.

The council can arrange precisely that. `Governor.execute` carries no access control and the timelock's executor role is open, so a Safe can bundle `scheduleUpgrade` with the execution of an already-passed, ripe proposal raising the voting period — leaving no block in between for a cancellation to be filed under the old settings.

We therefore **schedule each council upgrade as a two-call batch** whose first call is the module itself:

```
1. module.checkUpgradeDelayElapsed(scheduledAt)   reverts unless now ≥ scheduledAt + upgradeDelay(), recomputed live
2. token.upgradeToAndCall(newImplementation, data)
```

`executeBatch` runs the calls in order and reverts the whole execution if one fails, so the timelock's frozen timestamp becomes a lower bound and `checkUpgradeDelayElapsed` sets the real deadline. Nothing load-bearing is computed at schedule time any more. Because it tests the recomputed cancel cycle plus `COUNCIL_EXTRA_DELAY`, while a cancellation takes the recomputed cycle, the voter body keeps its full margin for **any** raise — the guarantee needs no bound on how far the settings may move. In the other direction a cut cannot shorten anything, since the timelock's frozen timestamp still applies; the effective deadline is the later of the two.

`scheduledAt` rides in the `checkUpgradeDelayElapsed` calldata, so it needs no storage and is covered by the operation id. It is a permissionless `view` over public state, so it is also the natural thing for off-chain monitoring to call. A revert leaves the operation `Ready` — the timelock marks an operation done only after every call succeeds — so a legitimate upgrade delayed by a raise simply executes later rather than being consumed.

## Considered options

- **Cap and floor the timing parameters, size `COUNCIL_EXTRA_DELAY` to the ranges** — also closes the race, but overrides `GovernorSettings`' setters and subclasses `TimelockController`, contradicting this layer's preference for stock audited governance code; it makes the bounds permanent (neither contract is upgradeable), and it lengthens the honest-case council path from 42 to ~97 days to buy protection against an attack that may never occur.
- **A fixed floor under the scheduled delay** — module-only and cheap, but a floor bounds our side of the race, not the attacker's: without caps the cancel cycle is unbounded, so the guarantee stays conditional on no raise exceeding the floor's envelope.
- **A permissionless `extendUpgrade()`** that cancels and re-schedules when a raise lands — works, but adds a watchtower liveness assumption: it protects the voter body only if somebody calls it in time.
- **Make the module the timelock's sole `EXECUTOR`** — puts a revocable party in the execution path, breaking the "anyone may execute" property that keeps an approved decision from being blocked by a party refusing to act.

## Consequences

- **The honest-case council path is unchanged at 42 days.** The deadline stretches only in the world where a raise actually executes after scheduling — that is, only under the attack.
- **A council upgrade is a batch operation.** Its id comes from `hashOperationBatch` and varies with the schedule timestamp, so re-scheduling after a cancel yields a fresh id unless it happens in the same block. `UpgradeScheduled` reports `scheduledAt` and an `earliestExecutableAt` that is a lower bound rather than a promise.
- **The margin remains exactly `COUNCIL_EXTRA_DELAY`.** As before, a cancel cycle begun later than that lands after the upgrade; `checkUpgradeDelayElapsed` preserves the margin, it does not widen it. Raise the parameter if the 7 days should be slack rather than a knife-edge.
- **The cancel path must still be driven promptly.** A cancel proposal left un-queued while `minDelay` is raised is recomputed at the new delay — the same assumption ADR-07 already makes about queue and execute being called without undue delay.
- **A passed proposal can stall a pending council upgrade** by raising the settings repeatedly. This creates no new power: a passed proposal can already cancel the upgrade outright.
