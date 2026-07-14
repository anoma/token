# Timestamp-based voting clock (EIP-6372)

`clock()` returns `block.timestamp` and `CLOCK_MODE()` returns `"mode=timestamp"`, overriding OpenZeppelin's default block-number clock. This aligns the `ERC20Votes` clock with the timestamp-based vesting schedule and lets the owning Governor denominate `votingDelay`/`votingPeriod` in **seconds** (human-meaningful and stable regardless of any future block-time change).

## Considered options

- **Block-number clock (OZ default)** — rejected: governance windows would be measured in blocks and the clock would be misaligned with the timestamp-based vesting.

## Consequences

- **One-time and irreversible.** Vote checkpoints and the total-supply checkpoint are keyed by this clock; changing it after deployment would corrupt checkpoint history.
- The usual objection to timestamp clocks (proposer timestamp manipulation) **does not apply**: post-Merge Ethereum has fixed 12-second slots, and the token and its governance are deployed **only on Ethereum L1**, so portability concerns are moot as well. "Ethereum-L1-only" is the governing constraint behind this choice.
