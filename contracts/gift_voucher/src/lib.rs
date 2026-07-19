#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, Address, Env, Symbol, Bytes, BytesN, String};

// Import the token interface to call TranslateCredits
mod token {
    soroban_sdk::contractimport!(
        file = "../target/wasm32-unknown-unknown/release/translate_credits.wasm"
    );
}

#[derive(Clone, Debug, PartialEq)]
#[contracttype]
pub struct VoucherInfo {
    pub creator: Address,
    pub amount: i128,
    pub token_contract: Address,
    pub is_redeemed: bool,
    pub expiry: u64,
}

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Voucher(BytesN<32>),
}

#[contract]
pub struct GiftVoucherContract;

#[contractimpl]
impl GiftVoucherContract {
    /// Create a gift voucher by locking TranslateCredits in this contract
    pub fn create_voucher(
        env: Env,
        creator: Address,
        voucher_hash: BytesN<32>,
        amount: i128,
        token_contract: Address,
        expiry: u64,
    ) {
        creator.require_auth();

        if amount <= 0 {
            panic!("amount must be positive");
        }

        let key = DataKey::Voucher(voucher_hash.clone());
        if env.storage().persistent().has(&key) {
            panic!("voucher already exists");
        }

        if env.ledger().timestamp() >= expiry {
            panic!("expiry must be in the future");
        }

        // Lock the token amount into this contract
        let client = token::Client::new(&env, &token_contract);
        client.transfer(&creator, &env.current_contract_address(), &amount);

        let voucher = VoucherInfo {
            creator,
            amount,
            token_contract,
            is_redeemed: false,
            expiry,
        };

        env.storage().persistent().set(&key, &voucher);

        // Publish event
        env.events().publish((Symbol::new(&env, "voucher_created"), voucher_hash), amount);
    }

    /// Redeem a voucher. The caller provides the raw secret code as Bytes, which is hashed on-chain.
    pub fn redeem_voucher(env: Env, redeemer: Address, voucher_code: Bytes) {
        redeemer.require_auth();

        // Calculate SHA-256 hash of the code
        let hash = env.crypto().sha256(&voucher_code);
        let key = DataKey::Voucher(hash.clone());

        if !env.storage().persistent().has(&key) {
            panic!("voucher not found");
        }

        let mut voucher: VoucherInfo = env.storage().persistent().get(&key).unwrap();

        if voucher.is_redeemed {
            panic!("voucher already redeemed");
        }

        if env.ledger().timestamp() > voucher.expiry {
            panic!("voucher has expired");
        }

        // Mark as redeemed
        voucher.is_redeemed = true;
        env.storage().persistent().set(&key, &voucher);

        // Transfer the locked amount to the redeemer
        let client = token::Client::new(&env, &voucher.token_contract);
        client.transfer(&env.current_contract_address(), &redeemer, &voucher.amount);

        // Publish event
        env.events().publish((Symbol::new(&env, "voucher_redeemed"), hash), voucher.amount);
    }

    /// Refund an expired voucher back to the creator
    pub fn refund_voucher(env: Env, voucher_hash: BytesN<32>) {
        let key = DataKey::Voucher(voucher_hash.clone());

        if !env.storage().persistent().has(&key) {
            panic!("voucher not found");
        }

        let mut voucher: VoucherInfo = env.storage().persistent().get(&key).unwrap();

        if voucher.is_redeemed {
            panic!("voucher already redeemed");
        }

        if env.ledger().timestamp() <= voucher.expiry {
            panic!("voucher is not yet expired");
        }

        // Mark as redeemed/inactive to prevent multiple refunds
        voucher.is_redeemed = true;
        env.storage().persistent().set(&key, &voucher);

        // Return tokens to the creator
        let client = token::Client::new(&env, &voucher.token_contract);
        client.transfer(&env.current_contract_address(), &voucher.creator, &voucher.amount);

        // Publish event
        env.events().publish((Symbol::new(&env, "voucher_refunded"), voucher_hash), voucher.amount);
    }
}
