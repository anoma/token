# CONTEXT

> Domain glossary and architecture overview for the Anoma (XAN) token and its governance: the V1→V2 upgrade, linear vesting of formerly-locked balances, `ERC20Votes` governance, the upgrade council, and `XanV2Vesting` for the recipients that the genesis distribution did not contain. This is conceptual orientation only — the audit-grade token spec is [docs/01-XanV2-upgrade.md](docs/01-XanV2-upgrade.md), the governance reference is [docs/02-XanV2-governance.md](docs/02-XanV2-governance.md), the `XanV2Vesting` spec is [docs/03-XanV2Vesting.md](docs/03-XanV2Vesting.md), and the design decisions are the ADRs in [docs/adr/](docs/adr/).

## Architecture

The XAN token is **governance-agnostic**: it trusts a single owner to authorize upgrades and holds no governance logic itself. All meta-governance lives outside the token, in the contracts that hold that owner role. Authority flows from the token holders, through the DAO, to the timelock that owns and upgrades the token:

```mermaid
flowchart LR
    voters([Voter body])
    gov[XanGovernor]
    multisig([Multisig])
    module[XanUpgradeCouncilModule]
    timelock[Timelock]
    proxy[ERC1967Proxy]
    tokenV1[(XanV1)]
    token[(XanV2)]
    vesting[XanV2Vesting]

    voters -->|delegate + vote| gov
    gov -->|proposals| timelock
    multisig -->|propose upgrade| module
    module --> timelock
    timelock -->|owns + upgrades| proxy
    proxy -. formerly .-x tokenV1
    proxy -->|delegates to| token

    voters -->|cancel + replace| module
    multisig -->|owns + funds| vesting
```

### Actors

- **XanV2** — the token. Governance-agnostic; its only privileged power is an owner-authorized upgrade. Carries `ERC20Votes` voting power (the full balance, including still-locked vesting tokens), so holders can delegate and vote.
- **Timelock** — owns the token and is the only account that can upgrade it. Every privileged action waits out a delay before anyone may execute it.
- **XanGovernor** — the voter body's instrument: holders delegate and vote, and an accepted proposal is queued through the timelock and then executed.
- **XanUpgradeCouncilModule** — a module fronting a fixed council multisig that can initiate a token upgrade as a backup when the voter body is inactive. It can withdraw its own pending upgrade but holds no power over voter-body operations.
- **XanV2Vesting** — vests XAN for the eligible recipients that the V1 genesis distribution did not contain, on the V2 schedule. It pays unlocks from the XAN that the council multisig moves into it. The council multisig owns, funds, and can upgrade it, outside the voter body's control.

### Interplay

