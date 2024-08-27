## WalletL1Client
Optimism wallet client used for L1 interactions.\
Currently only supports OP and not other chains of the superchain.\
This implementation is not as robust as the `Wallet` implementation.

### Signature

```zig
pub fn WalletL1Client(client_type: Clients) type
```

## Init
Starts the wallet client. Init options depend on the client type.\
This has all the expected L1 actions. If you are looking for L2 actions
consider using `L2WalletClient`
If the contracts are null it defaults to OP contracts.\
Caller must deinit after use.

### Signature

```zig
pub fn init(priv_key: ?Hash, opts: InitOpts) !*WalletL1
```

## Deinit
Frees and destroys any allocated memory

### Signature

```zig
pub fn deinit(self: *WalletL1) void
```

## DepositTransaction
Invokes the contract method to `depositTransaction`. This will send
a transaction to the network.

### Signature

```zig
pub fn depositTransaction(self: *WalletL1, deposit_envelope: DepositEnvelope) !RPCResponse(Hash)
```

## EstimateDepositTransaction
Estimate the gas cost for the deposit transaction.\
Uses the portalAddress. The data is expected to be hex abi encoded data.

### Signature

```zig
pub fn estimateDepositTransaction(self: *WalletL1, data: Hex) !RPCResponse(Gwei)
```

## EstimateFinalizeWithdrawal
Estimates the gas cost for calling `finalizeWithdrawal`

### Signature

```zig
pub fn estimateFinalizeWithdrawal(self: *WalletL1, data: Hex) !RPCResponse(Gwei)
```

## EstimateProveWithdrawal
Estimates the gas cost for calling `proveWithdrawal`

### Signature

```zig
pub fn estimateProveWithdrawal(self: *WalletL1, data: Hex) !RPCResponse(Gwei)
```

## FinalizeWithdrawal
Invokes the contract method to `finalizeWithdrawalTransaction`. This will send
a transaction to the network.

### Signature

```zig
pub fn finalizeWithdrawal(self: *WalletL1, withdrawal: WithdrawalNoHash) !RPCResponse(Hash)
```

## PrepareWithdrawalProofTransaction
Prepares a proof withdrawal transaction.

### Signature

```zig
pub fn prepareWithdrawalProofTransaction(self: *WalletL1, withdrawal: Withdrawal, l2_output: L2Output) !WithdrawalEnvelope
```

## ProveWithdrawal
Invokes the contract method to `proveWithdrawalTransaction`. This will send
a transaction to the network.

### Signature

```zig
pub fn proveWithdrawal(self: *WalletL1, withdrawal: WithdrawalNoHash, l2_output_index: u256, outputRootProof: RootProof, withdrawal_proof: []const Hex) !RPCResponse(Hash)
```

## PrepareDepositTransaction
Prepares the deposit transaction. Will error if its a creation transaction
and a `to` address was given. It will also fail if the mint and value do not match.

### Signature

```zig
pub fn prepareDepositTransaction(self: *WalletL1, deposit_envelope: DepositEnvelope) !DepositData
```

## SendTransaction
Sends a transaction envelope to the network. This serializes, hashes and signed before
sending the transaction.

### Signature

```zig
pub fn sendTransaction(self: *WalletL1, envelope: LondonTransactionEnvelope) !RPCResponse(Hash)
```

