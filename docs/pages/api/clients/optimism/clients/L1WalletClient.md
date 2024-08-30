## L1WalletClient
Optimism  wallet client used for L2 interactions.
Currently only supports OP and not other chains of the superchain.
This implementation is not as robust as the `Wallet` implementation.

### Signature

```zig
pub fn L1WalletClient(client_type: Clients) type
```

## Init
Starts the wallet client. Init options depend on the client type.
This has all the expected L2 actions. If you are looking for L1 actions
consider using `L1WalletClient`

If the contracts are null it defaults to OP contracts.
Caller must deinit after use.

### Signature

```zig
pub fn init(priv_key: ?Hash, opts: InitOpts) !*L1Wallet
```

## Deinit
Frees and destroys any allocated memory

### Signature

```zig
pub fn deinit(self: *L1Wallet) void
```

## EstimateInitiateWithdrawal
Estimates the gas cost for calling `initiateWithdrawal`

### Signature

```zig
pub fn estimateInitiateWithdrawal(self: *L1Wallet, data: Hex) !RPCResponse(Gwei)
```

## InitiateWithdrawal
Invokes the contract method to `initiateWithdrawal`. This will send
a transaction to the network.

### Signature

```zig
pub fn initiateWithdrawal(self: *L1Wallet, request: WithdrawalRequest) !RPCResponse(Hash)
```

## PrepareInitiateWithdrawal
Prepares the interaction with the contract method to `initiateWithdrawal`.

### Signature

```zig
pub fn prepareInitiateWithdrawal(self: *L1Wallet, request: WithdrawalRequest) !PreparedWithdrawal
```

## SendTransaction
Sends a transaction envelope to the network. This serializes, hashes and signed before
sending the transaction.

### Signature

```zig
pub fn sendTransaction(self: *L1Wallet, envelope: LondonTransactionEnvelope) !RPCResponse(Hash)
```

