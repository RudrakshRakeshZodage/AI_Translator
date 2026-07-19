#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol};

mod token {
    soroban_sdk::contractimport!(
        file = "../target/wasm32-unknown-unknown/release/translate_credits.wasm"
    );
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct SubscriptionState {
    pub end_time: u64,
    pub plan_id: u32,
    pub token_contract: Address,
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    Subscription(Address),
    MerchantAddress,
}

#[contract]
pub struct SubscriptionsContract;

#[contractimpl]
impl SubscriptionsContract {
    /// Initialize with Admin and Merchant address to collect subscription funds
    pub fn initialize(env: Env, admin: Address, merchant_address: Address) {
        if env.storage().instance().has(&DataKey::Admin) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::MerchantAddress, &merchant_address);
    }

    /// Purchase or renew a subscription
    pub fn subscribe(
        env: Env,
        subscriber: Address,
        plan_id: u32,
        duration_seconds: u64,
        price: i128,
        token_contract: Address,
    ) {
        subscriber.require_auth();

        if price < 0 {
            panic!("price cannot be negative");
        }

        let merchant: Address = env.storage().instance().get(&DataKey::MerchantAddress).expect("not initialized");

        // Charge the subscriber
        if price > 0 {
            let client = token::Client::new(&env, &token_contract);
            client.transfer(&subscriber, &merchant, &price);
        }

        let current_time = env.ledger().timestamp();
        let key = DataKey::Subscription(subscriber.clone());
        
        let existing_expiry = if env.storage().persistent().has(&key) {
            let existing: SubscriptionState = env.storage().persistent().get(&key).unwrap();
            if existing.end_time > current_time {
                existing.end_time
            } else {
                current_time
            }
        } else {
            current_time
        };

        let new_expiry = existing_expiry + duration_seconds;

        let state = SubscriptionState {
            end_time: new_expiry,
            plan_id,
            token_contract,
        };

        env.storage().persistent().set(&key, &state);

        // Publish event
        env.events().publish(
            (Symbol::new(&env, "subscribed"), subscriber, plan_id),
            new_expiry,
        );
    }

    /// Check if a subscriber has an active subscription
    pub fn is_active(env: Env, subscriber: Address) -> bool {
        let key = DataKey::Subscription(subscriber);
        if !env.storage().persistent().has(&key) {
            return false;
        }
        let state: SubscriptionState = env.storage().persistent().get(&key).unwrap();
        state.end_time > env.ledger().timestamp()
    }
}
