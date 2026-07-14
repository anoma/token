# Seed the voting total-supply checkpoint at the upgrade

The supply was minted in V1, before `ERC20Votes` existed, so the voting total-supply checkpoint is empty and `getPastTotalSupply` would read **0** — which makes `GovernorVotesQuorumFraction` quorum **0**, so any single `For` vote would pass. `reinitializeFromV1` therefore seeds it once with `_transferVotingUnits(address(0), address(this), totalSupply())`: the `from == address(0)` leg adds to the total-supply checkpoint, and the `address(this)` recipient moves no delegate votes because nothing is delegated yet at the upgrade.

## Considered options

- **Fix quorum on the Governor side** (e.g. a custom `quorum()` reading `totalSupply()`) — rejected: it pushes a token-internal concern into every governance consumer; seeding the checkpoint is the canonical, consumer-agnostic fix.

## Consequences

- `getPastTotalSupply` is correct only for timepoints at or after the upgrade; pre-upgrade timepoints read `0`. This is fine because governance only operates after the upgrade.
