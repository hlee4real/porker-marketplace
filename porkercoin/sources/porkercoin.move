module admin::porkercoin {
    use aptos_framework::coin;
    use std::signer;
    use std::string;

    struct PORKER {}

    struct CoinCapabilities<phantom PORKER> has key {
        mint_capability: coin::MintCapability<PORKER>,
        burn_capability: coin::BurnCapability<PORKER>,
        freeze_capability: coin::FreezeCapability<PORKER>,
    }

    const E_NO_ADMIN: u64 = 0;
    const E_NO_CAPABILITIES: u64 = 1;
    const E_HAS_CAPABILITIES: u64 = 2;

    public entry fun init_coin(account: &signer) {
        let (burn_capability, freeze_capability, mint_capability) = coin::initialize<PORKER>(
            account,
            string::utf8(b"Porker Token"),
            string::utf8(b"PORKER"),
            18,
            true,
        );

        assert!(signer::address_of(account) == @admin, E_NO_ADMIN);
        assert!(!exists<CoinCapabilities<PORKER>>(@admin), E_HAS_CAPABILITIES);

        move_to<CoinCapabilities<PORKER>>(account, CoinCapabilities<PORKER>{mint_capability, burn_capability, freeze_capability});
    }

    public entry fun mint_coin<PORKER>(account: &signer, user: address, amount: u64) acquires CoinCapabilities {
        let account_address = signer::address_of(account);
        assert!(account_address == @admin, E_NO_ADMIN);
        assert!(exists<CoinCapabilities<PORKER>>(account_address), E_NO_CAPABILITIES);
        let mint_capability = &borrow_global<CoinCapabilities<PORKER>>(account_address).mint_capability;
        let coins = coin::mint<PORKER>(amount, mint_capability);
        coin::deposit(user, coins)
    }
}