# Deployment Checklist

Step 1 deploys both networks; steps 2 and 3 are then run on Sepolia first and on mainnet once the rehearsal has completed. The token spec is [`docs/01-XanV2-upgrade.md`](docs/01-XanV2-upgrade.md) and the governance spec is [`docs/02-XanV2-governance.md`](docs/02-XanV2-governance.md). Section 5 deploys `XanV2Vesting` (see [`docs/03-XanV2Vesting.md`](docs/03-XanV2Vesting.md)).

## 1. Before you start

- [x] **Create a fresh deployer wallet.** It must never have sent a transaction on any chain, and must be used for nothing else afterwards, except to deploy `XanV2Vesting` in [section 5](#5-xanv2vesting).

  Deployer wallet: `0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f` ([mainnet](https://etherscan.io/address/0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f), [sepolia](https://sepolia.etherscan.io/address/0xc461247a7375cF7c70a576d636aA3dd38ff3bb2f))

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

- [ ] **Broadcast.**

  ```bash
  just prepare-upgrade <deployer> <sender> <proxy> <council> <chain>
  ```

  - [ ] Sepolia: [broadcast/PrepareXanV2Upgrade.s.sol/11155111/run-1786972071911.json](broadcast/PrepareXanV2Upgrade.s.sol/11155111/run-1786972071911.json)
  - [ ] Mainnet: [broadcast/PrepareXanV2Upgrade.s.sol/1/run-1786972324372.json](broadcast/PrepareXanV2Upgrade.s.sol/1/run-1786972324372.json)

- [ ] **Confirm the deployer no longer holds the timelock admin** (nonce 8 renounced it). Must print `false`.

  ```bash
  cast call <timelock> "hasRole(bytes32,address)(bool)" \
    $(cast call <timelock> "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url <chain>) <sender> --rpc-url <chain>
  ```

- [ ] **Verify the contracts on the explorers.**

  ```bash
  just verify-governance <timelock> <governor> <council-module> <implementation-v2> <chain>
  ```

- [ ] **Record all four addresses** (timelock, governor, council module, V2 implementation) in [README.md](README.md#deployed-contracts)

Once both chains are done:

- [ ] **Confirm the two V2 implementation deployments are byte-identical.** Both commands must print the same hash. Its constructor arguments are the nonce-0 timelock and two constants, all identical across the chains.

  ```bash
  cast keccak $(cast code <implementationV2> --rpc-url sepolia)
  cast keccak $(cast code <implementationV2> --rpc-url mainnet)
  ```

  Result: `0xc67381bca50028ed121ebb36280275cb22efbb26aa09c51815010ffc08940da6`

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

## 5. XanV2Vesting

Deploys the `XanV2Vesting` implementation and its UUPS proxy for the eligible recipients that the V1 genesis distribution did not contain. The deployer of section 1 deploys both at the same nonces on both chains, so both networks share the addresses. Run on Sepolia first; repeat on mainnet once the rehearsal has completed.

- [ ] **Confirm the deployer of section 1 is at nonce 13 on both chains.** Both commands must print 13, and the wallet must send nothing else on either chain until both deployments are done. If a chain prints a lower nonce, raise it with transactions that send 0 ETH from the deployer to itself. A failed transaction also uses its nonce. The implementation lands at the address for nonce 13 and the proxy at the address for nonce 14: `0x999b1a6641555816bb9a24692626963D7abe62D7` and `0xe1F1599b47cbF5ca681109f8129f289FD29cfD49`. On both chains, the deploy script reverts before it broadcasts anything if the proxy would land elsewhere.

  ```bash
  cast nonce <sender> --rpc-url sepolia
  cast nonce <sender> --rpc-url mainnet
  cast compute-address <sender> --nonce <nonce>
  ```

- [ ] **Confirm the council multisig is still `Parameters.COUNCIL_MULTISIG`** (`0x0efb18adf9638495dBEE87b98b1e21cEE7bf1116`). The deployment script makes it the owner (see [ADR-10](docs/adr/10-the-council-multisig-owns-xanv2vesting.md)). If this does not print it, update `src/libs/Parameters.sol` first.

  ```bash
  cast call <council-module> "getCouncil()(address)" --rpc-url <chain>
  ```

- [ ] **Dry-run.** The printed `proxy` and `implementation` must be the addresses of the first step.

  ```bash
  just deploy-vesting-simulate <sender> <chain>
  ```

- [ ] **Broadcast.**

  ```bash
  just deploy-vesting <deployer> <sender> <chain>
  ```

- [ ] **Verify the implementation on the explorers.** `just deploy-vesting` already verifies both contracts on Etherscan.

  ```bash
  just verify-impl <implementation> src/XanV2Vesting.sol:XanV2Vesting <chain>
  ```

- [ ] **Record the proxy and implementation addresses** in [README.md](README.md#deployed-contracts).

- [ ] **Write the recipients** into the empty list of `script/xan-v2-vesting-recipients.json`: the checked addresses with their locked tranches, and `totalPrincipal`, their sum (see section [Deployment](docs/03-XanV2Vesting.md#11-deployment)). Generate the payloads and commit them with the recipient file. The script stops on an entry that `addRecipients` rejects and on a sum that differs from `totalPrincipal`, and CI fails while a payload is out of date.

  ```bash
  just vesting-recipients-payload
  ```

- [ ] **Add the recipients** with the payload of the chain:
  - [ ] [safe-payloads/addRecipients_to_xanV2Vesting_sepolia.json](safe-payloads/addRecipients_to_xanV2Vesting_sepolia.json)
  - [ ] [safe-payloads/addRecipients_to_xanV2Vesting_mainnet.json](safe-payloads/addRecipients_to_xanV2Vesting_mainnet.json)

  One signer of the council multisig puts the transaction in the queue:

  1. In the Safe app of the council multisig, open the Transaction Builder.
  2. Drag the payload file into the Transaction Builder.
  3. Create the batch and send it.

  Each signer compares the data of the queued transaction with `data` in the payload file. A signer signs only if the two are the same.

- [ ] **Send any liquid tranches directly.** `XanV2Vesting` holds only the locked tranches.

- [ ] **Fund it.** The council multisig transfers XAN to the contract and tops it up periodically. Before each top-up, this prints the XAN to send now so that every unlock until the next top-up at `<timestamp>` (Unix time) succeeds (see [Top-up amount](docs/03-XanV2Vesting.md#top-up-amount)). `just vesting-top-up-full <chain>` prints the XAN that covers every remaining unlock instead.

  ```bash
  just vesting-top-up-until <timestamp> <chain>
  ```

Once both chains are done:

- [ ] **Confirm the two implementation deployments are byte-identical.** Both commands must print the same hash. The constructor argument, the XAN token proxy, has the same address on both chains.

  ```bash
  cast keccak $(cast code <implementation> --rpc-url sepolia)
  cast keccak $(cast code <implementation> --rpc-url mainnet)
  ```
