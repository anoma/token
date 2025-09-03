# Token

The Anoma token is the foundation of the Anoma Economic System. It is an ERC-20 token, which can be upgraded (to arbitrary new logic) with a meta-governance mechanism based on quorum approval voting and a fast-track council.

## Audits

Anoma smart contracts undergo regular audits:

1. Zellic Audit

   - Company Website: https://www.zellic.io
   - Commit ID: [856c38dd77d777783c4b0f7010419ef1b99a0daa](https://github.com/anoma/token/tree/856c38dd77d777783c4b0f7010419ef1b99a0daa)
   - Started: 2025-07-10
   - Finished: 2025-07-14

   [📄 Full Report (pdf)](./audits/2025-07-17_Zellic_Anoma_Token_&_TokenDistributor.pdf)

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
forge coverage
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
