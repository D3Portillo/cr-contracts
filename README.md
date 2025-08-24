# Code Riots Sway Smart Contracts

A simple implementation of a decentralized betting platform using Sway smart contracts.

# Logic chips:

- Contract is initializable (owner = house)
- owner can start a challenge (time to be live, fees to be taken)
- owner can cancel a challenge (anyone can withdraw their assets - no fees taken)
- owner can finalize a challenge (in case time's up before - pick winner and fees are TAKEN)
- backers can deposit for their favorite riots
- backers can withdraw their deposits (if challenge is canceled)
- backers can claim rewards (deposits + earned, if challenge is successful)
- backers can see the total TVL delegated to a riot
- backers can see the global accumulated TVL
- riots are off-chain hosted and have a consistent id across all challenges
- fails when not initialized
- we can see total BKRs
