# An upgrade-council module for backup token upgrades

`XanGovernor` + `TimelockController` own and upgrade the token (see [ADR-06](./06-governance-agnostic-owner-only-upgradeability.md)). To give an **upgrade council** (a Safe multisig) a **backup upgrade path** for when the voter body cannot reach quorum, we add a dedicated `XanUpgradeCouncilModule` rather than widening the token or the Governor. The mechanics are specified in [docs/02-XanV2-governance.md](../02-XanV2-governance.md#4-xanupgradecouncilmodule); this ADR records why the council's powers are shaped as they are.

The shaping principle is that **subordination to the voter body is one-way**:

- **The module never owns the token.** It holds timelock roles and schedules an upgrade operation; the timelock, as owner, executes it. Ownership stays where the rest of governance already points.
- **Propose: upgrades only.** The council's sole scheduling power builds a token upgrade and nothing else.
- **Cancel: its own pending upgrade only.** The module holds `CANCELLER` but only ever aims it at the operation it scheduled itself, so the council has no power over voter-body operations.
- **The delay is computed live** from the Governor's settings and the timelock's minimum, and **re-checked at execution** by the batch's leading `checkUpgradeDelayElapsed` call, so a council upgrade always outlasts a full voter cancel cycle even if those settings change after it was scheduled (see [ADR-08](./08-recompute-the-council-upgrade-delay-at-execution.md)). The path is a **backup, never a fast-track**: slower than a voter proposal, valuable for liveness rather than speed.
- **The council address is immutable.** A Safe rotates its own signers without changing address, so routine membership changes need no on-chain action. Changing the address means the voter body revokes this module's roles and wires a fresh one — the same action that disarms a captured council, so immutability costs no capability the voter body lacked.

The voter body cancels a council upgrade with a `XanGovernor` proposal that relays `TimelockController.cancel` through the governor. Reusing the Governor's quorum instead of bespoke vote-counting is what forces the council delay to out-size a full cancel cycle.

## Considered options

- **Extend `XanGovernor` with council functions** — rejected: bloats and de-standardises an already-complex Governor and enlarges the re-audit surface on every governance change.
- **Module owns the token directly** — rejected: duplicates the timelock's delay/cancel machinery, moves ownership off the timelock the rest of governance uses, and double-delays voter-body upgrades.
- **Bare timelock roles for the council, no module** — rejected: `PROPOSER` is not operation-scoped, so the council could schedule *any* action; the module exists to keep the propose path upgrades-only on-chain.
- **A general cancel power for the council** — a mutual check: `cancel` over any queued operation as an emergency brake against a malicious voter-body proposal. Rejected on **capture-cost asymmetry**: passing a malicious voter proposal takes quorum — 10% of a voting supply that includes locked balances (see [ADR-03](./03-voting-power-tracks-full-balance.md)), with timestamp-checkpointed votes ruling out flash-loan capture — while the brake needs only a handful of compromised multisig keys. The brake would defend against the expensive attack while itself *being* the cheap one: a captured council could stall every governance operation. The argument scales with the quorum, so revisit it if that parameter moves.
- **No cancel at all** — rejected: the council could not withdraw its own mistakenly scheduled upgrade in the exact scenario the module exists for, a dormant voter body being the only other canceller. With the executor role open, a flawed upgrade would be certain to execute, and the one-in-flight guard would block a corrected re-schedule meanwhile.
- **On-chain council rotation** (a timelock-gated `setCouncil`) — rejected: rotation to a _new address_ is rare, and the case that needs it — a compromised Safe — is already covered by revoking the module's roles and wiring a fresh module. A privileged mutator and its second access-control path bought no capability the voter body lacked.
- **Bespoke quorum-gated cancel for the voter→council direction** (V1's `vetoCouncilUpgrade`) — rejected: reintroduces the vote-counting the OZ Governor migration shed; the Governor-proposal cancel reuses audited code at the cost of a longer council delay.
- **Explicit inactivity gate** (block the council while voters are "active") — rejected: a stock Governor exposes no persistent "active" state; the long delay makes the gate emergent — an active voter body cancels, an inactive one lets the upgrade land.

## Consequences

- **A passed voter-body proposal is on-chain-unstoppable.** No actor can cancel a queued voter-body operation. The residual defence against a captured voter body is off-chain, within the timelock delay: coordinate socially, exit, or fork. Accepted on the same capture-cost grounds, and likewise sensitive to the quorum.
- **Inactive-voter honeypot (irreducible).** A voter body that cannot reach quorum also cannot cancel, so in the very scenario the council exists for, the council is checked only by the delay and off-chain monitoring. This is the layer's central trust assumption, bounded by voters later replacing the council.
- **Double delay on the voter→council cancel.** That cancel is itself a Governor proposal and passes through the timelock before it can cancel; this is folded into the council-delay sizing.
- **One upgrade in flight.** The module refuses a council upgrade while another is pending; cancelling frees the slot for a corrected re-schedule. Voter-body upgrades are unaffected, and the token's `reinitializer` version guard prevents a stale operation re-running.
- **The council cannot leave on its own.** The address is immutable and the module has no hand-off or renounce. A council wishing to step down asks the voter body to disarm the module, or simply stops scheduling upgrades.
