# Anoma (XAN) Token

The Anoma token (XAN) is an upgradeable ERC-20 token.

This repository contains both implementations and the upgrade from V1 to V2. **V1** gates upgrades with an in-token meta-governance mechanism based on quorum approval voting and a fast-track council. **V2** removes the in-token governance in favor of a single owner, vests the formerly locked balances linearly, and adds `ERC20Votes` vote delegation on a timestamp clock. The V2 owner is an external governance stack — the `XanGovernor` DAO, its `TimelockController`, and the `XanUpgradeCouncilModule` backup upgrade path.

Conceptual orientation lives in [`CONTEXT.md`](./CONTEXT.md). The audit-facing specifications are [`docs/01-XanV2-upgrade.md`](./docs/01-XanV2-upgrade.md) (token) and [`docs/02-XanV2-governance.md`](./docs/02-XanV2-governance.md) (governance layer); design decisions are recorded in [`docs/adr/`](./docs/adr/).

## Deployments

The proxy is the token address and stays fixed across upgrades; the implementation behind it is what an upgrade replaces. The council multisig is V1's `governanceCouncil`, which schedules V1 upgrades and will also front the `XanUpgradeCouncilModule` after the upgrade. Both networks share the same addresses.

| Contract          | Ethereum mainnet                                                                                                        | Sepolia                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Proxy (XAN token) | [`0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7`](https://etherscan.io/token/0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7)   | [`0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7`](https://sepolia.etherscan.io/token/0xCEDbEA37C8872c4171259Cdfd5255CB8923Cf8e7)   |
| Implementation V1 | [`0x03997b568FE70E91A53c458DC19dc29e0bC2735E`](https://etherscan.io/address/0x03997b568FE70E91A53c458DC19dc29e0bC2735E) | [`0x03997b568FE70E91A53c458DC19dc29e0bC2735E`](https://sepolia.etherscan.io/address/0x03997b568FE70E91A53c458DC19dc29e0bC2735E) |
| Council multisig  | [`0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116`](https://etherscan.io/address/0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116) | [`0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116`](https://sepolia.etherscan.io/address/0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116) |

## Audits

Anoma smart contracts undergo regular audits:

### XanV1

1. Zellic Audit

   - Company Website: https://www.zellic.io
   - Commit ID: [856c38dd77d777783c4b0f7010419ef1b99a0daa](https://github.com/anoma/token/tree/856c38dd77d777783c4b0f7010419ef1b99a0daa)
   - Started: 2025-07-10
   - Finished: 2025-07-14

   [📄 Audit Report (pdf)](./audits/2025-07-17_Zellic_Anoma_Token_&_TokenDistributor.pdf)

2. Informal Systems Audit

   - Company Website: https://informal.systems/
   - Commit ID: [e4b0034454612c0ff018f239d841fc3024d62151](https://github.com/anoma/token/tree/e4b0034454612c0ff018f239d841fc3024d62151)
   - Started: 2025-08-18
   - Finished: 2025-08-27
   - Updated: 2025-09-18

   [📄 Initial Audit Report (pdf)](./audits/2025-09-03_Informal_Systems_Anoma_Token_&_TokenDistributor.pdf)
   [📄 Updated Audit Report (pdf)](./audits/2025-09-18_Informal_Systems_Anoma_Token_&_TokenDistributor.pdf)

### XanV2 & Governance

1. Nethermind Audit

   - Company Website: https://www.nethermind.io
   - Commit ID: [a580fdb7ec2fd26a480bd0d22982b8aebd503df8](https://github.com/anoma/token/tree/a580fdb7ec2fd26a480bd0d22982b8aebd503df8)
   - Started: 2026-07-29
   - Finished: 2026-08-06

   [📄 Audit Report (pdf)](./audits/2026-08-06_Nethermind_XAN_Token_Upgrade.pdf)

## Security

If you believe you've found a security issue, we encourage you to notify us via Email at [security@anoma.foundation](mailto:security@anoma.foundation). Please do not use the issue tracker for security issues. We welcome working with you to resolve the issue promptly.

## Setup

1. Get an up-to-date version of [Foundry](https://github.com/foundry-rs/foundry)
   with

   ```sh
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. Clone this repo and run
   ```sh
   forge install
   ```

## Usage

### Tests

```sh
forge test --force
```

> [!NOTE]  
> The `--force` flag is required for the [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) package to work.

### Coverage

```sh
forge coverage
```

### Linting & Static Analysis

As a prerequisite, install the

- `solhint` linter (see https://github.com/protofire/solhint)
- `slither` static analyzer (see https://github.com/crytic/slither)

```sh
bunx --bun solhint --config .solhint.json 'src/**/*.sol' && \
bunx --bun solhint --config .solhint.other.json 'script/**/*.sol' 'test/**/*.sol' && \
slither .
```
