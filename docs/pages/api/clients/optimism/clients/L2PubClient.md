## L2Client
Optimism client used for L2 interactions.
Currently only supports OP and not other chains of the superchain.

### Signature

```zig
pub fn L2Client(comptime client_type: Clients) type
```

## Init
Starts the RPC connection
If the contracts are null it defaults to OP contracts.

### Signature

```zig
pub fn init(opts: InitOpts) !*L2
```

## Deinit
Frees and destroys any allocated memory

### Signature

```zig
pub fn deinit(self: *L2) void
```

## EstimateL1Gas
Returns the L1 gas used to execute L2 transactions

### Signature

```zig
pub fn estimateL1Gas(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei
```

## EstimateL1GasFee
Returns the L1 fee used to execute L2 transactions

### Signature

```zig
pub fn estimateL1GasFee(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei
```

## EstimateTotalFees
Estimates the L1 + L2 fees to execute a transaction on L2

### Signature

```zig
pub fn estimateTotalFees(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei
```

## EstimateTotalGas
Estimates the L1 + L2 gas to execute a transaction on L2

### Signature

```zig
pub fn estimateTotalGas(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei
```

## GetBaseL1Fee
Returns the base fee on L1

### Signature

```zig
pub fn getBaseL1Fee(self: *L2) !Wei
```

## GetWithdrawMessages
Gets the decoded withdrawl event logs from a given transaction receipt hash.

### Signature

```zig
pub fn getWithdrawMessages(self: *L2, tx_hash: Hash) !Message
```

