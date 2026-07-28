# Anoma (XAN) Token

The Anoma token (XAN) is the foundation of the Anoma Economic System. It is an upgradeable ERC-20 token.

The currently deployed **V1** implementation gates upgrades with an in-token meta-governance mechanism based on quorum approval voting and a fast-track council. This repository also contains the **V2** implementation and the V1→V2 upgrade: V2 removes the in-token governance in favor of a single owner, vests the formerly locked balances linearly, and adds `ERC20Votes` vote delegation on a timestamp clock. The V2 owner is an external governance stack — the `XanGovernor` DAO, its `TimelockController`, and the `XanUpgradeCouncilModule` backup upgrade path.

Conceptual orientation lives in [`CONTEXT.md`](./CONTEXT.md). The audit-facing specifications are [`docs/01-XanV2-upgrade.md`](./docs/01-XanV2-upgrade.md) (token) and [`docs/02-XanV2-governance.md`](./docs/02-XanV2-governance.md) (governance layer); design decisions are recorded in [`docs/adr/`](./docs/adr/).

## Audits

Anoma smart contracts undergo regular audits:

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

Run

```sh
forge test --force --gas-report
```

> [!NOTE]  
> The `--force` flag is required for the [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) package to work.
> The `--gas-report` flag prints selected gas reports.

### Coverage

Run

```sh
forge coverage --ir-minimum
```

### Linting & Static Analysis

As a prerequisite, install the

- `solhint` linter (see https://github.com/protofire/solhint)
- `slither` static analyzer (see https://github.com/crytic/slither)

Run the linter and analysis with

```sh
npx solhint --config .solhint.json 'src/**/*.sol' && \
npx solhint --config .solhint.other.json 'script/**/*.sol' 'test/**/*.sol' && \
slither .
```

### Documentation

Run

```sh
forge doc
```
