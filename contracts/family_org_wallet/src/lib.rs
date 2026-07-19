#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol};

mod token {
    soroban_sdk::contractimport!(
        file = "../target/wasm32-unknown-unknown/release/translate_credits.wasm"
    );
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct MemberInfo {
    pub daily_limit: i128,
    pub last_withdraw_timestamp: u64,
    pub withdrawn_today: i128,
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Owner,
    Member(Address),
}

#[contract]
pub struct FamilyOrgWalletContract;

#[contractimpl]
impl FamilyOrgWalletContract {
    /// Initialize the contract with the primary owner address
    pub fn initialize(env: Env, owner: Address) {
        if env.storage().instance().has(&DataKey::Owner) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Owner, &owner);
    }

    /// Add a member with a specific daily limit (restricted to owner)
    pub fn add_member(env: Env, member: Address, daily_limit: i128) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).expect("not initialized");
        owner.require_auth();

        if daily_limit < 0 {
            panic!("limit cannot be negative");
        }

        let key = DataKey::Member(member.clone());
        let info = MemberInfo {
            daily_limit,
            last_withdraw_timestamp: 0,
            withdrawn_today: 0,
        };

        env.storage().persistent().set(&key, &info);

        // Publish event
        env.events().publish((Symbol::new(&env, "member_added"), member), daily_limit);
    }

    /// Remove a member (restricted to owner)
    pub fn remove_member(env: Env, member: Address) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).expect("not initialized");
        owner.require_auth();

        let key = DataKey::Member(member.clone());
        if !env.storage().persistent().has(&key) {
            panic!("not a member");
        }

        env.storage().persistent().remove(&key);

        // Publish event
        env.events().publish((Symbol::new(&env, "member_removed"),), member);
    }

    /// Withdraw funds from the family/org wallet (subject to daily limits for members)
    pub fn withdraw(env: Env, member: Address, to: Address, amount: i128, token_contract: Address) {
        member.require_auth();

        if amount <= 0 {
            panic!("amount must be positive");
        }

        let owner: Address = env.storage().instance().get(&DataKey::Owner).expect("not initialized");

        // If the owner is withdrawing, there are no limits
        if member == owner {
            let client = token::Client::new(&env, &token_contract);
            client.transfer(&env.current_contract_address(), &to, &amount);
            env.events().publish((Symbol::new(&env, "owner_withdrew"), to), amount);
            return;
        }

        // For regular members, enforce daily limits
        let key = DataKey::Member(member.clone());
        if !env.storage().persistent().has(&key) {
            panic!("unauthorized member");
        }

        let mut info: MemberInfo = env.storage().persistent().get(&key).unwrap();
        let current_time = env.ledger().timestamp();
        let seconds_in_day = 86400u64;

        // Reset limit check if 24 hours have passed
        if current_time - info.last_withdraw_timestamp >= seconds_in_day {
            info.withdrawn_today = 0;
        }

        if info.withdrawn_today + amount > info.daily_limit {
            panic!("daily limit exceeded");
        }

        // Update member limits
        info.withdrawn_today += amount;
        info.last_withdraw_timestamp = current_time;
        env.storage().persistent().set(&key, &info);

        // Execute transfer
        let client = token::Client::new(&env, &token_contract);
        client.transfer(&env.current_contract_address(), &to, &amount);

        // Publish event
        env.events().publish((Symbol::new(&env, "member_withdrew"), member, to), amount);
    }
}
