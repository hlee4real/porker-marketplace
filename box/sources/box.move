module admin::box {
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_token::token;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;

    const E_INVALID_OWNER : u64 = 0;
    const E_NOT_ENOUGH_COIN : u64 = 1;
    const E_AMOUNT_NOT_ENOUGH : u64 = 2;
    const E_HIGH_ARG_GREATER_THAN_LOW_ARG : u64 = 3;

    const BOX_COLLECTION_NAME : vector<u8> = b"Mystery Box Collection of Aptos";
    const BOX_COLLECTION_URI : vector<u8> = b"https://gamefi.org/api/v1/boxes/13";
    const BOX_COLLECTION_DESCRIPTION : vector<u8> = b"This box can be open to have a random token";
    const BOX_TOKEN_NAME : vector<u8> = b"Mystery Box Token of Aptos #";
    const BOX_TOKEN_URI : vector<u8> = b"https://gamefi.org/api/v1/boxes/14";

    const MAIN_COLLECTION_NAME : vector<u8> = b"Wukong Aptos Collection Game";
    const MAIN_COLLECTION_URI : vector<u8> = b"https://gamefi.org/api/v1/boxes/15";
    const MAIN_COLLECTION_DESCRIPTION : vector<u8> = b"Main collection of Wukong Aptos Game";
    const MAIN_TOKEN_NAME : vector<u8> = b"Wukong Aptos Token #";

    struct TokenMintingEvent has drop, store{
        token_data_id: vector<token::TokenDataId>,
        holder: address,
    }

    struct OpenBoxEvent has drop, store{
        receiver: address,
    }

    struct BoxMintingEvent has drop,store {
        receiver: address,
        token_data_id: vector<token::TokenDataId>,
    }

    struct Minter has key{
        cap: SignerCapability,
        box_minted_supply: u64,
        main_minted_supply: u64,
        avaiable_token: vector<u64>,
        box_minting_events: event::EventHandle<BoxMintingEvent>,
        token_minting_events: event::EventHandle<TokenMintingEvent>,
        open_box_events: event::EventHandle<OpenBoxEvent>,
    }

    public entry fun init (sender: &signer) {
        let sender_address = signer::address_of(sender);
        let (signer_cap, capa) = account::create_resource_account(sender, x"01");
        let signer_address = signer::address_of(&signer_cap);
        assert!(sender_address == @admin, E_INVALID_OWNER);
        if (!exists<Minter>(signer_address)){
            move_to(sender, Minter{
                cap: capa,
                box_minted_supply: 0,
                main_minted_supply: 0,
                avaiable_token: vector::empty<u64>(),
                box_minting_events: account::new_event_handle<BoxMintingEvent>(&signer_cap),
                token_minting_events: account::new_event_handle<TokenMintingEvent>(&signer_cap),
                open_box_events: account::new_event_handle<OpenBoxEvent>(&signer_cap),
            });
        }
    }

    //call only once
    public entry fun create_box_collection(creator: &signer) acquires Minter{
        assert!(signer::address_of(creator) == @admin, E_INVALID_OWNER);
        let token_cap = borrow_global_mut<Minter>(@admin);
        let resource_signer = account::create_signer_with_capability(&token_cap.cap);

        token::create_collection(
            &resource_signer,
            string::utf8(BOX_COLLECTION_NAME),
            string::utf8(BOX_COLLECTION_DESCRIPTION),
            string::utf8(BOX_COLLECTION_URI),
            0,
            vector<bool>[ false, false, false ],
        );
    }

    public entry fun mint_box(receiver: &signer, amount: u64) acquires Minter{
        let price : u64 = 10000;
        assert!(amount >= price, E_AMOUNT_NOT_ENOUGH);
        let token_cap = borrow_global_mut<Minter>(@admin);
        let receiver_address = signer::address_of(receiver);
        let resource_signer = account::create_signer_with_capability(&token_cap.cap);
        assert!(coin::balance<AptosCoin>(receiver_address) >= amount, E_NOT_ENOUGH_COIN);

        //make the receiver can receive any token then mint token to them.
        token::initialize_token_store(receiver);
        token::opt_in_direct_transfer(receiver, true);

        let mutate_config = token::create_token_mutability_config(
            &vector<bool>[ false, false, false, false, true ]
        );

        let ids = vector::empty<token::TokenDataId>();
        token_cap.box_minted_supply = token_cap.box_minted_supply + 1;
        let name = string::utf8(BOX_TOKEN_NAME);
        string::append(&mut name, u64_to_string(token_cap.box_minted_supply));
        let token_data_id = token::create_tokendata(
            &resource_signer,
            string::utf8(BOX_COLLECTION_NAME),
            name,
            string::utf8(BOX_COLLECTION_DESCRIPTION),
            1,
            string::utf8(BOX_TOKEN_URI),
            @admin,
            1,
            1,
            mutate_config,
            vector::empty<string::String>(),
            vector::empty<vector<u8>>(),
            vector::empty<string::String>(),
        );

        token::mint_token_to(&resource_signer, signer::address_of(receiver), token_data_id, 1);
        vector::push_back(&mut ids, token_data_id);
        coin::transfer<AptosCoin>(receiver, @admin, amount);

        event::emit_event(&mut token_cap.box_minting_events, BoxMintingEvent{
            receiver: receiver_address,
            token_data_id: ids,
        });
    }

    public entry fun create_main_collection(creator: &signer) acquires Minter {
        assert!(signer::address_of(creator) == @admin, E_INVALID_OWNER);
        let token_cap = borrow_global_mut<Minter>(@admin);
        let resource_signer = account::create_signer_with_capability(&token_cap.cap);

        token::create_collection(
            &resource_signer,
            string::utf8(MAIN_COLLECTION_NAME),
            string::utf8(MAIN_COLLECTION_DESCRIPTION),
            string::utf8(MAIN_COLLECTION_URI),
            0,
            vector<bool>[ false, false, false ],
        );
    }

    public entry fun mint_main_token(receiver: &signer, token_uri: vector<u8>, property_key: vector<u8>, property_value: vector<u8>, property_type:vector<u8>) acquires Minter {
        assert!(signer::address_of(receiver) == @admin, E_INVALID_OWNER);
        let token_cap = borrow_global_mut<Minter>(@admin);
        let receiver_address = signer::address_of(receiver);
        let resource_signer = account::create_signer_with_capability(&token_cap.cap);

        let ids = vector::empty<token::TokenDataId>();
        token_cap.main_minted_supply = token_cap.main_minted_supply + 1;
        let name = string::utf8(MAIN_TOKEN_NAME);
        string::append(&mut name, u64_to_string(token_cap.main_minted_supply));
        let token_data_id = token::create_tokendata(
            &resource_signer,
            string::utf8(MAIN_COLLECTION_NAME),
            name,
            string::utf8(MAIN_COLLECTION_DESCRIPTION),
            1,
            string::utf8(token_uri),
            @admin,
            1,
            1,
            token::create_token_mutability_config(&vector<bool>[ false, false, false, false, true ]),
            vector<String>[string::utf8(property_key)],
            vector<vector<u8>>[property_value],
            vector<String>[string::utf8(property_type)],
        );

        token::mint_token(&resource_signer, token_data_id, 1);

        vector::push_back(&mut ids, token_data_id);

        let avaiable_token = token_cap.avaiable_token;
        vector::push_back(&mut avaiable_token, token_cap.main_minted_supply);

        event::emit_event(&mut token_cap.token_minting_events, TokenMintingEvent{
            holder: receiver_address,
            token_data_id: ids,
        });
    }

    public entry fun open_box(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires Minter {
        let sender_addr = signer::address_of(sender);
        let token_cap = borrow_global_mut<Minter>(@admin);
        let resource_signer = account::create_signer_with_capability(&token_cap.cap);
        let resource_address = signer::address_of(&resource_signer);
        token::burn(sender, creator, string::utf8(collection_name), string::utf8(token_name), property_version, 1);
        //first random then create token_id -> transfer to sender
        let tokens_vector = token_cap.avaiable_token;
        let length = vector::length(&tokens_vector);
        let random_number = rand_u64_in_range(length);
        let token_id_value = vector::borrow_mut(&mut tokens_vector, random_number);
        let token_name = string::utf8(MAIN_TOKEN_NAME);
        string::append(&mut token_name, u64_to_string(*token_id_value));

        let token_id = token::create_token_id_raw(resource_address, string::utf8(MAIN_COLLECTION_NAME), token_name, 0);
        token::transfer(&resource_signer, token_id, sender_addr, 1);

        event::emit_event(&mut token_cap.open_box_events, OpenBoxEvent{
            receiver: sender_addr,
        });

    }

    fun u64_to_string(value: u64): string::String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    fun rand_u64_in_range(high: u64) : u64 {
        assert!(high > 0, E_HIGH_ARG_GREATER_THAN_LOW_ARG);
        let value = timestamp::now_microseconds();
        ( value % (high - 0)) + 0
    }

}