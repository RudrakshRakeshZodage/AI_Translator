#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol};

mod token {
    soroban_sdk::contractimport!(
        file = "../target/wasm32-unknown-unknown/release/translate_credits.wasm"
    );
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    Referrer(Address),
    RewardPool, // Address holding tokens for reward payouts
}

#[contract]
pub struct ReferralsContract;

#[contractimpl]
impl ReferralsContract {
    /// Initialize with Admin and Reward Pool address
    pub fn initialize(env: Env, admin: Address, reward_pool: Address) {
        if env.storage().instance().has(&DataKey::Admin) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::RewardPool, &reward_pool);
    }

    /// Set a referrer for the caller
    pub fn set_referrer(env: Env, user: Address, referrer: Address) {
        user.require_auth();

        if user == referrer {
            panic!("cannot refer yourself");
        }

        let key = DataKey::Referrer(user.clone());
        if env.storage().persistent().has(&key) {
            panic!("referrer already set");
        }

        env.storage().persistent().set(&key, &referrer);

        // Publish event
        env.events().publish((Symbol::new(&env, "referrer_set"), user, referrer), 0);
    }

    /// Query the referrer of a user
    pub fn get_referrer(env: Env, user: Address) -> Option<Address> {
        let key = DataKey::Referrer(user);
        env.storage().persistent().get(&key)
    }

    /// Trigger rewards on purchase of credits. Admin (e.g. FastAPI Backend) calls this.
    /// Distributes 5% bonus to referrer and 5% bonus to referee.
    pub fn reward_purchase(env: Env, buyer: Address, purchase_amount: i128, token_contract: Address) {
        let admin: Address = env.storage().instance().get(&DataKey::Admin).expect("not initialized");
        admin.require_auth();

        let referrer_opt = Self::get_referrer(env.clone(), buyer.clone());
        if let Some(referrer) = referrer_opt {
            let reward_pool: Address = env.storage().instance().get(&DataKey::RewardPool).expect("not initialized");
            
            // Calculate 5% reward
            let reward_amount = purchase_amount * 5 / 100;
            if reward_amount > 0 {
                let client = token::Client::new(&env, &token_contract);
                
                // Reward referrer
                client.transfer(&reward_pool, &referrer, &reward_amount);
                
                // Reward buyer (referee)
                client.transfer(&reward_pool, &buyer, &reward_amount);

                // Publish event
                env.events().publish(
                    (Symbol::new(&env, "referral_rewarded"), buyer, referrer),
                    reward_amount,
                );
            }
        }
    }
}
