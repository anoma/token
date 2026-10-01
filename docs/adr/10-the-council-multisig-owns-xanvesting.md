# The council multisig owns XanVesting

`XanVesting` has an owner that adds recipients with their principals and withdraws the surplus (see [docs/03-XanVesting.md](../03-XanVesting.md#9-ownership)). All principals draw on one XAN balance, so the owner decides who receives the XAN that the contract holds. The timelock owns the token, so every privileged action on the token waits out a timelock delay under the governance layer (see [docs/02-XanV2-governance.md](../02-XanV2-governance.md#1-actors)); `XanVesting` needs an owner of its own.

We make the **council multisig** the owner: the Safe that fronts the `XanUpgradeCouncilModule` (see [ADR-07](./07-council-backup-upgrade-module.md)) and funds `XanVesting`. Its address is `Parameters.COUNCIL_MULTISIG`, the same on Ethereum mainnet and Sepolia, and the deployment script passes it as `initialOwner`, so the deployer does not enter it.

## Considered options

- **The council multisig** — chosen: the party that funds the contract also allocates its XAN, and one multisig transaction adds a batch of recipients or withdraws the surplus.
- **The timelock** — rejected: it keeps `XanVesting` under the voter body, but every batch of recipients and every surplus withdrawal would then need a full voter-body proposal (35 days, see [Timings](../02-XanV2-governance.md#timings)), while the funding still happens off-chain.

## Consequences

- **The voter body has no power over `XanVesting`.** It cannot add, block, or remove recipients, and it cannot replace the owner; only the owner can transfer ownership. Replacing the council module (see [ADR-07](./07-council-backup-upgrade-module.md)) does not change the owner of `XanVesting`.
- **The council is trusted with the XAN in `XanVesting`.** It must add only eligible recipients with their correct principals: an unfunded or oversized principal takes XAN that backs the other recipients, and it cannot be removed.
- **A captured council can allocate the XAN in `XanVesting`.** Besides scheduling token upgrades (see [Trust assumptions](../02-XanV2-governance.md#8-trust-assumptions)), it can add principals for accounts that it controls and withdraw the surplus. The loss is bounded by the XAN that the contract holds.
- **A new council address needs a code change.** If the council multisig moves to a new address before the deployment, `Parameters.COUNCIL_MULTISIG` must change first.
