# The council multisig owns XanV2Vesting

`XanV2Vesting` has an owner that adds recipients with their principals, withdraws the surplus, and upgrades the implementation (see [docs/03-XanV2Vesting.md](../03-XanV2Vesting.md#9-ownership)). All principals draw on one XAN balance, so the owner decides who receives the XAN that the contract holds. The timelock owns the token, so every privileged action on the token waits out a timelock delay under the governance layer (see [docs/02-XanV2-governance.md](../02-XanV2-governance.md#1-actors)); `XanV2Vesting` needs an owner of its own.

We make the **council multisig** the owner: the Safe that fronts the `XanUpgradeCouncilModule` (see [ADR-07](./07-council-backup-upgrade-module.md)) and funds `XanV2Vesting`. Its address is `Parameters.COUNCIL_MULTISIG`, the same on Ethereum mainnet and Sepolia, and the deployment script passes it to `initialize` as `initialOwner`, so the deployer does not enter it.

## Considered options

- **The council multisig** — chosen: the party that funds the contract also allocates its XAN, and one multisig transaction adds a batch of recipients or withdraws the surplus.
- **The timelock** — rejected: it keeps `XanV2Vesting` under the voter body, but every batch of recipients, every surplus withdrawal, and every upgrade would then need a full voter-body proposal (35 days, see [Timings](../02-XanV2-governance.md#timings)), while the funding still happens off-chain.

## Consequences

- **The voter body has no power over `XanV2Vesting`.** It cannot add, block, or remove recipients, and it cannot replace the owner; only the owner can transfer ownership. Replacing the council module (see [ADR-07](./07-council-backup-upgrade-module.md)) does not change the owner of `XanV2Vesting`.
- **The council is trusted with the XAN in `XanV2Vesting`.** It must add only eligible recipients with their correct principals: an unfunded or oversized principal takes XAN that backs the other recipients, and it cannot be removed.
- **A captured council can take the XAN in `XanV2Vesting`.** Besides scheduling token upgrades (see [Trust assumptions](../02-XanV2-governance.md#8-trust-assumptions)), it can upgrade `XanV2Vesting` to an implementation that transfers all XAN that the contract holds. The loss is bounded by that XAN.
- **A new council address needs a code change.** If the council multisig moves to a new address before the deployment, `Parameters.COUNCIL_MULTISIG` must change first.
