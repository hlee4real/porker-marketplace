module admin::bobnft {
    use std::signer;
    use std::string::{Self,String};
    use std::bcs;

    use aptos_token::token;
    use aptos_token::token::TokenDataId;

    struct ModuleData has key {
        token_data_id: TokenDataId,
    }

    fun init_module(source_account: &signer) {
        let collection_name = string::utf8(b"Bob");
        let description = string::utf8(b"Bob NFT");
        let collection_uri = string::utf8(b"https://gamefi.org/api/v1/boxes/2");
        let token_name = string::utf8(b"Bob");
        let token_uri = string::utf8(b"https://gamefi.org/api/v1/boxes/2");
        let maximum_supply = 1000000000;
        let mutate_setting = vector<bool>[false, false, false];

        token::create_collection(source_account, collection_name, description, collection_uri, maximum_supply, mutate_setting);
        let token_data_id = token::create_tokendata(
            source_account,
            collection_name,
            token_name,
            string::utf8(b""),
            0,
            token_uri,
            signer::address_of(source_account),
            1,
            0,
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ),

            vector<String>[string::utf8(b"given_to")],
            vector<vector<u8>>[b""],
            vector<String>[ string::utf8(b"address") ],
        );
        move_to(source_account, ModuleData {
            token_data_id,
        });
    }

    public entry fun mint(receiver: &signer) acquires ModuleData {
        let module_data = borrow_global<ModuleData>(@admin);
        token::mint_token(receiver, module_data.token_data_id, 1);

        let (creator_address, collection, name) = token::get_token_data_id_fields(&module_data.token_data_id);
        token::mutate_token_properties(
            receiver,
            signer::address_of(receiver),
            creator_address,
            collection,
            name,
            0,
            1,
            vector<String>[string::utf8(b"given_to")],
            vector<vector<u8>>[bcs::to_bytes(&signer::address_of(receiver))],
            vector<String>[ string::utf8(b"address") ],
        );
    }
}