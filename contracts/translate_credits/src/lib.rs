#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, symbol_short, Address, BytesN, Env, Symbol, Vec,
};

#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[contracterror]
#[repr(u32)]
pub enum ContractError {
    AlreadyInitialized = 1,
    NotInitialized = 2,
    Unauthorized = 3,
    InvalidAmount = 4,
    InsufficientBalance = 5,
    DuplicateRecord = 6,
    RecordExpired = 7,
    InvalidNonce = 8,
    TimestampInFuture = 9,
    BatchSizeExceeded = 10,
    CannotTransferToSelf = 11,
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct OfflineUsageRecord {
    pub record_id: BytesN<32>,     // Cryptographic SHA-256 hash or UUID bytes of the offline transaction
    pub user: Address,              // Account consuming credits
    pub amount: i128,               // Amount of credits consumed offline
    pub timestamp: u64,             // Device timestamp when usage occurred (Unix seconds)
    pub expiry: u64,                // Expiry timestamp (deadline for sync)
    pub nonce: u64,                 // Sequential nonce for replay prevention per user
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct ProcessedRecord {
    pub user: Address,
    pub amount: i128,
    pub processed_at: u64,
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    Balance(Address),
    UserNonce(Address),
    ProcessedRecord(BytesN<32>),
}

#[contract]
pub struct TranslateCreditsContract;

#[contractimpl]
impl TranslateCreditsContract {
    /// Initialize the contract and set the admin address
    pub fn initialize(env: Env, admin: Address) -> Result<(), ContractError> {
        if env.storage().instance().has(&DataKey::Admin) {
            return Err(ContractError::AlreadyInitialized);
        }
        env.storage().instance().set(&DataKey::Admin, &admin);
        Ok(())
    }

    /// Read the admin address
    pub fn get_admin(env: Env) -> Result<Address, ContractError> {
        env.storage()
            .instance()
            .get(&DataKey::Admin)
            .ok_or(ContractError::NotInitialized)
    }

    /// Query the credit balance of a specific address
    pub fn balance(env: Env, user: Address) -> i128 {
        env.storage().instance().get(&DataKey::Balance(user)).unwrap_or(0)
    }

    /// Query the current sequence nonce for a user
    pub fn get_user_nonce(env: Env, user: Address) -> u64 {
        env.storage()
            .persistent()
            .get(&DataKey::UserNonce(user))
            .unwrap_or(0)
    }

    /// Check if an offline transaction record ID has already been processed on-chain
    pub fn is_record_processed(env: Env, record_id: BytesN<32>) -> bool {
        env.storage()
            .persistent()
            .has(&DataKey::ProcessedRecord(record_id))
    }

    /// Mint new credits (restricted to admin)
    pub fn mint(env: Env, to: Address, amount: i128) -> Result<(), ContractError> {
        if amount <= 0 {
            return Err(ContractError::InvalidAmount);
        }
        let admin = Self::get_admin(env.clone())?;
        admin.require_auth();

        let current_balance = Self::balance(env.clone(), to.clone());
        let new_balance = current_balance
            .checked_add(amount)
            .ok_or(ContractError::InvalidAmount)?;

        env.storage()
            .instance()
            .set(&DataKey::Balance(to.clone()), &new_balance);

        env.events().publish((symbol_short!("mint"), to), amount);
        Ok(())
    }

    /// Burn credits (used when user spends translation credits online)
    pub fn burn(env: Env, from: Address, amount: i128) -> Result<(), ContractError> {
        if amount <= 0 {
            return Err(ContractError::InvalidAmount);
        }
        from.require_auth();

        let current_balance = Self::balance(env.clone(), from.clone());
        if current_balance < amount {
            return Err(ContractError::InsufficientBalance);
        }

        let new_balance = current_balance - amount;
        env.storage()
            .instance()
            .set(&DataKey::Balance(from.clone()), &new_balance);

        env.events().publish((symbol_short!("burn"), from), amount);
        Ok(())
    }

    /// Transfer credits between users (P2P transfer)
    pub fn transfer(env: Env, from: Address, to: Address, amount: i128) -> Result<(), ContractError> {
        if amount <= 0 {
            return Err(ContractError::InvalidAmount);
        }
        from.require_auth();

        if from == to {
            return Err(ContractError::CannotTransferToSelf);
        }

        let from_balance = Self::balance(env.clone(), from.clone());
        if from_balance < amount {
            return Err(ContractError::InsufficientBalance);
        }

        let to_balance = Self::balance(env.clone(), to.clone());
        let new_to_balance = to_balance
            .checked_add(amount)
            .ok_or(ContractError::InvalidAmount)?;

        env.storage()
            .instance()
            .set(&DataKey::Balance(from.clone()), &(from_balance - amount));
        env.storage()
            .instance()
            .set(&DataKey::Balance(to.clone()), &new_to_balance);

        env.events()
            .publish((symbol_short!("transfer"), from, to), amount);
        Ok(())
    }

    /// Synchronize a single offline credit usage record with on-chain balance verification,
    /// duplicate detection (UUID verification), replay prevention (nonce check), and expiry validation.
    pub fn sync_offline_usage(env: Env, record: OfflineUsageRecord) -> Result<(), ContractError> {
        // 1. Authorisation & Cryptographic Verification
        record.user.require_auth();

        // 2. Input Validation
        if record.amount <= 0 {
            return Err(ContractError::InvalidAmount);
        }

        // 3. Expiry Timestamp Validation
        let current_ledger_time = env.ledger().timestamp();
        if current_ledger_time >= record.expiry {
            return Err(ContractError::RecordExpired);
        }

        // 4. Timestamp Drift Check (Reject timestamps > 5 mins in future)
        if record.timestamp > current_ledger_time + 300 {
            return Err(ContractError::TimestampInFuture);
        }

        // 5. Duplicate Transaction Detection & Cryptographic UUID Hash Check
        let proc_key = DataKey::ProcessedRecord(record.record_id.clone());
        if env.storage().persistent().has(&proc_key) {
            return Err(ContractError::DuplicateRecord);
        }

        // 6. Replay Attack Prevention via Strict Sequence Nonce Verification
        let nonce_key = DataKey::UserNonce(record.user.clone());
        let current_nonce: u64 = env
            .storage()
            .persistent()
            .get(&nonce_key)
            .unwrap_or(0);

        let expected_nonce = current_nonce + 1;
        if record.nonce != expected_nonce {
            return Err(ContractError::InvalidNonce);
        }

        // 7. Balance Check & Offline Usage Validation
        let current_balance = Self::balance(env.clone(), record.user.clone());
        if current_balance < record.amount {
            return Err(ContractError::InsufficientBalance);
        }

        // 8. State Mutations: Update Balance, User Nonce, and Processed Record Store
        let new_balance = current_balance - record.amount;
        env.storage()
            .instance()
            .set(&DataKey::Balance(record.user.clone()), &new_balance);

        env.storage().persistent().set(&nonce_key, &record.nonce);

        let processed_record = ProcessedRecord {
            user: record.user.clone(),
            amount: record.amount,
            processed_at: current_ledger_time,
        };
        env.storage().persistent().set(&proc_key, &processed_record);

        // Extend TTL on persistent entries (low watermark = 100,000 ledgers ~ 5 days, extend by 518,400 ledgers ~ 30 days)
        env.storage().persistent().extend_ttl(&proc_key, 100_000, 518_400);
        env.storage().persistent().extend_ttl(&nonce_key, 100_000, 518_400);

        // 9. Emit Audit Event
        env.events().publish(
            (Symbol::new(&env, "offline_sync"), record.user, record.record_id),
            record.amount,
        );

        Ok(())
    }

    /// Batch Synchronize offline credit usage records (capped at 10 items per invocation for gas limits)
    pub fn batch_sync_offline_usage(
        env: Env,
        records: Vec<OfflineUsageRecord>,
    ) -> Result<u32, ContractError> {
        if records.len() > 10 {
            return Err(ContractError::BatchSizeExceeded);
        }

        let mut synced_count: u32 = 0;
        for record in records.iter() {
            Self::sync_offline_usage(env.clone(), record)?;
            synced_count += 1;
        }

        Ok(synced_count)
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use soroban_sdk::{testutils::Address as _, testutils::Ledger as _, Address, BytesN, Env, Vec};

    fn setup_test_env() -> (Env, Address, Address, TranslateCreditsContractClient<'static>) {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let user = Address::generate(&env);
        let contract_id = env.register_contract(None, TranslateCreditsContract);
        let client = TranslateCreditsContractClient::new(&env, &contract_id);

        client.initialize(&admin);
        client.mint(&user, &1000);

        (env, admin, user, client)
    }

    #[test]
    fn test_successful_offline_sync() {
        let (env, _admin, user, client) = setup_test_env();

        let record_id = BytesN::from_array(&env, &[1u8; 32]);
        let now = env.ledger().timestamp();

        let record = OfflineUsageRecord {
            record_id: record_id.clone(),
            user: user.clone(),
            amount: 100,
            timestamp: now,
            expiry: now + 3600,
            nonce: 1,
        };

        let result = client.sync_offline_usage(&record);
        assert_eq!(result, ());

        assert_eq!(client.balance(&user), 900);
        assert_eq!(client.get_user_nonce(&user), 1);
        assert!(client.is_record_processed(&record_id));
    }

    #[test]
    fn test_reject_duplicate_record_id() {
        let (env, _admin, user, client) = setup_test_env();

        let record_id = BytesN::from_array(&env, &[2u8; 32]);
        let now = env.ledger().timestamp();

        let record1 = OfflineUsageRecord {
            record_id: record_id.clone(),
            user: user.clone(),
            amount: 50,
            timestamp: now,
            expiry: now + 3600,
            nonce: 1,
        };

        client.sync_offline_usage(&record1);

        // Attempt duplicate record submission with nonce 2
        let record2 = OfflineUsageRecord {
            record_id: record_id.clone(),
            user: user.clone(),
            amount: 50,
            timestamp: now,
            expiry: now + 3600,
            nonce: 2,
        };

        let res = client.try_sync_offline_usage(&record2);
        assert_eq!(res, Err(Ok(ContractError::DuplicateRecord)));
    }

    #[test]
    fn test_reject_invalid_nonce_replay() {
        let (env, _admin, user, client) = setup_test_env();

        let record_id = BytesN::from_array(&env, &[3u8; 32]);
        let now = env.ledger().timestamp();

        // Nonce 5 instead of 1
        let record = OfflineUsageRecord {
            record_id,
            user: user.clone(),
            amount: 50,
            timestamp: now,
            expiry: now + 3600,
            nonce: 5,
        };

        let res = client.try_sync_offline_usage(&record);
        assert_eq!(res, Err(Ok(ContractError::InvalidNonce)));
    }

    #[test]
    fn test_reject_expired_record() {
        let (env, _admin, user, client) = setup_test_env();

        let record_id = BytesN::from_array(&env, &[4u8; 32]);
        let now = env.ledger().timestamp();

        // Expiry in past
        let record = OfflineUsageRecord {
            record_id,
            user: user.clone(),
            amount: 50,
            timestamp: now - 100,
            expiry: now - 1,
            nonce: 1,
        };

        let res = client.try_sync_offline_usage(&record);
        assert_eq!(res, Err(Ok(ContractError::RecordExpired)));
    }

    #[test]
    fn test_reject_insufficient_balance() {
        let (env, _admin, user, client) = setup_test_env();

        let record_id = BytesN::from_array(&env, &[5u8; 32]);
        let now = env.ledger().timestamp();

        // Spending 2000 when balance is 1000
        let record = OfflineUsageRecord {
            record_id,
            user: user.clone(),
            amount: 2000,
            timestamp: now,
            expiry: now + 3600,
            nonce: 1,
        };

        let res = client.try_sync_offline_usage(&record);
        assert_eq!(res, Err(Ok(ContractError::InsufficientBalance)));
    }

    #[test]
    fn test_batch_sync_offline_usage() {
        let (env, _admin, user, client) = setup_test_env();
        let now = env.ledger().timestamp();

        let mut records = Vec::new(&env);
        for i in 1..=3 {
            let mut id_arr = [0u8; 32];
            id_arr[0] = i as u8;
            let record_id = BytesN::from_array(&env, &id_arr);

            records.push_back(OfflineUsageRecord {
                record_id,
                user: user.clone(),
                amount: 100,
                timestamp: now,
                expiry: now + 3600,
                nonce: i as u64,
            });
        }

        let synced = client.batch_sync_offline_usage(&records);
        assert_eq!(synced, 3);
        assert_eq!(client.balance(&user), 700);
        assert_eq!(client.get_user_nonce(&user), 3);
    }
}
