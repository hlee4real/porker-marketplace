module admin::marketplace {
    use aptos_framework::coin::{Self};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::guid;

    use std::signer;
    use std::option::{Self, Option};
    use std::string::String;
    use aptos_std::event::{Self, EventHandle};
    use aptos_std::table::{Self, Table};

    use aptos_token::token::{Self, Token, TokenId};

    // ---------------------------------------------
    // ERRORs

    const ERROR: u64 = 0;
    const ERROR_INVALID_BUYER: u64 = 1;
    const ERROR_INVALID_OWNER:u64 = 2;
    const ERROR_NOT_ENOUGH_LENGTH:u64 = 3;

    //TokenCap is a struct that holds a SignerCapability for a token
    struct TokenCap has key {
        cap: SignerCapability,
    }

    //MarketData is a struct that holds the fee and the fund address for a market
    struct MarketData has key {
        fee: u64,
        fund_address: address
    }

    // Set of data sent to the event stream during a listing of a token (for fixed price)
    struct ListEvent has drop, store {
        id: TokenId,
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    // Set of data sent to the event stream during a delisting of a token 
    struct DelistEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        amount: u64,
        seller_address: address,
    }

    // Set of data sent to the event stream during a buying of a token (for fixed price)
    struct BuyEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        buyer_address: address
    }

    //Listed Item is a struct that holds the data for a listed item
    struct ListedItem has store {
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        locked_token: Option<Token>,
        seller_address: address
    }

    struct ChangePriceEvent has drop, store {
        id: TokenId,
        amount: u64,
        listing_id: u64,
        timestamp: u64,
        seller_address: address,
    }

    struct ListedItemsData has key {
        listed_items: Table<TokenId, ListedItem>,
        listing_events: EventHandle<ListEvent>,
        buying_events: EventHandle<BuyEvent>,
        delisting_events: EventHandle<DelistEvent>,
        changing_price_events: EventHandle<ChangePriceEvent>
    }


    // public contract && initial resource account
    public entry fun initial_market(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        //create resource account for market
        let (market_signer, market_cap) = account::create_resource_account(sender, x"01");
        let market_signer_address = signer::address_of(&market_signer);

        assert!(sender_addr == @admin, ERROR_INVALID_OWNER);

        //if the market does not exist, create it and move the TokenCap to it (create storage for the token cap)
        if(!exists<TokenCap>(@admin)){
            move_to(sender, TokenCap {
                cap: market_cap
            })
        };

        //if the market does not exist, create it and move the MarketData to it (create storage for the market data)
        if (!exists<MarketData>(market_signer_address)){
            move_to(&market_signer, MarketData {
                fee: 200,
                fund_address: sender_addr
            })
        };

        //if the market does not exist, create it and move the ListedItemsData to it (create storage for the listed items data)
        //move_to để tạo storage -> lưu trữ những thứ cần dùng, VD: listed_items này là table chứa các token đã được list (token đc rút ra từ sender và lưu vào table này, sau đó token sẽ đc lock lại)
        if (!exists<ListedItemsData>(market_signer_address)) {
            move_to(&market_signer, ListedItemsData {
                listed_items:table::new<TokenId, ListedItem>(),
                listing_events: account::new_event_handle<ListEvent>(&market_signer),
                buying_events: account::new_event_handle<BuyEvent>(&market_signer),
                delisting_events: account::new_event_handle<DelistEvent>(&market_signer),
                changing_price_events: account::new_event_handle<ChangePriceEvent>(&market_signer)
            });
        };

    }

    //internal function for list token
    fun list_token(
        sender: &signer,
        token_id: TokenId,
        price: u64,
    ) acquires ListedItemsData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@admin).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        //withdraw token from sender and get listed items
        let token = token::withdraw_token(sender, token_id, 1);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        //royalties for the token
        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        // get unique id
        let guid = account::create_guid(market_signer);
        let listing_id = guid::creation_num(&guid);

        //emit list event
        event::emit_event<ListEvent>(
            &mut listed_items_data.listing_events,
            ListEvent { 
                id: token_id,
                amount: price,
                seller_address: sender_addr,
                timestamp: timestamp::now_seconds(),
                listing_id,
                royalty_payee,
                royalty_numerator,
                royalty_denominator 
            },
        );

        //use option to lock token then add it to table. resource account is not used to hold token in this contract
        //instead of it, the token is locked in the table
        table::add(listed_items, token_id, ListedItem {
            amount: price,
            listing_id,
            timestamp: timestamp::now_seconds(),
            locked_token: option::some(token),
            seller_address: sender_addr
        })
    }

    public entry fun list_token_script(sender: &signer, creator: address, collection_name: String, token_name: String, property_version: u64, price: u64) acquires ListedItemsData, TokenCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        list_token(sender, token_id, price);
    }

    // delist token
    fun delist_token(
        sender: &signer,
        token_id: TokenId
    ) acquires ListedItemsData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@admin).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        //get listed items
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);

        event::emit_event<DelistEvent>(
            &mut listed_items_data.delisting_events,
            DelistEvent { 
                id: token_id, 
                amount: listed_item.amount,
                listing_id: listed_item.listing_id,
                timestamp: timestamp::now_seconds(),
                seller_address: sender_addr 
            },
        );

        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        //remove token from table and destroy it from the option which is locked before
        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _} = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }

    public entry fun delist_token_script(sender: &signer, creator: address, collection_name: String, token_name: String, property_version: u64) acquires ListedItemsData, TokenCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        delist_token(sender, token_id);
    }
    
    // internal buy token function 
    fun buy_token<CoinType>(
        sender: &signer, 
        token_id: TokenId,
    ) acquires ListedItemsData, TokenCap, MarketData {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<TokenCap>(@admin).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);

        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);
        let seller = listed_item.seller_address;

        assert!(sender_addr != seller, ERROR_INVALID_BUYER);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        let _fee_royalty: u64 = 0;

        if (royalty_denominator == 0){
            _fee_royalty = 0;
        } else {
            _fee_royalty = royalty_numerator * listed_item.amount / royalty_denominator;
        };

        let fee_listing = listed_item.amount * market_data.fee / 10000;
        let sub_amount = listed_item.amount - fee_listing - _fee_royalty;

        if (_fee_royalty > 0) {
            coin::transfer<CoinType>(sender, royalty_payee, _fee_royalty);
        };

        if (fee_listing > 0) {
            coin::transfer<CoinType>(sender, market_data.fund_address, fee_listing);
        };

        // transfer coin to buyer
        coin::transfer<CoinType>(sender, seller, sub_amount);

        //get token from locked token
        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        //emit buy event
        event::emit_event<BuyEvent>(
            &mut listed_items_data.buying_events,
            BuyEvent { 
                id: token_id, 
                listing_id: listed_item.listing_id,
                seller_address: listed_item.seller_address,
                timestamp: timestamp::now_seconds(),
                buyer_address: sender_addr 
            },
        );

        //destroy none -> destroy locked token from listed item
        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _} = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }


    public entry fun buy_token_script<CoinType>(sender: &signer, creator: address, collection_name: String, token_name: String, property_version: u64) acquires ListedItemsData, TokenCap, MarketData{
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        buy_token<CoinType>(sender, token_id);
    }

}