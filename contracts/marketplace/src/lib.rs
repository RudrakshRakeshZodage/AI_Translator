#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol};

mod token {
    soroban_sdk::contractimport!(
        file = "../target/wasm32-unknown-unknown/release/translate_credits.wasm"
    );
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct Listing {
    pub creator: Address,
    pub price: i128,
    pub token_contract: Address,
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    PlatformFeeAddress,
    Item(u64),
}

#[contract]
pub struct MarketplaceContract;

#[contractimpl]
impl MarketplaceContract {
    /// Initialize the marketplace admin and fee address
    pub fn initialize(env: Env, admin: Address, platform_fee_address: Address) {
        if env.storage().instance().has(&DataKey::Admin) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::PlatformFeeAddress, &platform_fee_address);
    }

    /// List a new marketplace item (restricted to listing creator)
    pub fn list_item(env: Env, creator: Address, item_id: u64, price: i128, token_contract: Address) {
        creator.require_auth();

        if price < 0 {
            panic!("price cannot be negative");
        }

        let key = DataKey::Item(item_id);
        if env.storage().persistent().has(&key) {
            panic!("item already listed");
        }

        let listing = Listing {
            creator,
            price,
            token_contract,
        };

        env.storage().persistent().set(&key, &listing);

        // Publish event
        env.events().publish((Symbol::new(&env, "item_listed"), item_id), price);
    }

    /// Buy an item. Splits purchase price: 90% to creator, 10% platform fee.
    pub fn purchase_item(env: Env, buyer: Address, item_id: u64) {
        buyer.require_auth();

        let key = DataKey::Item(item_id);
        if !env.storage().persistent().has(&key) {
            panic!("item not listed");
        }

        let listing: Listing = env.storage().persistent().get(&key).unwrap();

        if listing.price > 0 {
            let platform_fee_address: Address = env.storage().instance().get(&DataKey::PlatformFeeAddress).expect("not initialized");
            
            // Calculate 90/10 split
            let creator_amount = listing.price * 90 / 100;
            let platform_amount = listing.price - creator_amount;

            let client = token::Client::new(&env, &listing.token_contract);
            
            // Transfer to Creator
            if creator_amount > 0 {
                client.transfer(&buyer, &listing.creator, &creator_amount);
            }
            
            // Transfer Platform Fee
            if platform_amount > 0 {
                client.transfer(&buyer, &platform_fee_address, &platform_amount);
            }
        }

        // Publish event
        env.events().publish((Symbol::new(&env, "item_purchased"), buyer, item_id), listing.price);
    }
}
