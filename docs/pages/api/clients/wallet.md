## WalletClients
The type of client used by the wallet instance.

## WalletHttpClient
Wallet instance with rpc http/s client.

## WalletWsClient
Wallet instance with rpc ws/s client.

## WalletIpcClient
Wallet instance with rpc ipc client.

## TransactionEnvelopePool

## Node

## FindTransactionEnvelope
Finds a transaction envelope from the pool based on the
transaction type. This is thread safe.\
Returns null if no transaction was found

## AddEnvelopeToPool
Adds a new node into the pool. This is thread safe.

## UnsafeReleaseEnvelopeFromPool
Removes a node from the pool. This is not thread safe.

## ReleaseEnvelopeFromPool
Removes a node from the pool. This is thread safe.

## GetFirstElementFromPool
Gets the last node from the pool and removes it.\
This is thread safe.

## GetLastElementFromPool
Gets the last node from the pool and removes it.\
This is thread safe.

## Deinit
Destroys all created pointer. All future operations will deadlock.\
This is thread safe.

## Wallet
Creates a wallet instance based on which type of client defined in
`WalletClients`. Depending on the type of client the underlaying methods
of `rpc_client` can be changed. The http and websocket client do not
mirror 100% in terms of their methods.\
The client's methods can all be accessed under `rpc_client`.\
The same goes for the signer.

## Init
Init wallet instance. Must call `deinit` to clean up.\
The init opts will depend on the `client_type`.

## Deinit
Clears memory and destroys any created pointers

## AssertTransaction
Asserts that the transactions is ready to be sent.\
Will return errors where the values are not expected

## FindTransactionEnvelopeFromPool
Find a specific prepared envelope from the pool based on the given search criteria.

## GetWalletAddress
Get the wallet address.\
Uses the wallet public key to generate the address.\
This will allocate and the returned address is already checksumed

## PoolTransactionEnvelope
Converts unprepared transaction envelopes and stores them in a pool.\
If you want to store transaction for the future it's best to manange
the wallet nonce manually since otherwise they might get stored with
the same nonce if the wallet was unable to update it.

## PrepareTransaction
Prepares a transaction based on it's type so that it can be sent through the network.\
Only the null struct properties will get changed.\
Everything that gets set before will not be touched.

## SearchPoolAndSendTransaction
Search the internal `TransactionEnvelopePool` to find the specified transaction based on the `type` and nonce.\
If there are duplicate transaction that meet the search criteria it will send the first it can find.\
The search is linear and starts from the first node of the pool.

## SendBlobTransaction
Sends blob transaction to the network
Trusted setup must be loaded otherwise this will fail.

## SendSidecarTransaction
Sends blob transaction to the network
This uses and already prepared sidecar.

## SendSignedTransaction
Signs, serializes and send the transaction via `eth_sendRawTransaction`.\
Returns the transaction hash.

## SendTransaction
Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.\
If any envelope is in the envelope pool it will use that instead in a LIFO order
Will return an error if the envelope is incorrect

## SignEthereumMessage
Signs an ethereum message with the specified prefix.\
The Signatures recoverId doesn't include the chain_id

## SignTypedData
Signs a EIP712 message according to the expecification
https://eips.ethereum.org/EIPS/eip-712
`types` parameter is expected to be a struct where the struct
keys are used to grab the solidity type information so that the
encoding and hashing can happen based on it. See the specification
for more details.\
`primary_type` is the expected main type that you want to hash this message.\
Compilation will fail if the provided string doesn't exist on the `types` parameter
`domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
domain types.\
`message` is expected to be a struct where the solidity types are transalated to the native
zig types. I.E string -> []const u8 or int256 -> i256 and so on.\
In the future work will be done where the compiler will offer more clearer types
base on a meta programming type function.\
Returns the signature type.

## VerifyMessage
Verifies if a given signature was signed by the current wallet.

## VerifyTypedData
Verifies a EIP712 message according to the expecification
https://eips.ethereum.org/EIPS/eip-712
`types` parameter is expected to be a struct where the struct
keys are used to grab the solidity type information so that the
encoding and hashing can happen based on it. See the specification
for more details.\
`primary_type` is the expected main type that you want to hash this message.\
Compilation will fail if the provided string doesn't exist on the `types` parameter
`domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
domain types.\
`message` is expected to be a struct where the solidity types are transalated to the native
zig types. I.E string -> []const u8 or int256 -> i256 and so on.\
In the future work will be done where the compiler will offer more clearer types
base on a meta programming type function.\
Returns the signature type.

## WaitForTransactionReceipt
Waits until the transaction gets mined and we can grab the receipt.\
It fails if the retry counter is excedded.\
The behaviour of this method varies based on the client type.\
If it's called with the websocket client or the ipc client it will create a subscription for new block and wait
until the transaction gets mined. Otherwise it will use the rpc_client `pooling_interval` property.

