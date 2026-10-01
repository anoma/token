# XanV2Vesting — Specification & Architecture

This document specifies `XanV2Vesting`, the contract that vests XAN for eligible recipients whose addresses the genesis distribution of XAN V1 did not contain. It copies the vesting schedule and the unlock mechanism of the token, which [`01-XanV2-upgrade.md`](./01-XanV2-upgrade.md) specifies, and it lives outside the governance layer of [`02-XanV2-governance.md`](./02-XanV2-governance.md). The domain vocabulary lives in [`../CONTEXT.md`](../CONTEXT.md).

## 1. Purpose

The genesis distribution of XAN V1 gave each eligible recipient that submitted an address its locked tranche, through the Merkle `TokenDistributor` and `transferAndLock`. A few eligible recipients did not submit an address, so the distribution does not contain them. `XanV2` vests only the principals that V1 recorded (see section [Vesting](./01-XanV2-upgrade.md#4-vesting)), so it cannot vest their tranches.

The council multisig moves these tranches into `XanV2Vesting`, and each recipient unlocks its tranche there over time, on the same schedule and with the same `unlock()` as the holders in the token. A principal is the locked tranche that the recipient missed; if the recipient was also owed a liquid tranche, the council multisig sends that directly with an ordinary transfer.

**No new tokens.** `XanV2` cannot mint, so the supply stays fixed. `XanV2Vesting` only passes existing XAN from the council multisig to the recipients.

## 2. Architecture

```mermaid
flowchart LR
    council([Council multisig,<br/>owner])
    recipient([Recipient])
    vesting[XanV2Vesting proxy]
    token[(XanV2 proxy)]

    council -->|transfer XAN| vesting
    council -->|addRecipients / withdrawSurplus / upgradeToAndCall| vesting
    recipient -->|unlock| vesting
    vesting -->|transfer vested XAN| recipient
    vesting -.->|read schedule| token
```

`XanV2Vesting` is a UUPS proxy (`ERC1967Proxy`) with OpenZeppelin `OwnableUpgradeable`, and it keeps its state in the ERC-7201 namespace `anoma.storage.XanV2Vesting`. It holds its XAN like any other account, and `unlock()` pays recipients with ordinary token transfers. Besides its own balance, it reads only the vesting schedule from the XAN token, once, when the implementation is constructed.

It exposes the vesting interface of `IXanV2` except `implementation()` and `initialOwner()`, with `unlockedAmountOf` in place of `unlockedBalanceOf` (see section [Domain model & balances](#3-domain-model--balances)). It reuses the `VestingScheduled` and `Unlocked` events of `IXanV2` and the `NothingToUnlock` error of `XanV2`.

## 3. Domain model & balances

The relationships mirror those of `XanV2` (see section [Domain model & balances](./01-XanV2-upgrade.md#3-domain-model--balances)), with the principal in place of the token balance:

- `principalOf` — the principal that the owner added; fixed once added
- `lockedBalanceOf = principal − unlocked[account]` — the part of the principal not unlocked yet
- `unlockedAmountOf = unlocked[account]` — the part that the contract has transferred to the account
- `unlockableBalanceOf = max(0, vested(principal) − unlocked[account])` — what `unlock()` would transfer now
- `principalOf = lockedBalanceOf + unlockedAmountOf`

**`unlockedAmountOf` is not a balance.** In `XanV2`, `unlockedBalanceOf` is the spendable balance, `balanceOf − lockedBalanceOf`. `XanV2Vesting` holds no balance per account, because unlocked XAN leaves the contract. `unlockedAmountOf` returns the amount transferred so far, which counts in the balance of the account in the token, where it is freely transferable.

Three totals cover all recipients:

- `totalPrincipal()` — the sum of all principals
- `totalLockedBalance()` — the sum of all locked balances: the XAN that the contract must hold to pay every remaining unlock
- `totalUnlockableBalance()` — the XAN that the contract must hold now so that every recipient can unlock: `vested(totalPrincipal) − Σ unlocked`, which exceeds the sum of the unlockable balances by at most 1 wei per recipient

## 4. Vesting

**Schedule.** The constructor of the implementation copies `vestingStart()` and `vestingEnd()` from the XAN token into immutables, so every recipient vests on the schedule of `XanV2` (see section [Vesting](./01-XanV2-upgrade.md#4-vesting)):

```
vested(principal) = 0                                                               if now ≤ vestingStart
                  = principal                                                       if now ≥ vestingEnd
                  = principal · (now − vestingStart) / (vestingEnd − vestingStart)  otherwise
```

A recipient added after `vestingStart` can unlock the part that has already vested at once.

**`unlock()`.** Works as in `XanV2`: it raises the cumulative `unlocked[msg.sender]` to `vested(principal)` and reverts `NothingToUnlock` if nothing new has vested. It then transfers the difference from the XAN balance of the contract to the caller and emits `Unlocked`. If the balance is too low, it reverts `TokenBalanceInsufficient` and records nothing (see section [Funding](#6-funding)). It acts only for `msg.sender`, so a recipient calls it from the address that has the principal.

**Rounding.** As in `XanV2`: integer division under-vests by at most a dust amount mid-schedule, and at or after `vestingEnd` the full principal vests.

## 5. Recipients

`initialize(initialOwner, recipients)` adds the initial recipients, and the owner adds more in batches with `addRecipients(Recipient[])`. A `Recipient` is an `account` and its `principal`. The list is append-only: a principal cannot change and cannot be removed. An entry reverts the whole batch if:

- the account is the zero address (`ZeroAccountNotAllowed`), or the principal is zero (`ZeroPrincipalNotAllowed`);
- the account is `XanV2Vesting` itself (`SelfRecipientNotAllowed`) or the XAN token (`TokenRecipientNotAllowed`), neither of which can call `unlock()`;
- the account already has a principal here (`PrincipalAlreadySet`).

Each added principal emits `PrincipalAdded`. `getRecipients()` returns all recipients with their principals, in the order of addition.

An account can also have a principal in the XAN token. The two principals vest independently, and `XanV2Vesting` does not read the one in the token.

## 6. Funding

The council multisig funds the contract with ordinary XAN transfers; the contract has no deposit function. The owner can add principals before the XAN arrives, so the contract can hold less than `totalLockedBalance()` for a time. This is accepted:

- **Underfunded.** An `unlock()` that needs more XAN than the contract holds reverts `TokenBalanceInsufficient` and records nothing. The recipient keeps its unlockable amount and calls again after the next top-up, so no vesting is lost. While the balance is low, the unlocks that land first are paid first.
- **Top-ups.** The council multisig tops up the contract periodically, so that vesting continues and recipients can unlock (see [Top-up amount](#top-up-amount)).
- **Surplus.** `withdrawSurplus(receiver, value)` lets the owner take the XAN above `totalLockedBalance()`, for example after an overpayment, and emits `SurplusWithdrawn`. A larger `value` reverts `SurplusInsufficient`, so `withdrawSurplus` cannot take XAN that a locked balance needs.

### Top-up amount

Two scripts compute the XAN to send now, from the live state of `XanV2Vesting` and the XAN token. Both send nothing, return zero when the balance is already enough, and cover the recipients added so far:

- `script/ComputeXanV2VestingTopUpUntil.s.sol` covers every unlock until a timestamp, usually the time of the next top-up. It reads `totalUnlockableBalance()` at that timestamp. Run it with `just vesting-top-up-until <xan-v2-vesting> <timestamp> <chain>`.
- `script/ComputeXanV2VestingTopUpFull.s.sol` covers every present and future unlock. Run it with `just vesting-top-up-full <xan-v2-vesting> <chain>`.

For example, 3,650,000 XAN of principals vest about 3,333 XAN per day, so a top-up until 30 days from now adds about 100,000 XAN to what recipients can unlock now.

## 7. Voting

`XanV2Vesting` holds the locked XAN and cannot delegate it, so a locked principal has no voting power. This differs from `XanV2`, where voting power includes the locked principal (see [ADR-03](./adr/03-voting-power-tracks-full-balance.md)). A recipient votes only with XAN that it has unlocked and delegated. The XAN in `XanV2Vesting` still counts toward the total supply that sets the quorum (see section [XanGovernor](./02-XanV2-governance.md#3-xangovernor)), but no one can cast its votes. This is accepted (see [ADR-09](./adr/09-locked-xanv2vesting-principals-carry-no-voting-power.md)).

## 8. Integration

A client checks both contracts for an account, because an account can have a principal in each (see section [Recipients](#5-recipients)). If `principalOf(account)` on `XanV2Vesting` is non-zero, it calls `unlock()` and the views on `XanV2Vesting`; if `principalOf(account)` on the XAN token proxy is non-zero, it calls them on the proxy. The views that both contracts have mean the same on both. The spendable XAN is `unlockedBalanceOf` on the token alone, because it already includes the XAN that `unlockedAmountOf` reports (see section [Domain model & balances](#3-domain-model--balances)).

## 9. Ownership

The owner is the council multisig, which funds the contract (see [ADR-10](./adr/10-the-council-multisig-owns-xanv2vesting.md)). The deployment script passes it to `initialize` as `initialOwner`, from `Parameters.COUNCIL_MULTISIG`, so the deployer does not enter it. The owner can add recipients, withdraw the surplus, upgrade the implementation (`upgradeToAndCall`), and transfer or renounce ownership (`OwnableUpgradeable`). Without an upgrade, it cannot change or remove a principal, and it cannot unlock for a recipient. An upgrade can change every rule of the contract; after a renounce, no one can upgrade it. The voter body has no power over `XanV2Vesting`: replacing the council module does not change its owner.

## 10. Trust assumptions

- **The owner adds only eligible recipients with their correct principals.** All principals draw on one XAN balance. A principal that the council multisig does not fund, such as an oversized one, takes XAN that backs the other recipients when it unlocks, and it cannot be removed. The owner, the council multisig, is trusted to add only principals that it funds (see [ADR-10](./adr/10-the-council-multisig-owns-xanv2vesting.md)); `withdrawSurplus` alone cannot take XAN that a locked balance needs. The contract does not read the principals in the XAN token, so the owner must also make sure that a principal does not repeat a tranche that the account already vests there.
- **The council multisig keeps the contract funded.** Unlocks depend on its top-ups. An underfunded contract delays unlocks but loses no vesting.
- **The owner upgrades only to reviewed implementations.** An upgrade can change the schedule and the principals, and it can transfer all XAN that the contract holds. A captured council multisig can take that XAN at once (see [ADR-10](./adr/10-the-council-multisig-owns-xanv2vesting.md)).
- **Without an upgrade, a principal leaves the contract only through `unlock()` by its account.** `withdrawSurplus` cannot take it. A principal for an address that can never call `unlock()`, such as a wrong address or a lost key, stays in the contract. So each recipient proves control of its address before it is added (see [DEPLOYMENT.md](../DEPLOYMENT.md#5-xanv2vesting)).
- **The schedule is fixed in the implementation.** Each implementation copies the schedule of the token when it is constructed. A token upgrade that changes the schedule does not change `XanV2Vesting` until the owner upgrades it to an implementation constructed after that change.
- **Locked principals do not vote.** See section [Voting](#7-voting).
- **No external audit.** `XanV2Vesting` relies on its tests, an internal security review, and the linters; unlike the other contracts in this repository, no external auditor has reviewed it.

## 11. Deployment

`script/DeployXanV2Vesting.s.sol` (`just deploy-vesting-simulate`, then `just deploy-vesting`) deploys the implementation and an `ERC1967Proxy` that calls `initialize`, after the OpenZeppelin upgrades plugin has validated the implementation. It takes the XAN token proxy and the path of a JSON file in `script/input/` with the initial recipients:

```json
{ "recipients": [{ "account": "0x…", "principal": "1000000000000000000" }] }
```

Principals are decimal strings in the smallest unit (18 decimals). Every recipient has proved control of its address beforehand (see [DEPLOYMENT.md](../DEPLOYMENT.md#5-xanv2vesting)). After the deployment, the council multisig transfers the XAN.

The deployer of the governance stack deploys the implementation and the proxy at the same nonces on Ethereum mainnet and Sepolia, so both networks share their addresses. On these two chains, the script reverts before it broadcasts anything unless the proxy lands at `0x60A149fE74D2f55219f1Abad2911756Da9c67bf4`.

## 12. Parameters

| Getter           | Source                                       | Mainnet                                                                                                                           |
| ---------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `XAN_TOKEN()`    | implementation constructor                   | `0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7`                                                                                      |
| `vestingStart()` | XAN token, at implementation construction    | `1790683200` (2026-09-29 12:00 UTC)                                                                                               |
| `vestingEnd()`   | XAN token, at implementation construction    | `1885291200` (2029-09-28 12:00 UTC)                                                                                               |
| `owner()`        | `initialize` (`Parameters.COUNCIL_MULTISIG`) | `0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116`, the council multisig ([ADR-10](./adr/10-the-council-multisig-owns-xanv2vesting.md)) |
