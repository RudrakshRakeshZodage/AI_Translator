#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol, symbol_short};

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    Balance(Address),
}

#[contract]
pub struct TranslateCreditsContract;

#[contractimpl]
impl TranslateCreditsContract {
    /// Initialize the contract and set the admin address
    pub fn initialize(env: Env, admin: Address) {
        if env.storage().instance().has(&DataKey::Admin) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Admin, &admin);
    }

    /// Read the admin address
    pub fn get_admin(env: Env) -> Address {
        env.storage().instance().get(&DataKey::Admin).expect("not initialized")
    }

    /// Query the balance of a specific address
    pub fn balance(env: Env, user: Address) -> i128 {
        env.storage().instance().get(&DataKey::Balance(user)).unwrap_or(0)
    }

    /// Mint new credits (restricted to admin)
    pub fn mint(env: Env, to: Address, amount: i128) {
        if amount <= 0 {
            panic!("amount must be positive");
        }
        let admin: Address = env.storage().instance().get(&DataKey::Admin).expect("not initialized");
        admin.require_auth();

        let balance = Self::balance(env.clone(), to.clone());
        let new_balance = balance + amount;
        env.storage().instance().set(&DataKey::Balance(to.clone()), &new_balance);

        // Publish event
        env.events().publish((Symbol::new(&env, "mint"), to), amount);
    }

    /// Burn credits (used when user spends translation credits)
    pub fn burn(env: Env, from: Address, amount: i128) {
        if amount <= 0 {
            panic!("amount must be positive");
        }
        from.require_auth();

        let balance = Self::balance(env.clone(), from.clone());
        if balance < amount {
            panic!("insufficient balance");
        }
        let new_balance = balance - amount;
        env.storage().instance().set(&DataKey::Balance(from.clone()), &new_balance);

        // Publish event
        env.events().publish((Symbol::new(&env, "burn"), from), amount);
    }

    /// Transfer credits between users (P2P transfer)
    pub fn transfer(env: Env, from: Address, to: Address, amount: i128) {
        if amount <= 0 {
            panic!("amount must be positive");
        }
        from.require_auth();

        if from == to {
            panic!("cannot transfer to self");
        }

        let from_balance = Self::balance(env.clone(), from.clone());
        if from_balance < amount {
            panic!("insufficient balance");
        }

        let to_balance = Self::balance(env.clone(), to.clone());

        env.storage().instance().set(&DataKey::Balance(from.clone()), &(from_balance - amount));
        env.storage().instance().set(&DataKey::Balance(to.clone()), &(to_balance + amount));

        // Publish event
        env.events().publish((Symbol::new(&env, "transfer"), from, to), amount);
    }
}
