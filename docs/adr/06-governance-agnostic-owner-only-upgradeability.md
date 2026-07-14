# XanV2 is governance-agnostic; upgrade authority is owner-only

V1 gated upgrades with a bespoke, in-token meta-governance engine (quorum approval voting + a fast-track council
+ veto + delay). V2 **deletes all of it** and gates `_authorizeUpgrade` with `onlyOwner`, relocating governance into the external owner — an OpenZeppelin `Governor` + `TimelockController` (+ an upgrade council), which reads the token's `ERC20Votes`. The dead V1 `Voting`/`Council` structs are retained only for storage-layout compatibility.

## Rationale

- Standard OZ `Governor` + `ERC20Votes` is battle-tested, auditable, and composable, versus a bespoke in-token engine that must be re-audited whenever governance changes.
- Governance can now evolve — quorum, voting period, the upgrade council, even the entire Governor — via `transferOwnership` to a new owner contract, **without ever upgrading the token**.
- Smaller token attack surface and a clean separation of concerns.

## Considered options

- **Keep V1-style in-token meta-governance** — rejected: couples governance to token code and forces a token re-audit on every governance change.

## Consequences

- The token **fully trusts `owner()`**. A flawed or captured owner is total control of the token. That risk is deliberately pushed into the external Governor / Timelock / upgrade council design, which is out of scope for the token itself.
- The V1 struct layout must be preserved in V2 for storage compatibility.
