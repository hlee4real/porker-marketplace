module admin::marketplace {
    use std::signer;
    use std::string;

    use aptos_token::token;

    use aptos_std::table::{Self, Table};

    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::event;

    const E_ITEM_ALREADY_EXISTS: u64 = 0;
    const E_COLLECTION_ITEM_ALREADY_EXISTS: u64 = 10;
    const E_SELLER_DOESNT_OWN_TOKEN: u64 = 1;
    const E_INVALID_BALANCE: u64 = 2;
    const E_ITEM_NOT_LISTED: u64 = 3;
    const E_AUCTION_ITEM_DOES_NOT_EXIST: u64 = 4;
    const E_LISTING_IS_CLOSED: u64 = 5;
    const E_INSUFFICIENT_BALANCE: u64 = 6;
    const E_RESOURCE_NOT_DESTROYED: u64 = 7;
    const E_SELLER_STILL_OWNS_TOKEN: u64 = 8;
    const E_BUYER_DOESNT_OWN_TOKEN: u64 = 9;

    struct Item<phantom CoinType> has store {
        list_price: u64,
        end_time: u64,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability,
    }

    struct CreateListingEvent has store, drop {
        listing_price: u64,
        end_time: u64,
        start_time: u64,
        seller: address,
        token: token::TokenId,
    }

    struct CancelEvent has store, drop {
        listing_price: u64,
        cancel_time: u64,
        seller: address,
        token: token::TokenId,
    }

    struct BuyEvent has store, drop {
        buy_price: u64,
        buy_time: u64,
        seller: address,
        buyer: address,
        token: token::TokenId,
    }

    struct ListingItem<phantom CoinType> has key {
        items: Table<token::TokenId, Item<CoinType>>
    }

    struct ListingEvents has key {
        create_listing: event::EventHandle<CreateListingEvent>,
        cancel_listing: event::EventHandle<CancelEvent>,
        complete_listing: event::EventHandle<BuyEvent>,
    }

    public entry fun list_nft<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, list_price: u64, expiration_time: u64, property_version:u64) acquires ListingItem, ListingEvents {
        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        assert!(!exists<ListingItem<CoinType>>(sender_addr), E_ITEM_ALREADY_EXISTS);
        assert!(token::balance_of(sender_addr, token_id) > 0, E_SELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = expiration_time + start_time;

        let withdrawCapability = token::create_withdraw_capability(sender, token_id, 1, end_time);
        let item = Item {
            list_price,
            end_time,
            token: token_id,
            withdrawCapability,
        };
        if (exists<ListingItem<CoinType>>(sender_addr)){
            let list_items = borrow_global_mut<ListingItem<CoinType>>(sender_addr);
            table::add(&mut list_items.items, token_id, item);
        }else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<ListingItem<CoinType>>(sender, 
                ListingItem { items: new_item }
            );
        };
        let create_listing_event = CreateListingEvent {
            listing_price: list_price,
            end_time,
            start_time,
            seller: sender_addr,
            token: token_id,
        };
        if (exists<ListingEvents>(sender_addr)){
            let auction_events = borrow_global_mut<ListingEvents>(sender_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        }else {
            move_to<ListingEvents>(sender, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(sender),
                cancel_listing: account::new_event_handle<CancelEvent>(sender),
                complete_listing: account::new_event_handle<BuyEvent>(sender),
            });
            let auction_events = borrow_global_mut<ListingEvents>(sender_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        };
    }

    public entry fun create_collection_token_and_list<CoinType>(
        creator: &signer,
        collection_name: vector<u8>,
        collection_description: vector<u8>,
        collection_uri: vector<u8>,
        collection_maximum: u64,
        collection_mutate_setting: vector<bool>,
        token_name: vector<u8>,
        token_description: vector<u8>,
        token_uri: vector<u8>,
        royalty_payee_address: address,
        royalty_points_denominator: u64,
        royalty_points_numerator: u64,
        token_mutate_setting: vector<bool>,
        property_keys: vector<string::String>,
        property_values: vector<vector<u8>>,
        property_types: vector<string::String>,
        list_price: u64, 
        expiration_time: u64,
    )acquires ListingItem, ListingEvents{
        let creator_addr = signer::address_of(creator);
        token::create_collection_script(
            creator,
            string::utf8(collection_name),
            string::utf8(collection_description),
            string::utf8(collection_uri),
            collection_maximum,
            collection_mutate_setting,
        );
        token::create_token_script(
            creator, 
            string::utf8(collection_name),
            string::utf8(token_name),
            string::utf8(token_description),
            1,
            1,
            string::utf8(token_uri),
            royalty_payee_address,
            royalty_points_denominator,
            royalty_points_numerator,
            token_mutate_setting,
            property_keys,
            property_values,
            property_types,
        );
        let token_id = token::create_token_id_raw(creator_addr, string::utf8(collection_name), string::utf8(token_name), 0);

        assert!(token::balance_of(creator_addr, token_id) > 0, E_SELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = expiration_time + start_time;

        let withdrawCapability = token::create_withdraw_capability(creator, token_id, 1, expiration_time);

        let item = Item {
            list_price,
            end_time,
            token: token_id,
            withdrawCapability,
        };
        if (exists<ListingItem<CoinType>>(creator_addr)){
            let list_items = borrow_global_mut<ListingItem<CoinType>>(creator_addr);
            table::add(&mut list_items.items, token_id, item);
        } else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<ListingItem<CoinType>>(creator, 
                ListingItem { items: new_item }
            );
        };
        let create_listing_event = CreateListingEvent {
            listing_price: list_price,
            end_time,
            start_time,
            seller: creator_addr,
            token: token_id,
        };
        if (exists<ListingEvents>(creator_addr)){
            let auction_events = borrow_global_mut<ListingEvents>(creator_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        } else {
            move_to<ListingEvents>(creator, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(creator),
                cancel_listing: account::new_event_handle<CancelEvent>(creator),
                complete_listing: account::new_event_handle<BuyEvent>(creator),
            });
            let auction_events = borrow_global_mut<ListingEvents>(creator_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        };
    }

    public entry fun buy_token<CoinType>(buyer: &signer, seller: address, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires ListingItem, ListingEvents{
        assert!(exists<ListingItem<CoinType>>(seller), E_AUCTION_ITEM_DOES_NOT_EXIST);

        let buyer_addr = signer::address_of(buyer);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let listing_items = borrow_global_mut<ListingItem<CoinType>>(seller);
        let listing_item = table::borrow_mut(&mut listing_items.items, token_id);

        let current_time = timestamp::now_microseconds();
        assert!(current_time < listing_item.end_time, E_LISTING_IS_CLOSED);

        assert!(token::balance_of(seller, listing_item.token) > 0, E_SELLER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<CoinType>(buyer_addr) > listing_item.list_price, E_INSUFFICIENT_BALANCE);

        token::opt_in_direct_transfer(buyer, true);

        let list = table::remove(&mut listing_items.items, token_id);

        let Item<CoinType> {
            list_price: price,
            end_time: _,
            token: _,
            withdrawCapability: withdrawCapability,
        } = list;

        coin::transfer<CoinType>(buyer, seller, price);

        let token = token::withdraw_with_capability(withdrawCapability);
        token::direct_deposit_with_opt_in(buyer_addr, token);
        let complete_listing_event = BuyEvent {
            buy_price: price,
            buy_time: current_time,
            seller,
            buyer: buyer_addr,
            token: token_id,
        };
        if (exists<ListingEvents>(buyer_addr)) {
            let auction_events = borrow_global_mut<ListingEvents>(buyer_addr);
            event::emit_event<BuyEvent>(
                &mut auction_events.complete_listing,
                complete_listing_event,
            );
        } else {
            move_to<ListingEvents>(buyer, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(buyer),
                cancel_listing: account::new_event_handle<CancelEvent>(buyer),
                complete_listing: account::new_event_handle<BuyEvent>(buyer),
            });
            let auction_events = borrow_global_mut<ListingEvents>(buyer_addr);
            event::emit_event<BuyEvent>(
                &mut auction_events.complete_listing,
                complete_listing_event,
            );
        };
    }

    public fun cancel_listing<CoinType>(seller: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires ListingEvents, ListingItem {
        let seller_addr = signer::address_of(seller);
        assert!(exists<ListingItem<CoinType>>(seller_addr), E_AUCTION_ITEM_DOES_NOT_EXIST);

        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let listing_items = borrow_global_mut<ListingItem<CoinType>>(seller_addr);
        let listing_item = table::borrow_mut(&mut listing_items.items, token_id);

        assert!(token::balance_of(seller_addr, listing_item.token) > 0, E_SELLER_DOESNT_OWN_TOKEN);

        let list = table::remove(&mut listing_items.items, token_id);

        let Item<CoinType> {
            list_price: price,
            end_time: _,
            token: _,
            withdrawCapability: _,
        } = list;

        let cancel_listing_event = CancelEvent {
            listing_price: price,
            cancel_time: timestamp::now_microseconds(),
            seller: seller_addr,
            token: token_id,
        };
        if (exists<ListingEvents>(seller_addr)){
            let auction_events = borrow_global_mut<ListingEvents>(seller_addr);
            event::emit_event<CancelEvent>(
                &mut auction_events.cancel_listing,
                cancel_listing_event,
            );
        } else {
            move_to<ListingEvents>(seller, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(seller),
                cancel_listing: account::new_event_handle<CancelEvent>(seller),
                complete_listing: account::new_event_handle<BuyEvent>(seller),
            });
            let auction_events = borrow_global_mut<ListingEvents>(seller_addr);
            event::emit_event<CancelEvent>(
                &mut auction_events.cancel_listing,
                cancel_listing_event,
            );
        };
    }

}