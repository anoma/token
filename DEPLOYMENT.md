# XanV2 Upgrade — Deployment Checklist

Step 1 deploys both networks; steps 2 and 3 are then run on Sepolia first and on mainnet once the rehearsal has completed. The token spec is [`docs/01-XanV2-upgrade.md`](docs/01-XanV2-upgrade.md) and the governance spec is [`docs/02-XanV2-governance.md`](docs/02-XanV2-governance.md).

## 1. Before you start

- [x] **Create a fresh deployer wallet.** It must never have sent a transaction on any chain, and must be used for nothing else afterwards.

  Deployer wallet: `0xffbA90faD46ee7881EaEc8FAaf54C990EC6D8F19` ([mainnet](https://etherscan.io/address/0xffbA90faD46ee7881EaEc8FAaf54C990EC6D8F19), [sepolia](https://sepolia.etherscan.io/address/0xffbA90faD46ee7881EaEc8FAaf54C990EC6D8F19))

- [x] **Confirm it is at nonce 0 on both chains.** Both commands must print `0`; if either does not, discard the wallet and create another.

  ```bash
  cast nonce <deployer> --rpc-url sepolia
  cast nonce <deployer> --rpc-url mainnet
  ```

- [x] **Fund the wallet on both chains.** Inbound transfers do not consume its nonce.

## 2. Step 1 — Prepare (both networks)

Deploys the governance stack and the V2 implementation, baking the timelock into `implementationV2` as the token owner. Do this on **both** chains before moving on: the stack is inert until step 2 schedules an upgrade, so a mainnet deployment sitting unscheduled carries no risk to the token, and deploying both here pins them to the same nonces before the wallet is used for anything else.

Run the block below for `sepolia`, then for `mainnet`.

- [x] **Confirm `<council>` is the multisig for the new `XanUpgradeCouncilModule`.** It is baked into the module and cannot be changed afterwards. It is the same Safe as V1's `governanceCouncil`, which performs step 2.

- [x] **Dry-run.**

  ```bash
  just prepare-upgrade-simulate <sender> <proxy> <council> <chain>
  ```

- [x] **Check the printed transaction list against the [address map](#6-address-map).** Ten transactions, `implementationV2` last. **Stop if it differs** — the nonce assignments have moved, so the contracts will not land where the map says.

- [x] **Broadcast.**

  ```bash
  just prepare-upgrade <deployer> <sender> <proxy> <council> <chain>
  ```

  - [x] Sepolia: [broadcast/PrepareXanV2Upgrade.s.sol/11155111/run-1786029049708.json](broadcast/PrepareXanV2Upgrade.s.sol/11155111/run-1786029049708.json)
  - [x] Mainnet: [broadcast/PrepareXanV2Upgrade.s.sol/1/run-1786029347059.json](broadcast/PrepareXanV2Upgrade.s.sol/1/run-1786029347059.json)

- [x] **Confirm the deployer no longer holds the timelock admin** (nonce 8 renounced it). Must print `false`.

  ```bash
  cast call <timelock> "hasRole(bytes32,address)(bool)" \
    $(cast call <timelock> "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url <chain>) <sender> --rpc-url <chain>
  ```

- [x] **Verify the contracts on the explorers.**

  ```bash
  just verify-governance <timelock> <governor> <council-module> <implementation-v2> <chain>
  ```

- [x] **Record all four addresses** (timelock, governor, council module, V2 implementation) in [README.md](README.md#deployed-contracts)

Once both chains are done:

- [x] **Confirm the two V2 implementation deployments are byte-identical.** Both commands must print the same hash. Its constructor arguments are the nonce-0 timelock and two constants, all identical across the chains.

  ```bash
  cast keccak $(cast code <implementationV2> --rpc-url sepolia)
  cast keccak $(cast code <implementationV2> --rpc-url mainnet)
  ```

  Result: `0xf5776c910a51e9cd4422f28c88fea4d8c75d2d73d9d833809e67835211f86354`

## 3. Step 2 — Schedule

A Safe transaction. Run on Sepolia first; repeat on mainnet once the rehearsal has completed.

- [ ] **Execute `scheduleCouncilUpgrade(implementationV2)` on the V1 proxy** from V1's `governanceCouncil` multisig. Use
  - [ ] [safe-payloads/scheduleCouncilUpgrade_to_xanV2_sepolia.json](safe-payloads/scheduleCouncilUpgrade_to_xanV2_sepolia.json)
  - [ ] [safe-payloads/scheduleCouncilUpgrade_to_xanV2_mainnet.json](safe-payloads/scheduleCouncilUpgrade_to_xanV2_mainnet.json)

- [ ] **Confirm it landed.** The address must equal `implementationV2`; the `uint48` (`endTime`) is the timestamp step 3 becomes executable at.

  ```bash
  cast call <proxy> "scheduledCouncilUpgrade()(address,uint48)" --rpc-url <chain>
  ```

- [ ] **Record the executable-at timestamp.** It is the scheduling time plus `DELAY_DURATION`, which is 14 days.

The alternative V1 path is the voter-body quorum — hold `castVote(implementationV2)` to quorum, then `scheduleVoterBodyUpgrade()`. The council path is the expected one.

## 4. Step 3 — Upgrade (after 14 days)

- [ ] **Wait out the delay.** The V1 voter body can still `vetoCouncilUpgrade()` during it.

- [ ] **Dry-run.**

  ```bash
  just upgrade-simulate <proxy> <chain>
  ```

- [ ] **Execute.** Permissionless — anyone may run it.

  ```bash
  just upgrade <deployer> <proxy> <chain>
  ```

  This calls `upgradeToAndCall(implementationV2, reinitializeFromV1())`. `reinitializeFromV1` takes no arguments, so executing the
  upgrade cannot influence the owner or the vesting schedule; both were fixed in step 1.

- [ ] **Confirm the proxy runs the V2 implementation.**

  ```bash
  cast call <proxy> "implementation()(address)" --rpc-url <chain>
  ```

- [ ] **Confirm the owner is the timelock.**

  ```bash
  cast call <proxy> "owner()(address)" --rpc-url <chain>
  ```
