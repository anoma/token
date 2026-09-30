# Locked XanVesting principals carry no voting power

`XanVesting` (see [docs/03-XanVesting.md](../03-XanVesting.md)) holds the XAN of its recipients until they unlock it. `ERC20Votes` counts voting units by holder, so the locked principals are voting units of the `XanVesting` contract, and the contract has no way to delegate them. Unlike a locked principal in `XanV2` (see [ADR-03](./03-voting-power-tracks-full-balance.md)), a locked principal in `XanVesting` therefore carries **no voting power**: a recipient votes only with the XAN that it has unlocked and delegated. We accept this.

## Considered options

- **The owner delegates the votes of the contract** — rejected: it gives the owner, a multisig, the voting power of every locked principal, which the recipients do not control.
- **Delegation per recipient** — rejected: `ERC20Votes` gives each holder one delegate, so every recipient would need a holder of its own, such as an escrow contract per recipient. That is a larger design for a few recipients.

## Consequences

- **Recipients vote only with unlocked XAN**, after they delegate it.
- **The XAN in `XanVesting` counts toward the quorum but cannot vote.** The quorum is a fraction of the total voting supply (see [ADR-05](./05-seed-voting-total-supply-checkpoint.md)), which includes the XAN in `XanVesting`. No one can cast those votes, so reaching the quorum needs a larger share of the votes that can be cast.
