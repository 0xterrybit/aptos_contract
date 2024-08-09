module mock::usdt {

    use std::signer;
    use std::string;
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    struct USDT {}

    struct FakeMoneyCapabilities has key {
        burn_cap: BurnCapability<USDT>,
        freeze_cap: FreezeCapability<USDT>,
        mint_cap: MintCapability<USDT>,
    }

    fun init_module(sender: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = aptos_framework::coin::initialize<USDT>(
            sender,
            string::utf8(b"Mock USDT"),
            string::utf8(b"USDT"),
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
        if (!coin::is_account_registered<USDT>(signer::address_of((sender)))) {
            coin::register<USDT>(sender);
        };

        let cap = borrow_global_mut<FakeMoneyCapabilities>(@mock);
        let fake_coin = coin::mint<USDT>(amount, &cap.mint_cap);
        coin::deposit(signer::address_of(sender), fake_coin);
    }
}