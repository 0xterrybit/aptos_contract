module mock::usdc {

    use std::signer;
    use std::string;
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    struct USDC {}

    struct FakeMoneyCapabilities has key {
        burn_cap: BurnCapability<USDC>,
        freeze_cap: FreezeCapability<USDC>,
        mint_cap: MintCapability<USDC>,
    }

    fun init_module(sender: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = aptos_framework::coin::initialize<USDC>(
            sender,
            string::utf8(b"Mock USDC"),
            string::utf8(b"USDC"),
            6,
            false,
        );

        move_to(sender, FakeMoneyCapabilities{
            burn_cap,
            freeze_cap,
            mint_cap
        })
    }

    public entry fun mint(sender: &signer, amount: u64) acquires FakeMoneyCapabilities {
        if (!coin::is_account_registered<USDC>(signer::address_of((sender)))) {
            coin::register<USDC>(sender);
        };

        let cap = borrow_global_mut<FakeMoneyCapabilities>(@mock);
        let fake_coin = coin::mint<USDC>(amount, &cap.mint_cap);
        coin::deposit(signer::address_of(sender), fake_coin);
    }
}