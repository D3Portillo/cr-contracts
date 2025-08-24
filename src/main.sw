contract;

use std::identity::Identity;
use std::asset_id::AssetId;
use std::asset::transfer;
use std::storage::storage_map::*;
use std::storage::storage_vec::*;
use std::call_frames::msg_asset_id;
use std::context::msg_amount;
use std::address::Address;

use ownership::{_owner, initialize_ownership, only_owner};
use src5::{SRC5, State};

const ZERO_ADDRESS: Identity = Identity::Address(Address::zero());

impl SRC5 for Contract {
    #[storage(read)]
    fn owner() -> State {
      _owner()
    }
}

abi SimplePoolContract {
  // Contract initialization

  // * ADMIN FUNCTIONS
  // Ownership setup
  #[storage(read, write)]
  fn initialize();

  // Start challenge + accept deposits
  #[storage(read, write)]
  fn start_challenge();

  // Stop event + distribute rewards if possible
  #[storage(read, write)]
  fn stop_challenge(winner_riot_id: u16, disburse_rewards: bool, fees_bps_1000: u8);

  // To be used in case of assets locked (edge case)
  #[storage(read, write)]
  fn unsecure_claim_deposits(recipient: Identity);

  // * EXTERNAL FUNCTIONS
  // Send assets to pool and bet for riot's id
  #[storage(read, write), payable]
  fn deposit_for_riot(riot_id: u16) -> Identity;

  // Get "claimed" rewards for user
  #[storage(read)]
  fn get_claimable_balance(backer: Identity) -> u64;

  // Get the delegated balance of `backer` for `riot_id`
  #[storage(read)]
  fn get_backing_balance(riot_id: u16, backer: Identity) -> u64;

  // Get total delegated balance for `riot_id`
  #[storage(read)]
  fn get_riot_tvl(riot_id: u16) -> u64;

  // Total Locked Value in this pool
  fn get_pool_tvl() -> u64;

  // Get riot backers
  #[storage(read)]
  fn get_riot_backers(riot_id: u16) -> u64;

  // Get backer at index
  #[storage(read)]
  fn get_backer_at_index(index: u64) -> Identity;

  // Get total pool backers
  #[storage(read)]
  fn get_pool_backers() -> u64;

  // Get if pool is active
  #[storage(read)]
  fn is_active() -> bool;

  // Get pool winner riot_id
  #[storage(read)]
  fn winner_riot_id() -> u16;
}

storage {
  // map(address -> map(riot_id -> amount)) - using composite key approach
  deposits: StorageMap<(Identity, u16), u64> = StorageMap {},
  // Track pool for all backers
  backers: StorageVec<Identity> = StorageVec {},
  // To track if an address is a backer
  is_backer: StorageMap<Identity, bool> = StorageMap {},
  // Flag if the pool is active
  is_active: bool = false,
  // To track pool winner riot_id
  winner_riot_id: u16 = 0,
  // Help notify total rewards
  rewards_disbursed: u64 = 0,
}


#[storage(read)]
fn _only_active_pool() {
  require(storage.is_active.read(), "InactivePool");
}

#[storage(read)]
fn _get_riot_tvl(riot_id: u16) -> u64 {
  // @dev `ZERO_ADDRESS` is used for accounting riot's TVL
  let global_deposit_key = (ZERO_ADDRESS, riot_id);
  storage.deposits.get(global_deposit_key).try_read().unwrap_or(0)
}

impl SimplePoolContract for Contract {
  // A simple deposit contract that allow users to deposit (bet)
  // assets for a specific riot

  #[storage(read, write)]
  fn initialize() {
    // Set `sender` as initial owner
    let sender = msg_sender().unwrap();
    initialize_ownership(sender);
  }

  #[storage(read, write)]
  fn start_challenge() {
    only_owner();

    require(!storage.is_active.read(), "PoolAlreadyActive");
    storage.is_active.write(true);
    // Implementation for starting a challenge
  }