- **Two upgrade paths**, both ending as a timelocked upgrade: a **voter-body proposal**, or a **council-initiated upgrade**. The council path is _slower_, not faster — it waits out a longer delay than a voter proposal, so the voter body always has time to cancel it.
- **One-way cancel**: the voter body can cancel the council's upgrade through a governor proposal, and the council can withdraw its own pending upgrade — but the council cannot cancel voter-body operations. Cancelling only blocks — no funds can move this way.
- **Voter supremacy**: the voter body can cancel the council's upgrades, replace the council, and revoke the module's powers; the council holds no reciprocal check over the voter body. The irreducible gap is an **inactive voter body** — the scenario the council exists for — where the council's long delay and off-chain monitoring are the only checks. A second, operational one: leaving two contrary timing-settings proposals queued in the timelock lets a pending council upgrade's deadline be pushed out and pulled back, stranding a cancel filed in between — see [Settings changes while an upgrade is pending](docs/02-XanV2-governance.md#settings-changes-while-an-upgrade-is-pending).

## Glossary

### Actors

**XanV2** (the token): The upgradeable ERC-20 / `ERC20Votes` token. Governance-agnostic — its only privileged power is an owner-authorized upgrade. Voting power tracks the full balance, including locked vesting tokens.

**XanGovernor**: The OpenZeppelin `Governor` DAO driven by the token's votes; the voter body's on-chain instrument. Power: propose, tally votes (quorum plus a `For` majority), and queue and execute accepted proposals through the timelock.

**XanUpgradeCouncilModule**: The upgrade council's on-chain module. Powers: initiate a token upgrade (upgrades-only, one at a time) as a backup for an inactive voter body — the upgrade takes longer than a voter proposal, so the voter body can cancel it — and withdraw its own pending upgrade. It holds no power over voter-body operations. Its council multisig is fixed for the module's lifetime: the voter body cannot swap a member on-chain, but it can replace the council wholesale by disarming this module (revoking its powers) and deploying a new one. Distinct from V1's defunct in-token `governanceCouncil`.

**Timelock** (`TimelockController`): The OpenZeppelin timelock that owns the token and executes accepted operations after a delay. Anyone may execute once the delay elapses; it self-administers, so its roles change only through governance.

**XanV2Vesting**: The UUPS-upgradeable contract that vests XAN for the eligible recipients that the V1 genesis distribution did not contain. It copies the V2 vesting schedule and `unlock()`, and it pays each unlock from the XAN that the council multisig moves into it. Owned by the council multisig, which funds and can upgrade it; its locked principals carry no voting power.

### Token & vesting

**Principal** (`principalOf`): The amount an account had locked under XAN V1 — its locked tranche from the distribution, received via `transferAndLock`. In V2 the principal vests linearly; it is fixed per account and never increases. In `XanV2Vesting`, the principal is the locked tranche that the owner added for a recipient that the distribution did not contain.

**Locked balance** (`lockedBalanceOf`): The still-locked, non-transferable part of an account's principal: `principal − unlocked`. Reaches zero once the principal has fully vested and been unlocked.

**Unlocked balance** (`unlockedBalanceOf`): The spendable part of an account's balance: `balanceOf − lockedBalance`. Only this part may be transferred. In `XanV2Vesting`, it is the amount that the contract has transferred to the account so far.

**Vested amount**: The portion of an account's principal that has vested by a given time — `0` before the start, the full principal at or after the end, and linear in between. A function of time alone, independent of what has been unlocked.

**Unlockable balance** (`unlockableBalanceOf`): What `unlock()` would move from locked to unlocked right now: `max(0, vested − unlocked)`.

**Unlock** (`unlock`): The action by which an account moves its currently unlockable (vested-but-not-yet-unlocked) tokens from its locked to its unlocked balance, making them spendable. In `XanV2`, it does not change `balanceOf` and moves no tokens between accounts; in `XanV2Vesting`, it transfers the unlocked amount from the contract to the account.

**Vesting schedule**: The linear schedule over which principals vest, from `XAN_VESTING_START` to `XAN_VESTING_START + XAN_VESTING_DURATION` (the vesting end). Identical for every account and baked into the V2 implementation; there is no cliff. `XanV2Vesting` copies it from the token when its implementation is constructed.

**Recipient**: An account with a principal in `XanV2Vesting`. It can also have a principal in the token; the two vest independently. The XAN it unlocks from `XanV2Vesting` is freely transferable.

**Surplus**: The XAN that `XanV2Vesting` holds above its total locked balance. Only the owner can withdraw it. Below the total locked balance, an unlock that needs more XAN than the contract holds reverts until the council multisig tops the contract up.

### Upgrade

**Reinitialization** (`reinitializeFromV1`): The one-time, argument-free call run when the proxy is upgraded from V1 to V2: it initializes `ERC20Votes` and ownership, seeds the voting total-supply checkpoint, and emits the vesting schedule. Executable permissionlessly once the upgrade is scheduled; the owner and schedule are baked into the implementation, never passed in.

### Governance

**Voter body**: The token holders exercising delegated `ERC20Votes` voting power — the V2-era electorate that drives `XanGovernor`. V1's quorum-locking-and-voting mechanism is its now-defunct predecessor.
