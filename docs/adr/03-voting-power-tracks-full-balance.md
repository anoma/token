# Voting power tracks the full balance, including locked principal

`ERC20Votes` checkpoints voting units off `balanceOf`, so an account's voting weight is its **entire** balance — including the still-locked, non-transferable, vesting principal. This mirrors V1, where locked tokens *were* the voting weight. The alternative (counting only the unlocked/liquid balance) was rejected: at launch almost the entire supply is locked and vesting, so the owning Governor could never reach quorum and the token would be un-upgradeable until years into the vest.

## Consequences

- For roughly the first three years the owning Governor is steered predominantly by the locked cohort — majority team / investors / foundation. This concentration is **accepted as a known property** of a freshly-distributed token; there is **no token-level mitigation** (no cap, no exclusion of locked tokens). It is left to the external governance design and attenuates over the vest as tokens unlock, transfer, and re-delegate.
- Voting power still requires (self-)delegation, per `ERC20Votes`.
