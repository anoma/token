# Bind owner and vesting as immutables; the permissionless reinitializer takes no arguments

The V1→V2 upgrade is scheduled through V1 governance — **either** the council fast-track (`scheduleCouncilUpgrade`) **or** a voter-body quorum vote (`scheduleVoterBodyUpgrade`) — and then **executed permissionlessly** by anyone once the delay elapses (execution has no caller gate). Any value passed through `reinitializeFromV1` calldata at execution time would therefore be attacker-controlled. So `owner`, `vestingStart`, and `vestingDuration` are baked as **constructor immutables** into the V2 implementation bytecode, and `reinitializeFromV1()` takes **no arguments** (`ZeroOwnerNotAllowed` rejects a zero owner; `reinitializer(2)` prevents re-runs). Because V1's `_authorizeUpgrade` requires `newImpl == scheduledImpl`, the executor can only run the exact pre-baked implementation.

## Considered options

- **Pass `owner` / vesting as `reinitializeFromV1` arguments** — rejected: under permissionless execution the caller would choose them, letting anyone seize ownership of the token.

## Consequences

- Residual trust reduces to: **(1)** the V2 implementation is deployed with the correct immutables (`owner` = the intended Timelock; `vestingStart`/`vestingDuration` = the `Parameters` constants), and **(2)** V1 governance schedules *that exact* implementation address — the council proposing it is vetoable by the voter body, or the voter body reaches quorum on it directly.
- **Audit-checklist item:** before scheduling/execution, read the deployed implementation's immutables back on-chain and confirm the owner is the intended Timelock.
- `_INITIAL_OWNER` is a bootstrapping value only; the live owner lives in `OwnableUpgradeable` storage and may change via `transferOwnership`, so it must never be read as the current owner.
