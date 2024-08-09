module perpetual::lp {


    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    friend perpetual::market;

    struct LP {}

    struct MoneyCapabilities has key {
        burn_cap: BurnCapability<LP>,
        freeze_cap: FreezeCapability<LP>,
        mint_cap: MintCapability<LP>,
    }

    fun init_module(sender: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = aptos_framework::coin::initialize<LP>(
            sender,
            string::utf8(b"Mock LP"),
            string::utf8(b"LP"),
            6,
            true,
        );

        move_to(sender, MoneyCapabilities{
            burn_cap,
            freeze_cap,
            mint_cap
        })
    }

    public(friend) fun mint_to(sender: &signer, amount: u64) acquires MoneyCapabilities {
        if (!coin::is_account_registered<LP>(signer::address_of((sender)))) {
            coin::register<LP>(sender);
        };

        let cap = borrow_global_mut<MoneyCapabilities>(@perpetual);
        let lp_coin = coin::mint<LP>(amount, &cap.mint_cap);
        coin::deposit(signer::address_of(sender), lp_coin);
    }

    public(friend) fun burn(sender: &signer, amount: u64) acquires MoneyCapabilities {
        if (!coin::is_account_registered<LP>(signer::address_of((sender)))) {
            coin::register<LP>(sender);
        };

        let cap = borrow_global_mut<MoneyCapabilities>(@perpetual);
        coin::burn_from<LP>(signer::address_of(sender), amount, &cap.burn_cap);
    }

    public fun get_supply(): u128 {
        let op_supply = coin::supply<LP>();
        option::destroy_some(op_supply)
    }

}