  #[storage(read, write)]
  fn stop_challenge(winner_riot_id: u16, disburse_rewards: bool, fees_bps_1000: u8) {
    // Implementation for stopping a challenge
    // NOTE: 1bps = 0.1% (1 / 1_000)

    only_owner();
    _only_active_pool();

    // We reward the users who backed the winning riot
    // by distributing the collected fees proportionally.
    // A fee_bps is collected and sent to OWNER wallet.

    let pool_tvl: u64 = std::context::this_balance(AssetId::base());
    let winner_riot_tvl = _get_riot_tvl(winner_riot_id);

    // Amount to reward is total TVL - Winner Backers TVL (so we send it as their initial deposit)
    // And last we subtract fees (if non-zero rewards)
    let mut reward_amount = pool_tvl - winner_riot_tvl;

    // Fees calculation
    let fees_taken: u64 = fees_bps_1000.as_u64();
    let fee_amount = (reward_amount * fees_taken) / 1_000;

    if (reward_amount > fee_amount) {
      // Substract fees to be collected
      reward_amount = reward_amount - fee_amount;
    }

    if (winner_riot_tvl > 0) {
      for item in storage.backers.iter() {
        let backer = item.read();
        let backer_deposit = storage.deposits.get((backer, winner_riot_id)).try_read().unwrap_or(0);
        if backer_deposit > 0 {
          // Logic to handle backers who "won" the bet
          let backer_reward = (backer_deposit * reward_amount) / winner_riot_tvl;
          // Send backer's initial deposit
          transfer(backer, AssetId::base(), backer_deposit + backer_reward);
        }
      }
    }

    if (disburse_rewards) {
      // Update total rewards
      storage.rewards_disbursed.write(reward_amount);
    }

    // Mark pool as inactive
    storage.is_active.write(false);
    // Store winner riot id
    storage.winner_riot_id.write(winner_riot_id);
  }

  #[storage(read, write)]
  fn unsecure_claim_deposits(recipient: Identity) {
    only_owner();

    let total_holdings = std::context::this_balance(AssetId::base());
    require(total_holdings > 0, "NO_FUNDS");
    transfer(recipient, AssetId::base(), total_holdings);

    // Mark pool as inactive
    storage.is_active.write(false);
  }

  // @dev We assume riot_id is defined off-chain (CR DBs)
  #[storage(read, write), payable]
  fn deposit_for_riot(riot_id: u16) -> Identity {
    // Ensure deposits are done only when active
    _only_active_pool();

    // We expect deposit token value to be USDC/USDT
    // For now Native is fine
    // Implementation for depositing for riot

    let sender = msg_sender().unwrap();
    let asset_amount = msg_amount();
    let underlying_asset = msg_asset_id();

    // 1. Check for the underlying asset
    require(underlying_asset == AssetId::base(), "INVALID_ASSET_ID");

    // 2. Check if amount if valid (gt ZERO)
    require(asset_amount > 0, "INVALID_AMOUNT");

    // 3. Update the deposit mapping using composite key approach
    let deposit_key = (sender, riot_id);

    // Get current amount for this sender-riot combination and add new deposit
    let current_amount = storage.deposits.get(deposit_key).try_read().unwrap_or(0);
    storage.deposits.insert(deposit_key, current_amount + asset_amount);

    // Update the mapping with the new total
    // 4. Use address ZERO as the "global" backing address for a riot
    let global_deposit_key = (ZERO_ADDRESS, riot_id);
    let global_current_amount = storage.deposits.get(global_deposit_key).try_read().unwrap_or(0);
    storage.deposits.insert(global_deposit_key, global_current_amount + asset_amount);

    // 5. Update backers count
    let is_backer = storage.is_backer.get(sender).try_read().is_some();

    // Append only if not a backer
    if !is_backer {
      storage.backers.push(sender);
      storage.is_backer.insert(sender, true);
    }

    // Return the sender's identity
    sender
  }

  #[storage(read)]
  fn get_claimable_balance(backer: Identity) -> u64 {
    let winner_riot_id = storage.winner_riot_id.read();
    if (winner_riot_id == 0) {
      // Early exit when no winner defined
      return 0;
    }

    let backer_deposit = storage.deposits.get((backer, winner_riot_id)).try_read().unwrap_or(0);
    let winner_riot_tvl = _get_riot_tvl(winner_riot_id);

    if (winner_riot_tvl == 0 || backer_deposit == 0) {
      // Early exit if nothing to earn
      return 0;
    }

    let rewards_given = storage.rewards_disbursed.read();
    let backer_reward = (backer_deposit * rewards_given) / winner_riot_tvl;
    backer_deposit + backer_reward
  }

  #[storage(read)]
  fn get_backing_balance(riot_id: u16, sender: Identity) -> u64 {
    let deposit_key = (sender, riot_id);
    storage.deposits.get(deposit_key).try_read().unwrap_or(0)
  }

