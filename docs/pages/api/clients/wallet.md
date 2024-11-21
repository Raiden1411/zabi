## WalletClients

The type of client used by the wallet instance.

### Properties

```zig
enum {
  http
  websocket
  ipc
}
```

## WalletHttpClient

Wallet instance with rpc http/s client.

```zig
Wallet(.http)
```

## WalletWsClient

Wallet instance with rpc ws/s client.

```zig
Wallet(.websocket)
```

## WalletIpcClient

Wallet instance with rpc ipc client.

```zig
Wallet(.ipc)
```

## TransactionEnvelopePool

### Properties

```zig
struct {
  mutex: Mutex = .{}
  pooled_envelopes: TransactionEnvelopeQueue
}
```

## Node

```zig
TransactionEnvelopeQueue.Node
```

### FindTransactionEnvelope
Finds a transaction envelope from the pool based on the
transaction type and it's nonce in case there are transactions with the same type. This is thread safe.

Returns null if no transaction was found

### Signature

```zig
pub fn findTransactionEnvelope(pool: *TransactionEnvelopePool, allocator: Allocator, search: SearchCriteria) ?TransactionEnvelope
```

### AddEnvelopeToPool
Adds a new node into the pool. This is thread safe.

### Signature

```zig
pub fn addEnvelopeToPool(pool: *TransactionEnvelopePool, node: *Node) void
```

### UnsafeReleaseEnvelopeFromPool
Removes a node from the pool. This is not thread safe.

### Signature

```zig
pub fn unsafeReleaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void
```

### ReleaseEnvelopeFromPool
Removes a node from the pool. This is thread safe.

### Signature

```zig
pub fn releaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void
```

### GetFirstElementFromPool
Gets the last node from the pool and removes it.
This is thread safe.

### Signature

```zig
pub fn getFirstElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope
```

### GetLastElementFromPool
Gets the last node from the pool and removes it.
This is thread safe.

### Signature

```zig
pub fn getLastElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope
```

### Deinit
Destroys all created pointer. All future operations will deadlock.
This is thread safe.

### Signature

```zig
pub fn deinit(pool: *TransactionEnvelopePool, allocator: Allocator) void
```

## Node

```zig
TransactionEnvelopeQueue.Node
```

## Wallet
Creates a wallet instance based on which type of client defined in
`WalletClients`. Depending on the type of client the underlaying methods
of `rpc_client` can be changed. The http and websocket client do not
mirror 100% in terms of their methods.

The client's methods can all be accessed under `rpc_client`.
The same goes for the signer.

### Signature

```zig
pub fn Wallet(comptime client_type: WalletClients) type
```

## InitErrors

Set of possible errors when starting the wallet.

```zig
ClientType.InitErrors || error{IdentityElement}
```

## Error

Set of common errors produced by wallet actions.

```zig
ClientType.BasicRequestErrors
```

## PrepareError

Set of errors when preparing a transaction

```zig
Error || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock, MaxFeePerGasUnderflow, UnsupportedTransactionType }
```

## AssertionErrors

Set of errors that can be returned on the `assertTransaction` method.

```zig
error{
            InvalidChainId,
            TransactionTipToHigh,
            EmptyBlobs,
            TooManyBlobs,
            BlobVersionNotSupported,
            CreateBlobTransaction,
        }
```

## Eip3074Envelope

Eip3074 auth message envelope.

### Properties

```zig
struct {
  magic: u8
  chain_id: u256
  nonce: u256
  address: u256
  commitment: Hash
}
```

## SendSignedTransactionErrors

Set of possible errors when sending signed transactions

```zig
Error || Signer.SigningErrors || SerializeErrors
```

## NonceManager

Nonce manager that use's the rpc client as the source of truth
for checking internally that the cached and managed values can be used.

### Properties

```zig
struct {
  /// The address that will get it's nonce managed.
  address: Address
  /// The current nonce in use.
  managed: u64
  /// The cached nonce.
  cache: u64
}
```

