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
transaction type. This is thread safe.\
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
Gets the last node from the pool and removes it.\
This is thread safe.

### Signature

```zig
pub fn getFirstElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope
```

### GetLastElementFromPool
Gets the last node from the pool and removes it.\
This is thread safe.

### Signature

```zig
pub fn getLastElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope
```

### Deinit
Destroys all created pointer. All future operations will deadlock.\
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
mirror 100% in terms of their methods.\
The client's methods can all be accessed under `rpc_client`.\
The same goes for the signer.

### Signature

```zig
pub fn Wallet(comptime client_type: WalletClients) type
```

## Init
Init wallet instance. Must call `deinit` to clean up.\
The init opts will depend on the `client_type`.

### Signature

```zig
pub fn init(private_key: ?Hash, opts: InitOpts) !*Wallet(client_type)
```

## AssertTransaction
Asserts that the transactions is ready to be sent.\
Will return errors where the values are not expected

### Signature

```zig
pub fn assertTransaction(self: *Wallet(client_type), tx: TransactionEnvelope) !void
```

## FindTransactionEnvelopeFromPool
Find a specific prepared envelope from the pool based on the given search criteria.

### Signature

```zig
pub fn findTransactionEnvelopeFromPool(self: *Wallet(client_type), search: TransactionEnvelopePool.SearchCriteria) ?TransactionEnvelope
```

## GetWalletAddress
Get the wallet address.\
Uses the wallet public key to generate the address.\
This will allocate and the returned address is already checksumed

### Signature

```zig
pub fn getWalletAddress(self: *Wallet(client_type)) Address
```

## PoolTransactionEnvelope
Converts unprepared transaction envelopes and stores them in a pool.\
If you want to store transaction for the future it's best to manange
the wallet nonce manually since otherwise they might get stored with
the same nonce if the wallet was unable to update it.

### Signature

```zig
pub fn poolTransactionEnvelope(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !void
```

## PrepareTransaction
Prepares a transaction based on it's type so that it can be sent through the network.\
Only the null struct properties will get changed.\
Everything that gets set before will not be touched.

### Signature

```zig
pub fn prepareTransaction(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !TransactionEnvelope
```

## SearchPoolAndSendTransaction
Search the internal `TransactionEnvelopePool` to find the specified transaction based on the `type` and nonce.\
If there are duplicate transaction that meet the search criteria it will send the first it can find.\
The search is linear and starts from the first node of the pool.

### Signature

```zig
pub fn searchPoolAndSendTransaction(self: *Wallet(client_type), search_opts: TransactionEnvelopePool.SearchCriteria) !RPCResponse(Hash)
```

## SendBlobTransaction
Sends blob transaction to the network
Trusted setup must be loaded otherwise this will fail.

### Signature

```zig
pub fn sendBlobTransaction(
            self: *Wallet(client_type),
            blobs: []const Blob,
            unprepared_envelope: UnpreparedTransactionEnvelope,
            trusted_setup: *KZG4844,
        ) !RPCResponse(Hash)
```

## SendSidecarTransaction
Sends blob transaction to the network
This uses and already prepared sidecar.

### Signature

```zig
pub fn sendSidecarTransaction(
            self: *Wallet(client_type),
            sidecars: []const Sidecar,
            unprepared_envelope: UnpreparedTransactionEnvelope,
        ) !RPCResponse(Hash)
```

## SendSignedTransaction
Signs, serializes and send the transaction via `eth_sendRawTransaction`.\
Returns the transaction hash.

### Signature

```zig
pub fn sendSignedTransaction(self: *Wallet(client_type), tx: TransactionEnvelope) !RPCResponse(Hash)
```

## SendTransaction
Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.\
If any envelope is in the envelope pool it will use that instead in a LIFO order
Will return an error if the envelope is incorrect

### Signature

```zig
pub fn sendTransaction(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !RPCResponse(Hash)
```

## SignEthereumMessage
Signs an ethereum message with the specified prefix.\
The Signatures recoverId doesn't include the chain_id

### Signature

```zig
pub fn signEthereumMessage(self: *Wallet(client_type), message: []const u8) !Signature
```

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

### Signature

```zig
pub fn signTypedData(
            self: *Wallet(client_type),
            comptime eip_types: anytype,
            comptime primary_type: []const u8,
            domain: ?TypedDataDomain,
            message: anytype,
        ) !Signature
```

## VerifyMessage
Verifies if a given signature was signed by the current wallet.

### Signature

```zig
pub fn verifyMessage(self: *Wallet(client_type), sig: Signature, message: []const u8) bool
```

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

### Signature

```zig
pub fn verifyTypedData(
            self: *Wallet(client_type),
            sig: Signature,
            comptime eip712_types: anytype,
            comptime primary_type: []const u8,
            domain: ?TypedDataDomain,
            message: anytype,
        ) !bool
```

## WaitForTransactionReceipt
Waits until the transaction gets mined and we can grab the receipt.\
It fails if the retry counter is excedded.\
The behaviour of this method varies based on the client type.\
If it's called with the websocket client or the ipc client it will create a subscription for new block and wait
until the transaction gets mined. Otherwise it will use the rpc_client `pooling_interval` property.

### Signature

```zig
pub fn waitForTransactionReceipt(self: *Wallet(client_type), tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt)
```

