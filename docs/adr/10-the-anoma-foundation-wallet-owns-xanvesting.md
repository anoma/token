# The Anoma Foundation wallet owns XanVesting

`XanVesting` has an owner that adds recipients with their principals and withdraws the surplus (see [docs/03-XanVesting.md](../03-XanVesting.md#9-ownership)). All principals draw on one XAN balance, so the owner decides who receives the XAN that the contract holds. The timelock owns the token, so every privileged action on the token waits out a timelock delay under the governance layer (see [docs/02-XanV2-governance.md](../02-XanV2-governance.md#1-actors)); `XanVesting` needs an owner of its own.

We make the **Anoma Foundation wallet** the owner: the wallet that holds the missed tranches and funds the contract. The deployment passes it as `initialOwner`.

## Considered options

- **The Anoma Foundation wallet** — chosen: the party that funds the contract also allocates its XAN, so the owner gains no power over XAN that someone else provided. The foundation could withhold that XAN anyway.
- **The council multisig** — rejected: a captured council could then allocate the XAN in `XanVesting`, which widens its power beyond token upgrades (see [Trust assumptions](../02-XanV2-governance.md#8-trust-assumptions)).
- **The timelock** — rejected: it keeps `XanVesting` under the voter body, but every batch of recipients and every surplus withdrawal would then need a full voter-body proposal (35 days, see [Timings](../02-XanV2-governance.md#timings)), while the funding still happens off-chain.

## Consequences

- **The voter body has no power over `XanVesting`.** It cannot add, block, or remove recipients, and it cannot replace the owner; only the owner can transfer ownership.
- **The foundation is trusted with the XAN in `XanVesting`.** It must add only eligible recipients with their correct principals: an unfunded or oversized principal takes XAN that backs the other recipients, and it cannot be removed. This adds no trust beyond what the foundation already holds, because it provides that XAN.
- **The upgrade council keeps only its upgrade powers.** Nothing in `XanVesting` widens what a captured council can do.
