# Vest the V1 locked balances on the upgrade instead of releasing them

V1 records locked balances per-implementation, so upgrading the proxy would read a fresh, empty locking namespace and **instantly free every `transferAndLock`-locked balance** (mostly team / investor / foundation allocations) at the V1→V2 upgrade. To avoid that liquidity shock, V2 instead re-reads the V1 implementation's locked balances as a fixed per-account *principal* and releases it **linearly over three years** (`VESTING_START` = 2026-10-31 12:00 UTC, `VESTING_DURATION` = 3·365 days), unlockable via `unlock()`. Until unlocked, principal stays non-transferable but still counts toward `balanceOf` and voting power.

## Considered options

- **Free on upgrade** (V1's default behavior) — rejected: dumps the entire locked supply into circulation at once.
- **Cliff vesting** — rejected in favor of continuous linear release.

## Consequences

- **Load-bearing precondition.** Principal is read only from the single mainnet V1 implementation `0x03997b568FE70E91A53c458DC19dc29e0bC2735E`. This captures all locked balances **only because that proxy has only ever run that one implementation** (V1→V2 is its first upgrade). Verify the proxy's implementation history on-chain before executing the upgrade; a forgotten earlier implementation would make those balances liquid with no vesting.
- The vesting start and duration are baked into the implementation bytecode as immutables (see [ADR-02](./02-bind-owner-and-vesting-as-immutables.md) for the permissionless-upgrade hardening), not passed at upgrade time.