  #[storage(read)]
  fn get_riot_tvl(riot_id: u16) -> u64 {
    _get_riot_tvl(riot_id)
  }

  #[storage(read)]
  fn get_riot_backers(riot_id: u16) -> u64 {
    // Not so-good approach, but for testing out.
    // We iterate over all backers and check if they have backed this riot
    let mut count = 0;
    for item in storage.backers.iter() {
      let backer = item.read();
      if storage.deposits.get((backer, riot_id)).try_read().unwrap_or(0) > 0 {
        count += 1;
      }
    }
    count
  }

  fn get_pool_tvl() -> u64 {
    std::context::this_balance(AssetId::base())
  }

  #[storage(read)]
  fn get_backer_at_index(index: u64) -> Identity {
    require(index < storage.backers.len(), "INDEX_OUT_OF_BOUNDS");
    storage.backers.get(index).unwrap().read()
  }

  #[storage(read)]
  fn get_pool_backers() -> u64 {
    storage.backers.len()
  }

  #[storage(read)]
  fn is_active() -> bool {
    storage.is_active.read()
  }

  #[storage(read)]
  fn winner_riot_id() -> u16 {
    storage.winner_riot_id.read()
  }
}

// *** TEST ***
#[test]
fn pool_tvl_is_zero() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  assert_eq(caller.get_pool_tvl(), 0);
}

#[test]
fn pool_is_active() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  caller.initialize();
  caller.start_challenge();

  assert_eq(caller.is_active(), true);
}

#[test]
fn pool_is_inactive() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  assert_eq(caller.is_active(), false);
}



#[test]
fn deposit_1_coin_for_riot_1() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  let riot_id = 1;
  let sending_coins = 1;

  caller.initialize();
  caller.start_challenge();

  let backer = caller.deposit_for_riot{
    coins: sending_coins,
  }(riot_id);

  assert_eq(caller.get_pool_tvl(), sending_coins);
  assert_eq(caller.get_riot_tvl(riot_id), sending_coins);
  assert_eq(caller.get_backing_balance(riot_id, backer), sending_coins);
}


#[test(should_revert)]
fn should_revert_when_no_coins() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  let riot_id = 1;

  caller.deposit_for_riot{
    coins: 0,
  }(riot_id);
}

#[test(should_revert)]
fn is_initializable_and_not_reentrant() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  caller.initialize();

  // Calling initialize again should fail
  caller.initialize();
}

#[test]
fn can_get_backer_at_index_0() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  caller.initialize();
  caller.start_challenge();

  let backer = caller.deposit_for_riot{
    coins: 1,
  }(1);

  assert_eq(caller.get_backer_at_index(0), backer);
}

#[test]
fn total_backers_is_1() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  let riot_id = 1;

  caller.initialize();
  caller.start_challenge();

  caller.deposit_for_riot{
    coins: 1,
  }(riot_id);

  assert_eq(caller.get_pool_backers(), 1);
  assert_eq(caller.get_riot_backers(riot_id), 1);
}

#[test(should_revert)]
fn fails_when_start_and_stopping_challenge() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  let riot_id = 1;

  caller.initialize();
  caller.start_challenge();

  assert_eq(caller.get_pool_backers(), 0);

  caller.stop_challenge(riot_id, true, 0);
  caller.deposit_for_riot{
    coins: 1,
  }(riot_id);
}

#[test]
fn unsecure_simulate_claim_deposits() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  caller.initialize();
  caller.start_challenge();

  caller.deposit_for_riot{
    coins: 1,
  }(1);

  assert_eq(caller.get_pool_tvl(), 1);

  // Simulate claiming deposits without proper checks
  let self_contract_identity = Identity::ContractId(ContractId::from(CONTRACT_ID));
  caller.unsecure_claim_deposits(self_contract_identity);
}

#[test(should_revert)]
fn should_revert_on_unsecure_start_call() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  caller.initialize();

  caller.start_challenge();
  caller.start_challenge();
}


#[test]
fn is_payouts_working() {
  let caller = abi(SimplePoolContract, CONTRACT_ID);
  let riot_id = 1;

  caller.initialize();
  caller.start_challenge();

  assert_eq(caller.get_pool_backers(), 0);

  caller.stop_challenge(riot_id, true, 0);
  assert_eq(caller.winner_riot_id(), riot_id);
}
