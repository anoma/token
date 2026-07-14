# XanV2 Upgrade — Specification & Architecture

This document specifies the `XanV2` implementation and the V1→V2 upgrade of the Anoma (XAN) token. It is the audit-facing reference for the token; the domain vocabulary is in [`CONTEXT.md`](../CONTEXT.md). The governance layer that _owns_ the token (Governor, Timelock, upgrade council) is specified separately in [`docs/02-XanV2-governance.md`](./02-XanV2-governance.md); this document is token-only and records just the requirements the token places on its owner.

## 1. What V2 changes

Relative to V1, the V2 implementation:

1. **Removes** V1's in-token meta-governance (quorum voting + fast-track council) and replaces it with a single `Ownable` owner gating UUPS upgrades.
2. **Adds linear vesting** of the formerly-locked V1 balances.
3. **Adds `ERC20Votes`** vote delegation and checkpoints on a **timestamp** clock (EIP-6372), to power the future on-chain governor.

## 2. Architecture

`XanV2` is a UUPS-upgradeable ERC-20 composed of OpenZeppelin upgradeable modules:

```
XanV2
├── ERC20Upgradeable                  (balances, transfers)
├── ERC20PermitUpgradeable            (EIP-2612 permit; shares the Nonces counter)
├── ERC20VotesUpgradeable             (delegation + checkpoints, timestamp clock)
├── OwnableUpgradeable                (single owner)
└── UUPSUpgradeable                   (_authorizeUpgrade onlyOwner)
```

The token is **deliberately governance-agnostic**. All meta-governance lives outside it, in the contracts that hold `owner()`:

```
voter body ──delegated ERC20Votes──▶ Governor ──proposals──▶ TimelockController ──owns / upgrades──▶ XanV2 proxy
                                                             ▲
                                        upgrade council ─────┘  (backup path; cancellable by the voter body)
```

