# Token

## Installation

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

### Documentation

Run

```sh
forge doc
```
