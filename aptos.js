const { AptosClient, AptosAccount, CoinClient, TokenClient } = require("aptos")
const NODE_URL = process.env.APTOS_NODE_URL || "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = process.env.APTOS_FAUCET_URL || "https://faucet.devnet.aptoslabs.com";
const client = new AptosClient(NODE_URL);
const coinClient = new CoinClient(client);
const tokenClient = new TokenClient(client);

let myWallet = AptosAccount.fromAptosAccountObject({
    address: address,
    publicKeyHex: publicKey,
    privateKeyHex: privateKey,
})

let wallet2 = AptosAccount.fromAptosAccountObject({
    address: address2,
    publicKeyHex: publicKey2,
    privateKeyHex: privateKey2,
})

const hoangCollection = {
    name: "Long's s s s  sx  Collection",
    description: "Collection of Long's NFT",
    uri: "https://gamefi.org/api/v1/boxes/9"
}
const hoangToken = {
    name: "Long's ssss Token",
    description: "Long's NFT",
    uri: "https://gamefi.org/api/v1/boxes/10",
    supply: 1,
}

const main = async () => {
    console.log(`My wallet ${address} has ${await coinClient.checkBalance(myWallet)} APT coins`)
    await make_collection()
    await make_token()
    await list_nft()
    await buy_token()
}
const make_collection = async () => {
    try {
        const tx = await tokenClient.createCollection(
            wallet2,
            hoangCollection.name,
            hoangCollection.description,
            hoangCollection.uri,
        )
        await client.waitForTransaction(tx, { checkSuccess: true })
    } catch (error) {
        console.log(error)
    }
}

const make_token = async () => {
    try {
        const tokens = await tokenClient.createToken(
            wallet2,
            hoangCollection.name,
            hoangToken.name,
            hoangToken.description,
            hoangToken.supply,
            hoangToken.uri,
        )
        await client.waitForTransaction(tokens, { checkSuccess: true })
    } catch (error) {
        console.log(error);
    }
}

const list_nft = async () => {
    try {
        const data = [
            wallet2.address(),
            hoangCollection.name,
            hoangToken.name,
            100,
            8000000,
            0,
        ];
        const create_tx = {
            type: 'entry_function_payload',
            function: '0x13875ee636300ec7031d1eefc82591b23263ea3665f870fb31abfd4fd713c779::marketplace::list_nft',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: data,
        }
        signAndSubmit(create_tx)
    } catch (error) {
        console.log(error);
    }
}

const buy_token = async () => {
    try {
        const buy_token_data = [
            wallet2.address(),
            myWallet.address(),
            hoangCollection.name,
            hoangToken.name,
            0,
        ]
        const payload = {
            type: 'entry_function_payload',
            function: '0x13875ee636300ec7031d1eefc82591b23263ea3665f870fb31abfd4fd713c779::marketplace::buy_token',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: buy_token_data,
        }
        signAndSubmit(payload)
    } catch (error) {
        console.log(error);
    }
}

const signAndSubmit = async (transaction) => {
    try {
        const txRequest = await client.generateTransaction(myWallet.address(), transaction);
        const signedTx = await client.signTransaction(myWallet, txRequest);
        const txResponse = await client.submitTransaction(signedTx);
        const result = await client.waitForTransaction(txResponse.hash);
        console.log("hash: ", txResponse.hash);
    }
    catch (e) {
        console.log('error sign and submit', e);
    }
}
main()