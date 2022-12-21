module admin::marketplace {
    use aptos_framework::coin;
    use aptos_framework::table::{Self, Table};
    use aptos_framework::guid;
    use aptos_token::token;
    use aptos_token::token_coin_swap::{ list_token_for_swap, exchange_coin_for_token };
    use std::string::String;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::event::{Self, EventHandle};    

    struct MarketId has store, drop, copy{
        market_name: String,
        market_address: address,
    }

    struct Market has key {
        market_id: MarketId,
        signer_cap: account::SignerCapability,
    }

    struct MarketEvents has key {
        create_market_event: EventHandle<CreateMarketEvent>,
        list_token_event: EventHandle<ListTokenEvent>,
        buy_token_event: EventHandle<BuyTokenEvent>,
    }

    struct OfferStore has key {
        offers: Table<token::TokenId, Offer>
    }

    struct Offer has drop, store {
        market_id : MarketId,
        seller: address,
        price: u64,
    }

    struct CreateMarketEvent has drop, store {
        market_id: MarketId,
    }

    struct ListTokenEvent has drop, store {
        market_id: MarketId,
        token_id: token::TokenId,
        seller: address,
        price: u64,
        timestamp: u64,
        offer_id: u64
    }

    struct BuyTokenEvent has drop, store {
        market_id: MarketId,
        token_id: token::TokenId,
        seller: address,
        buyer: address,
        price: u64,
        timestamp: u64,
        offer_id: u64
    }

    //lay ra resource account
    fun get_resource_account_cap(market_address: address) : signer acquires Market {
        let market = borrow_global<Market>(market_address);
        account::create_signer_with_capability(&market.signer_cap)
    }

    //init market va tao resource account, deposit coin vao resource account 
    public entry fun init_market<CoinType>(sender: &signer, market_name: String, initial_fund: u64) acquires MarketEvents, Market {
        let sender_addr = signer::address_of(sender);
        //market id la market name va market address
        //market address la address cua sender luc init market
        let market_id = MarketId { market_name, market_address: sender_addr };

        //neu chua co market event nao duoc tao thi se duoc tao va luu tren storage voi move_to
        if(!exists<MarketEvents>(sender_addr)) {
            move_to(sender, MarketEvents{
                create_market_event: account::new_event_handle<CreateMarketEvent>(sender),
                list_token_event: account::new_event_handle<ListTokenEvent>(sender),
                buy_token_event: account::new_event_handle<BuyTokenEvent>(sender)
            });
        };

        //neu chua tao offer nao thi se tao 1 cai table offer moi
        if(!exists<OfferStore>(sender_addr)) {
            move_to(sender, OfferStore{
                offers: table::new()
            });
        };

        //neu chua co market nao duoc tao thi se duoc tao va luu tren storage voi move_to
        if(!exists<Market>(sender_addr)) { 
            let (resource_signer, signer_cap) = account::create_resource_account(sender, x"01");
            token::initialize_token_store(&resource_signer);
            move_to(sender, Market{
                market_id, signer_cap
            });
            let market_events = borrow_global_mut<MarketEvents>(sender_addr);
            event::emit_event(&mut market_events.create_market_event, CreateMarketEvent{ market_id });
        };

        //lay ra resource account
        let resource_signer = get_resource_account_cap(sender_addr);

        //neu chua dang ky coin thi se dang ky coin
        if(!coin::is_account_registered<CoinType>(signer::address_of(&resource_signer))) {
            coin::register<CoinType>(&resource_signer);
        };

        //neu initial_fund > 0 thi se deposit coin vao resource account
        if(initial_fund > 0) {
            coin::transfer<CoinType>(sender, signer::address_of(&resource_signer), initial_fund);
        };
    }

    public entry fun list_token<CoinType>(seller: &signer, market_address:address, market_name: String, creator: address, collection: String, name: String, property_version: u64, price: u64) acquires MarketEvents, Market, OfferStore {
        let market_id = MarketId { market_name, market_address };
        //lay resource account tu market address ra vi luc init market resource account gan voi market address
        let resource_signer = get_resource_account_cap(market_address);
        let seller_addr = signer::address_of(seller);
        //tao ra token id
        let token_id = token::create_token_id_raw(creator, collection, name, property_version);
        //rut token
        let token = token::withdraw_token(seller, token_id, 1);

        //deposit token vao resource account.
        token::deposit_token(&resource_signer, token);
        //dung aptos_token::list_token_for_swap de list token
        list_token_for_swap<CoinType>(&resource_signer, creator, collection, name, property_version, 1, price, 0);
        //lay ra offer store tu struct OfferStore
        let offer_store = borrow_global_mut<OfferStore>(market_address);
        //them offer store vao table, offer store gom co market_id - market name va address, seller address, price
        table::add(&mut offer_store.offers, token_id, Offer {
            market_id, seller: seller_addr, price
        });

        //tao guid cho resource account
        let guid = account::create_guid(&resource_signer);
        //lay ra market event tu struct MarketEvents
        let market_events = borrow_global_mut<MarketEvents>(market_address);
        //emit event list token
        event::emit_event(&mut market_events.list_token_event, ListTokenEvent{
            market_id, 
            token_id, 
            seller: seller_addr, 
            price, 
            timestamp: timestamp::now_microseconds(),
            offer_id: guid::creation_num(&guid)
        });
    }

    public entry fun buy_token<CoinType>(buyer: &signer, market_address: address, market_name: String, creator: address, collection: String, name: String, property_version: u64, price: u64, offer_id: u64) acquires MarketEvents, Market, OfferStore {
        let market_id = MarketId { market_name, market_address };
        let token_id = token::create_token_id_raw(creator, collection, name, property_version);
        let offer_store = borrow_global_mut<OfferStore>(market_address);
        let seller = table::borrow(&offer_store.offers, token_id).seller;
        let buyer_addr = signer::address_of(buyer);

        let resource_signer = get_resource_account_cap(market_address);
        //dung aptos_token::exchange_coin_for_token de doi coin thanh token (buy token), deposit coin vao resource account
        exchange_coin_for_token<CoinType>(buyer, price, signer::address_of(&resource_signer), creator, collection, name, property_version, 1);

        //chuyen tien cho seller tu resource account
        coin::transfer<CoinType>(&resource_signer, seller, price);
        table::remove(&mut offer_store.offers, token_id);
        
        let market_events = borrow_global_mut<MarketEvents>(market_address);
        event::emit_event(&mut market_events.buy_token_event, BuyTokenEvent{
            market_id,
            token_id,
            seller,
            buyer: buyer_addr,
            price,
            timestamp: timestamp::now_microseconds(),
            offer_id,
        });
    }
}