## L1Client
Optimism client used for L1 interactions.\
Currently only supports OP and not other chains of the superchain.

### Signature

```zig
pub fn L1Client(comptime client_type: Clients) type
```

## Init
Starts the RPC connection
If the contracts are null it defaults to OP contracts.

### Signature

```zig
pub fn init(opts: InitOpts) !*L1
```

## Deinit
Frees and destroys any allocated memory

### Signature

```zig
pub fn deinit(self: *L1) void
```

## GetGame
Retrieves a valid dispute game on an L2 that occurred after a provided L2 block number.\
Returns an error if no game was found.\
`limit` is the max amount of game to search
`block_number` to filter only games that occurred after this block.\
`strategy` is weather to provide the latest game or one at random with the scope of the games that where found given the filters.

### Signature

```zig
pub fn getGame(self: *L1, limit: usize, block_number: u256, strategy: enum { random, latest, oldest }) !GameResult
```

## GetGames
Retrieves the dispute games for an L2
`limit` is the max amount of game to search
`block_number` to filter only games that occurred after this block.\
If null then it will return all games.

### Signature

```zig
pub fn getGames(self: *L1, limit: usize, block_number: ?u256) ![]const GameResult
```

## GetFinalizedWithdrawals
Returns if a withdrawal has finalized or not.

### Signature

```zig
pub fn getFinalizedWithdrawals(self: *L1, withdrawal_hash: Hash) !bool
```

## GetLatestProposedL2BlockNumber
Gets the latest proposed L2 block number from the Oracle.

### Signature

```zig
pub fn getLatestProposedL2BlockNumber(self: *L1) !u64
```

## GetL2HashesForDepositTransaction
Gets the l2 transaction hashes for the deposit transaction event.\
`hash` is expected to be the transaction hash from the deposit transaction.

### Signature

```zig
pub fn getL2HashesForDepositTransaction(self: *L1, tx_hash: Hash) ![]const Hash
```

## GetL2Output
Calls to the L2OutputOracle contract on L1 to get the output for a given L2 block

### Signature

```zig
pub fn getL2Output(self: *L1, l2_block_number: u256) !L2Output
```

## GetL2OutputIndex
Calls to the L2OutputOracle on L1 to get the output index.

### Signature

```zig
pub fn getL2OutputIndex(self: *L1, l2_block_number: u256) !u256
```

## GetPortalVersion
Retrieves the current version of the Portal contract.\
If the major is at least 3 it means that fault proofs are enabled.

### Signature

```zig
pub fn getPortalVersion(self: *L1) !SemanticVersion
```

## GetProvenWithdrawals
Gets a proven withdrawal.\
Will call the portal contract to get the information. If the timestamp is 0
this will error with invalid withdrawal hash.

### Signature

```zig
pub fn getProvenWithdrawals(self: *L1, withdrawal_hash: Hash) !ProvenWithdrawal
```

## GetSecondsToNextL2Output
Gets the amount of time to wait in ms until the next output is posted.\
Calls the l2OutputOracle to get this information.

### Signature

```zig
pub fn getSecondsToNextL2Output(self: *L1, latest_l2_block: u64) !u128
```

## GetSecondsToFinalize
Gets the amount of time to wait until a withdrawal is finalized.\
Calls the l2OutputOracle to get this information.

### Signature

```zig
pub fn getSecondsToFinalize(self: *L1, withdrawal_hash: Hash) !u64
```

## GetSecondsToFinalizeGame
Gets the amount of time to wait until a dispute game has finalized
Uses the portal to find this information. Will error if the time is 0.

### Signature

```zig
pub fn getSecondsToFinalizeGame(self: *L1, withdrawal_hash: Hash) !u64
```

## GetSecondsUntilNextGame
Gets the timings until the next dispute game is submitted based on the provided `l2BlockNumber`

### Signature

```zig
pub fn getSecondsUntilNextGame(self: *L1, interval_buffer: f64, l2BlockNumber: u64) !NextGameTimings
```

## GetTransactionDepositEvents
Gets the `TransactionDeposited` event logs from a transaction hash.\
To free the memory of this slice you will also need to loop through the
returned slice and free the `opaqueData` field. Memory will be duped
on that field because we destroy the Arena from the RPC request that owns
the original piece of memory that contains the data.

### Signature

```zig
pub fn getTransactionDepositEvents(self: *L1, tx_hash: Hash) ![]const TransactionDeposited
```

## GetWithdrawMessages
Gets the decoded withdrawl event logs from a given transaction receipt hash.

### Signature

```zig
pub fn getWithdrawMessages(self: *L1, tx_hash: Hash) !Message
```

## WaitForNextGame
Waits until the next dispute game to be submitted based on the provided `l2BlockNumber`
This will keep pooling until it can get the `GameResult` or it exceeds the max retries.

### Signature

```zig
pub fn waitForNextGame(self: *L1, limit: usize, interval_buffer: f64, l2BlockNumber: u64) !GameResult
```

## WaitForNextL2Output
Waits until the next L2 output is posted.\
This will keep pooling until it can get the L2Output or it exceeds the max retries.

### Signature

```zig
pub fn waitForNextL2Output(self: *L1, latest_l2_block: u64) !L2Output
```

## WaitToFinalize
Waits until the withdrawal has finalized.

### Signature

```zig
pub fn waitToFinalize(self: *L1, withdrawal_hash: Hash) !void
```

