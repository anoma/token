# XanV2 Upgrade — Deployment Checklist

Step 1 deploys both networks; steps 2 and 3 are then run on Sepolia first and on mainnet once the rehearsal has
completed. The token spec is [`docs/01-XanV2-upgrade.md`](docs/01-XanV2-upgrade.md) and the governance spec is
[`docs/02-XanV2-governance.md`](docs/02-XanV2-governance.md) — this document is the how, not the what.

## 1. Before you start

- [ ] **Create a fresh deployer wallet.** It must never have sent a transaction on any chain, and must be used for
      nothing else afterwards. Why this matters: [section 7](#7-why-a-fresh-wallet).

- [ ] **Confirm it is at nonce 0 on both chains.** Both commands must print `0`; if either does not, discard the wallet
      and create another.

  ```bash
  cast nonce <deployer> --rpc-url sepolia
  cast nonce <deployer> --rpc-url mainnet
  ```

- [ ] **Fund the wallet on both chains.** Inbound transfers do not consume its nonce.

> **Optional.** `implementationV2` is computable before it is deployed — one prediction covers both chains, same deployer and
> same nonce. Step 1 takes minutes, so this is not about saving time: it lets the council draft and review the step 2
> Safe transaction ahead of the deploy, and gives an independent check that the deployment landed where expected.
>
> ```bash
> cast compute-address <deployer> --nonce 9
> ```

## 2. Step 1 — Prepare (both networks)

Deploys the governance stack and the V2 implementation, baking the timelock into `implementationV2` as the token owner. Do this on
**both** chains before moving on: the stack is inert until step 2 schedules an upgrade, so a mainnet deployment sitting
unscheduled carries no risk to the token, and deploying both here pins them to the same nonces before the wallet is used
for anything else.

Run the block below for `sepolia`, then for `mainnet`.

- [ ] **Confirm `<council>` is the multisig for the new `XanUpgradeCouncilModule`** — _not_ V1's `governanceCouncil`,
      which is the Safe that performs step 2. It is baked into the module and cannot be changed afterwards.

- [ ] **Dry-run.**

  ```bash
  just prepare-upgrade-simulate <sender> <proxy> <council> <chain>
  ```

- [ ] **Check the printed transaction list against the [address map](#6-address-map).** Ten transactions, `implementationV2` last.
      **Stop if it differs** — the nonce assignments have moved, so the contracts will not land where the map says.

- [ ] **Broadcast.**

  ```bash
  just prepare-upgrade <deployer> <sender> <proxy> <council> <chain>
  ```

- [ ] **Confirm the deployer no longer holds the timelock admin** (nonce 8 renounced it). Must print `false`.

  ```bash
  cast call <timelock> "hasRole(bytes32,address)(bool)" \
    $(cast call <timelock> "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url <chain>) <sender> --rpc-url <chain>
  ```

- [ ] **Verify the contracts on the explorers.**

  ```bash
  just verify-governance <timelock> <governor> <council-module> <implementation-v2> <chain>
  ```

- [ ] **Record all four addresses** (timelock, governor, council module, implementation V2).

Once both chains are done:

- [ ] **Confirm the two implementation V2 deployments are byte-identical.** Both commands must print the same hash. Its
      constructor arguments are the nonce-0 timelock and two constants, all identical across the chains, so the runtime
      code must match too — a mismatch means something diverged.

  ```bash
  cast keccak $(cast code <implementationV2> --rpc-url sepolia)
  cast keccak $(cast code <implementationV2> --rpc-url mainnet)
  ```

  The council module is expected **not** to match if the two chains use different council multisigs; that address is an
  immutable in its runtime code.

## 3. Step 2 — Schedule

A Safe transaction, not a `forge script` step — `forge` cannot broadcast as the Safe. Run on Sepolia first; repeat on
mainnet once the rehearsal has completed.

- [ ] **Execute `scheduleCouncilUpgrade(implementationV2)` on the V1 proxy** from V1's `governanceCouncil` multisig.

- [ ] **Confirm it landed.** The address must equal `implementationV2`; the `uint48` (`endTime`) is the timestamp step 3
      becomes executable at.

  ```bash
  cast call <proxy> "scheduledCouncilUpgrade()(address,uint48)" --rpc-url <chain>
  ```

- [ ] **Record the executable-at timestamp.** It is the scheduling time plus `DELAY_DURATION`, which is 14 days.

The alternative V1 path is the voter-body quorum — hold `castVote(implementationV2)` to quorum, then `scheduleVoterBodyUpgrade()`.
The council path is the expected one.

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

- [ ] **Confirm the proxy runs implementation V2.**

  ```bash
  cast call <proxy> "implementation()(address)" --rpc-url <chain>
  ```

- [ ] **Confirm the owner is the timelock.**

  ```bash
  cast call <proxy> "owner()(address)" --rpc-url <chain>
  ```

## 5. Sepolia first

Run steps 2 and 3 on Sepolia well ahead of mainnet, to exercise the upgrade end to end and to give the frontend a live
integration target. Nothing about the deployment differs — the two chains carry the same parameters, so the rehearsal is
byte-for-byte what mainnet will run.

One consequence to expect rather than debug: `XAN_VESTING_START` is `1793448000` (2026-10-31 12:00 UTC) on Sepolia too,
so before that date nothing has vested. Principal stays fully locked and `unlock()` reverts `NothingToUnlock`. The
rehearsal therefore exercises the upgrade itself, delegation and voting, and transfers of already-liquid balances — but
not vesting progress.

## 6. Address map

`just prepare-upgrade` broadcasts ten transactions. Only four create contracts; the six role transactions consume nonces
without deploying anything. The `PROPOSER_ROLE()`-style reads are staticcalls and consume no nonce.

| Nonce | Transaction                           | Deploys                     |
| ----- | ------------------------------------- | --------------------------- |
| 0     | `new TimelockController`              | **TimelockController**      |
| 1     | `new XanGovernor`                     | **XanGovernor**             |
| 2     | `new XanUpgradeCouncilModule`         | **XanUpgradeCouncilModule** |
| 3     | `grantRole(PROPOSER, governor)`       | —                           |
| 4     | `grantRole(CANCELLER, governor)`      | —                           |
| 5     | `grantRole(PROPOSER, module)`         | —                           |
| 6     | `grantRole(CANCELLER, module)`        | —                           |
| 7     | `grantRole(EXECUTOR, address(0))`     | —                           |
| 8     | `renounceRole(DEFAULT_ADMIN, sender)` | —                           |
| 9     | `prepareUpgrade`                      | **XanV2 implementation**    |

`<sender>` (the address behind `<deployer>`) is the transient timelock admin: it wires the roles at nonces 3–7 and
renounces its admin at nonce 8, after which only governance can change roles.

## 7. Why a fresh wallet

A `CREATE` address is `keccak256(rlp([sender, nonce]))` — it depends only on the deployer and the nonce, **not** on the
bytecode or the constructor arguments. A fresh wallet starting at nonce `0` therefore lands the whole stack on identical
addresses on Sepolia and mainnet, even where the two deployments differ (the council multisig). Cross-chain parity is
already the case for V1, whose implementation sits at `0x03997b568FE70E91A53c458DC19dc29e0bC2735E` with an identical
codehash on Sepolia and mainnet.

Three rules keep the mapping intact:

- **One wallet, nothing else.** A single stray transaction — a test transfer, a token approval, a cancelled attempt —
  shifts every address after it.
- **A mined-but-reverted transaction still consumes its nonce.** Nonces are per-chain, so a botched Sepolia run
  desynchronizes Sepolia from mainnet. Recovery is a fresh wallet and a rerun on **both** chains: the rehearsal is
  effectively one-shot.
- **Funding is safe.** Sending ETH _to_ the wallet is inbound and does not consume its nonce.
