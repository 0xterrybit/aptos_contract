module perpetual::admin {

    use std::acl;
    use std::vector;
    use std::signer;

    const EACL_BOX_NOT_EXISTS: u64 = 1;
    const ENOT_CONTRACT_OWNER: u64 = 2;
    const ENOT_ACCEPT_ADDRESS: u64 = 3;

    struct ACLBox has key {
        box: acl::ACL
    }

    fun init_module(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @perpetual, ENOT_CONTRACT_OWNER);
        move_to(sender, ACLBox{
            box: acl::empty()
        });
    }

    public entry fun add_acl(sender: &signer, addr_vec: vector<address>) acquires ACLBox {
        let sender_addr = signer::address_of(sender);
        assert!(exists<ACLBox>(sender_addr), EACL_BOX_NOT_EXISTS);
        let acl_box = borrow_global_mut<ACLBox>(sender_addr);
        let len = vector::length(&addr_vec);
        let i = 0;
        while(i < len) {
            let addr = *vector::borrow(&addr_vec, i);
            acl::add(&mut acl_box.box, addr);
            i = i + 1;
        };
    }

    public fun check_permission(addr: address) acquires ACLBox {
        let acl_box = borrow_global<ACLBox>(@perpetual);
        assert!(acl::contains(&acl_box.box, addr), ENOT_ACCEPT_ADDRESS);
    }
}