The owner is intended to be the `TimelockController` of an OpenZeppelin `Governor` **from the first block of V2** (see section [Governance (external)](#9-governance-external)). The token can hand governance to a different owner later via `transferOwnership` with **no token upgrade**.

## 3. Domain model & balances

See [`CONTEXT.md`](../CONTEXT.md) for definitions. Key relationships for any account:

- `balanceOf = lockedBalance + unlockedBalance`
- `lockedBalanceOf = principal − unlocked[account]` — the still-locked, non-transferable part of the principal
- `unlockedBalanceOf = balanceOf − lockedBalanceOf` — the spendable part
- `unlockableBalanceOf = max(0, vested(principal) − unlocked[account])` — what `unlock()` would release now

`principal` is fixed per account (the V1 locked balance; see section [Vesting](#4-vesting)) and never increases — V2 has **no** `lock`, `transferAndLock`, mint, or burn, so the total supply is fixed at the V1 amount. Transfers are gated to the unlocked balance in `_update`; V2 never mints or burns, so — unlike V1 — `_update` keeps no `from == 0` exemption, and the mint/burn legs are simply unreachable.

## 4. Vesting

**Source of principal.** `_principalOf(account)` reads `lockingData.lockedBalances[account]` from the **V1** ERC-7201 storage namespace, under the single mainnet V1 implementation `_XAN_V1_IMPLEMENTATION = 0x03997b568FE70E91A53c458DC19dc29e0bC2735E`. These are the locked tranches distributed by the Merkle `TokenDistributor` via `transferAndLock` (the unlocked tranche was already liquid). This is correct only because that proxy has only ever run that one implementation — a **hard precondition**.

**Schedule.** Linear between `VESTING_START` and `VESTING_START + VESTING_DURATION`:

```
vested(principal) = 0                                          if now ≤ VESTING_START
                  = principal                                  if now ≥ VESTING_START + VESTING_DURATION
                  = principal · (now − VESTING_START) / VESTING_DURATION   otherwise
```

`VESTING_START = 2026-10-31 12:00 UTC` (`1793448000`); `VESTING_DURATION = 3 · 365 days` (1095 days, no leap adjustment). The schedule is baked into the implementation as immutables (`_VESTING_START`, `_VESTING_DURATION`).

**`unlock()`.** Moves an account's currently-unlockable amount from locked to unlocked by raising the cumulative `unlocked[account]` to `vested(principal)`. It reverts `NothingToUnlock` if nothing new has vested (`vested` is monotonic and capped at `principal`, so `unlocked` never exceeds `principal`). Emits `Unlocked`.

**Rounding.** `vested` uses integer division, so an account is under-vested by at most a dust amount mid-schedule; at or after `vestingEnd` the formula returns exactly `principal`, so no dust is stranded at completion.

## 5. Voting (`ERC20Votes`)

- **Voting power = the full balance**, including locked, unvested principal — voting still requires (self-)delegation.
- **Clock:** `clock() = block.timestamp`, `CLOCK_MODE() = "mode=timestamp"` (EIP-6372). A consumer governor denominates `votingDelay`/`votingPeriod` in seconds.
- **Clock invariant (binds future upgrades).** The external `XanGovernor` pins its own clock to the timestamp and reads the token's `getPastVotes`/`getPastTotalSupply` at second-scale timepoints. Any current or future token implementation the governor reads **must** keep `CLOCK_MODE() == "mode=timestamp"`. An upgrade that switched the token to a block-number clock would make the governor query second-scale timepoints against block-scale checkpoints — returning wrong vote weights or reverting (`ERC5805FutureLookup`) and bricking governance. A token upgrade that changes the clock mode must therefore be paired with a matching governor migration.
- **Total-supply checkpoint** is seeded once at the upgrade so quorum is non-zero. `getPastTotalSupply` is therefore valid only for timepoints at/after the upgrade.
- **Nonces** are shared between `permit` (EIP-2612) and `delegateBySig` via the single `NoncesUpgradeable` counter (the `nonces` override resolves the `ERC20Permit`/`Nonces` diamond).

## 6. Ownership & upgradeability

- `_authorizeUpgrade` is `onlyOwner` — the sole upgrade gate.
- The constructor takes `(initialOwner, vestingStartTimestamp, vestingDuration)`, stores them as **immutables** (in bytecode, not storage), rejects a zero owner (`ZeroOwnerNotAllowed`), and disables initializers.
- `reinitializeFromV1()` takes **no arguments** (`reinitializer(2)`); it initializes `ERC20Votes` + `Ownable` (installing `_INITIAL_OWNER`), seeds the voting total-supply checkpoint, and emits `VestingScheduled`. The argument-free design is the mitigation for permissionless execution.
- `_INITIAL_OWNER` is a **bootstrapping value only**; the live owner lives in `OwnableUpgradeable` storage and may change via `transferOwnership`. Never read the immutable as the current owner.

## 7. The V1→V2 upgrade procedure

V1 keeps the authority to perform the upgrade; it can be scheduled through **either** V1 path:

- **Council fast-track** — the V1 `governanceCouncil` (a Safe) calls `scheduleCouncilUpgrade(implV2)`, vetoable by the V1 voter body. `script/PrepareXanV2Upgrade.s.sol` deploys the governance stack and prepares `implV2`; the council Safe then schedules it in a **separate transaction** (a `forge script` cannot broadcast as the Safe).
- **Voter-body quorum** — token holders lock + `castVote(implV2)` to quorum, then `scheduleVoterBodyUpgrade()`.

Both end the same way: after `DELAY_DURATION` (14 days) the upgrade is **executed permissionlessly** (anyone may call `upgradeToAndCall(implV2, reinitializeFromV1())`; `script/ExecuteXanV2Upgrade.s.sol`). V1's `_authorizeUpgrade` requires `newImpl == scheduledImpl`, so only the exact scheduled implementation can be installed.

End-to-end:

1. `script/PrepareXanV2Upgrade.s.sol` deploys the governance stack (so the `timelock` owner exists), then deploys the V2 implementation with `constructorData = abi.encode(timelock, VESTING_START, VESTING_DURATION)` (via `prepareUpgrade`), baking the owner and schedule into bytecode; it returns `implV2`.
2. Schedule **that exact** `implV2` through one of the two V1 paths (the council path is a Safe transaction).
3. Wait out the delay; anyone executes (`script/ExecuteXanV2Upgrade.s.sol`); `reinitializeFromV1()` runs once.

## 8. Storage layout & compatibility

- **V1 namespace** (`erc7201:anoma.storage.Xan.v1`, slot `0x52f7…d200`) is read by V2 via inline assembly at the hardcoded location. Only `lockingData` is read; the `votingData`/`councilData` structs are retained in `ImplementationData` **solely to preserve the V1 layout** (their logic is gone).
- **V2 namespace** (`erc7201:anoma.storage.Xan.v2`, slot `0x52ac…a600`) holds only `unlocked[account]`.
- Immutables are stored in bytecode, not storage, so they add no layout risk.
- OZ upgrade-safety annotations: `@custom:oz-upgrades-from XanV1`, plus the documented `oz-upgrades-unsafe-allow` exceptions for the constructor, immutables, and reinitializer ordering.

## 9. Governance (external)

The governance layer that owns the token — `XanGovernor`, its `TimelockController`, and the `XanUpgradeCouncilModule` — is specified in [`docs/02-XanV2-governance.md`](./02-XanV2-governance.md). The requirements the token places on its owner:

- `owner()` is an OpenZeppelin `Governor` + `TimelockController` from the first block of V2.
- The Governor reads the token's `ERC20Votes` on the timestamp clock; the **voter body** is the delegated electorate.
- An **upgrade council** module can initiate upgrades as a liveness fallback if the voter body is inactive (on a longer, cancellable timeline than a voter proposal); the voter body can always cancel the council's upgrades and replace the council.

## 10. Parameters

| Constant                                | Value                                                                |
| --------------------------------------- | -------------------------------------------------------------------- |
| `SUPPLY`                                | `10^28` (10 billion · 1e18)                                          |
| `MIN_LOCKED_SUPPLY`                     | `SUPPLY / 4`                                                         |
| `QUORUM_RATIO_NUMERATOR / _DENOMINATOR` | `1 / 2`                                                              |
| `DELAY_DURATION`                        | `14 days`                                                            |
| `VESTING_START`                         | `1793448000` (2026-10-31 12:00 UTC)                                  |
| `VESTING_DURATION`                      | `3 · 365 days`                                                       |
| `_XAN_V1_IMPLEMENTATION`                | `0x03997b568FE70E91A53c458DC19dc29e0bC2735E`                         |
| V1 storage slot                         | `0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200` |
| V2 storage slot                         | `0x52ac9b9514a24171c0416c0576d612fe5fab9f5a41dcf77ddbf6be60ca9da600` |