### InitManager
Sets the initial state of the `NonceManager`.

### Signature

```zig
pub fn initManager(address: Address) NonceManager
```

### GetNonce
Gets the nonce from either the cache or from the network.

Resets the `manager` nonce value and the `cache` if the nonce value from the network
is higher than one from the `cache`.

### Signature

```zig
pub fn getNonce(self: *Self, rpc_client: *ClientType) ClientType.BasicRequestErrors!u64
```

### IncrementNonce
Increments the `manager` by one.

### Signature

```zig
pub fn incrementNonce(self: *Self) void
```

### UpdateNonce
Gets the nonce from either the cache or from the network and updates internally.

Resets the `manager` nonce value and the `cache` if the nonce value from the network
is higher than one from the `cache`.

### Signature

```zig
pub fn updateNonce(self: *Self, rpc_client: *ClientType) ClientType.BasicRequestErrors!u64
```

### ResetNonce
Resets the `manager` to 0.

### Signature

```zig
pub fn resetNonce(self: *Self) void
```

## Init
Sets the wallet initial state.

The init opts will depend on the [client_type](/api/clients/wallet#walletclients).\
Also add the hability to use a nonce manager or to use the network directly.

**Example**
```zig
const uri = try std.Uri.parse("http://localhost:6969/");

var buffer: Hash = undefined;
_ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

var wallet = try Wallet(.http).init(buffer, .{
    .allocator = testing.allocator,
    .network_config = .{
        .endpoint = .{ .uri = uri },
    },
}, true // Setting to true initializes the NonceManager);
defer wallet.deinit();
```

### Signature

```zig
pub fn init(
    private_key: ?Hash,
    opts: ClientInitOptions,
    nonce_manager: bool,
) (error{IdentityElement} || ClientType.InitErrors)!*WalletSelf
```

## AssertTransaction
Asserts that the transactions is ready to be sent.
Will return errors where the values are not expected

### Signature

```zig
pub fn assertTransaction(
    self: *WalletSelf,
    tx: TransactionEnvelope,
) AssertionErrors!void
```

## AuthMessageEip3074
Converts to a message that the contracts executing `AUTH` opcodes can understand.\
For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-3074#specification).

You can pass null to `nonce` if you want to target a specific nonce.\
Otherwise if with either use the `nonce_manager` if it can or fetch from the network.\
Memory must be freed after calling this method.

This is still experimental since the EIP has not being deployed into any mainnet.

### Signature

```zig
pub fn authMessageEip3074(
    self: *WalletSelf,
    invoker_address: Address,
    nonce: ?u64,
    commitment: Hash,
) ClientType.BasicRequestErrors![]u8
```

## FindTransactionEnvelopeFromPool
Find a specific prepared envelope from the pool based on the given search criteria.

### Signature

```zig
pub fn findTransactionEnvelopeFromPool(self: *WalletSelf, search: TransactionEnvelopePool.SearchCriteria) ?TransactionEnvelope
```

## HashAuthorityEip7702
Generates the authorization hash based on the eip7702 specification.
For more information please go [here](https://eips.ethereum.org/EIPS/eip-7702)

This is still experimental since the EIP has not being deployed into any mainnet.

### Signature

```zig
pub fn hashAuthorityEip7702(
    self: *WalletSelf,
    authority: Address,
    nonce: u64,
) RlpEncodeErrors!Hash
```

## GetWalletAddress
Get the wallet address.

Uses the wallet public key to generate the address.

### Signature

```zig
pub fn getWalletAddress(self: *WalletSelf) Address
```

## PoolTransactionEnvelope
Converts unprepared transaction envelopes and stores them in a pool.

This appends to the last node of the list.

### Signature

```zig
pub fn poolTransactionEnvelope(
    self: *WalletSelf,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) PrepareError!void
```

## PrepareTransaction
Prepares a transaction based on it's type so that it can be sent through the network.\

Only the null struct properties will get changed.\
Everything that gets set before will not be touched.

### Signature

```zig
pub fn prepareTransaction(
    self: *WalletSelf,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) PrepareError!TransactionEnvelope
```

## RecoverAuthMessageAddress
Recovers the address associated with the signature based on the message.\
To reconstruct the message use `authMessageEip3074`

Reconstructs the message from them and returns the address bytes.

### Signature

```zig
pub fn recoverAuthMessageAddress(
    auth_message: []u8,
    sig: Signature,
) Signer.RecoverPubKeyErrors!Address
```

## RecoverAuthorizationAddress
Recovers the address associated with the signature based on the authorization payload.

### Signature

```zig
pub fn recoverAuthorizationAddress(
    self: *WalletSelf,
    authorization_payload: AuthorizationPayload,
) (RlpEncodeErrors || Signer.RecoverPubKeyErrors)!Address
```

## SearchPoolAndSendTransaction
Search the internal `TransactionEnvelopePool` to find the specified transaction based on the `type` and nonce.

If there are duplicate transaction that meet the search criteria it will send the first it can find.\
The search is linear and starts from the first node of the pool.

### Signature

```zig
pub fn searchPoolAndSendTransaction(
    self: *WalletSelf,
    search_opts: TransactionEnvelopePool.SearchCriteria,
) (SendSignedTransactionErrors || AssertionErrors || error{TransactionNotFoundInPool})!RPCResponse(Hash)
```

## SendBlobTransaction
Sends blob transaction to the network.
Trusted setup must be loaded otherwise this will fail.

### Signature

```zig
pub fn sendBlobTransaction(
    self: *WalletSelf,
    blobs: []const Blob,
    unprepared_envelope: UnpreparedTransactionEnvelope,
    trusted_setup: *KZG4844,
) !RPCResponse(Hash)
```

## SendSidecarTransaction
Sends blob transaction to the network.
This uses and already prepared sidecar.

### Signature

```zig
pub fn sendSidecarTransaction(
    self: *WalletSelf,
    sidecars: []const Sidecar,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash)
```

## SendSignedTransaction
Signs, serializes and send the transaction via `eth_sendRawTransaction`.

Returns the transaction hash.

### Signature

```zig
pub fn sendSignedTransaction(
    self: *WalletSelf,
    tx: TransactionEnvelope,
) SendSignedTransactionErrors!RPCResponse(Hash)
```

## SendTransaction
Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.

If any envelope is in the envelope pool it will use that instead in a LIFO order.\
Will return an error if the envelope is incorrect

### Signature

```zig
pub fn sendTransaction(
    self: *WalletSelf,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) (SendSignedTransactionErrors || AssertionErrors || PrepareError)!RPCResponse(Hash)
```

## SignAuthMessageEip3074
Signs and prepares an eip3074 authorization message.
For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-3074#specification).

You can pass null to `nonce` if you want to target a specific nonce.\
Otherwise if with either use the `nonce_manager` if it can or fetch from the network.

This is still experimental since the EIP has not being deployed into any mainnet.

### Signature

```zig
pub fn signAuthMessageEip3074(
    self: *WalletSelf,
    invoker_address: Address,
    nonce: ?u64,
    commitment: Hash,
) (ClientType.BasicRequestErrors || Signer.SigningErrors)!Signature
```

## SignAuthorizationEip7702
Signs and prepares an eip7702 authorization message.
For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-7702#specification).

You can pass null to `nonce` if you want to target a specific nonce.\
Otherwise if with either use the `nonce_manager` if it can or fetch from the network.

This is still experimental since the EIP has not being deployed into any mainnet.

### Signature

```zig
pub fn signAuthorizationEip7702(
    self: *WalletSelf,
    authority: Address,
    nonce: ?u64,
) (ClientType.BasicRequestErrors || Signer.SigningErrors || RlpEncodeErrors)!AuthorizationPayload
```

## SignEthereumMessage
Signs an ethereum message with the specified prefix.

The Signatures recoverId doesn't include the chain_id.

### Signature

```zig
pub fn signEthereumMessage(
    self: *WalletSelf,
    message: []const u8,
) (Signer.SigningErrors || Allocator.Error)!Signature
```

## SignTypedData
Signs a EIP712 message according to the expecification
https://eips.ethereum.org/EIPS/eip-712

`types` parameter is expected to be a struct where the struct
keys are used to grab the solidity type information so that the
encoding and hashing can happen based on it. See the specification
for more details.

`primary_type` is the expected main type that you want to hash this message.
Compilation will fail if the provided string doesn't exist on the `types` parameter

`domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
domain types.

`message` is expected to be a struct where the solidity types are transalated to the native
zig types. I.E string -> []const u8 or int256 -> i256 and so on.
In the future work will be done where the compiler will offer more clearer types
base on a meta programming type function.

Returns the signature type.

### Signature

```zig
pub fn signTypedData(
    self: *WalletSelf,
    comptime eip_types: anytype,
    comptime primary_type: []const u8,
    domain: ?TypedDataDomain,
    message: anytype,
) (Signer.SigningErrors || EIP712Errors)!Signature
```

## VerifyAuthMessage
Verifies if the auth message was signed by the provided address.\
To reconstruct the message use `authMessageEip3074`.

You can pass null to `expected_address` if you want to use this wallet instance
associated address.

### Signature

```zig
pub fn verifyAuthMessage(
    self: *WalletSelf,
    expected_address: ?Address,
    auth_message: []u8,
    sig: Signature,
) (ClientType.BasicRequestErrors || Signer.RecoverPubKeyErrors)!bool
```

## VerifyAuthorization
Verifies if the authorization message was signed by the provided address.\

You can pass null to `expected_address` if you want to use this wallet instance
associated address.

### Signature

```zig
pub fn verifyAuthorization(
    self: *WalletSelf,
    expected_address: ?Address,
    authorization_payload: AuthorizationPayload,
) (ClientType.BasicRequestErrors || Signer.RecoverPubKeyErrors || RlpEncodeErrors)!bool
```

## VerifyMessage
Verifies if a given signature was signed by the current wallet.

### Signature

```zig
pub fn verifyMessage(self: *WalletSelf, sig: Signature, message: []const u8) bool
```

## VerifyTypedData
Verifies a EIP712 message according to the expecification
https://eips.ethereum.org/EIPS/eip-712

`types` parameter is expected to be a struct where the struct
keys are used to grab the solidity type information so that the
encoding and hashing can happen based on it. See the specification
for more details.

`primary_type` is the expected main type that you want to hash this message.
Compilation will fail if the provided string doesn't exist on the `types` parameter

`domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
domain types.

`message` is expected to be a struct where the solidity types are transalated to the native
zig types. I.E string -> []const u8 or int256 -> i256 and so on.
In the future work will be done where the compiler will offer more clearer types
base on a meta programming type function.

Returns the signature type.

### Signature

```zig
pub fn verifyTypedData(
    self: *WalletSelf,
    sig: Signature,
    comptime eip712_types: anytype,
    comptime primary_type: []const u8,
    domain: ?TypedDataDomain,
    message: anytype,
) (EIP712Errors || Signer.RecoverPubKeyErrors)!bool
```

## WaitForTransactionReceipt
Waits until the transaction gets mined and we can grab the receipt.
It fails if the retry counter is excedded.

The behaviour of this method varies based on the client type.

If it's called with the websocket client or the ipc client it will create a subscription for new block and wait
until the transaction gets mined. Otherwise it will use the rpc_client `pooling_interval` property.

### Signature

```zig
pub fn waitForTransactionReceipt(self: *WalletSelf, tx_hash: Hash, confirmations: u8) (Error || error{
    FailedToGetReceipt,
    TransactionReceiptNotFound,
    TransactionNotFound,
    InvalidBlockNumber,
    FailedToUnsubscribe,
})!RPCResponse(TransactionReceipt)
```

