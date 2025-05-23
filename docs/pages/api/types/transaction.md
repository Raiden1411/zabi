## BerlinEnvelope

Tuple representing an encoded envelope for the Berlin hardfork.

```zig
StructToTupleType(BerlinTransactionEnvelope)
```

## BerlinEnvelopeSigned

Tuple representing an encoded envelope for the Berlin hardfork with the signature.

```zig
StructToTupleType(BerlinTransactionEnvelopeSigned)
```

## CancunEnvelope

Tuple representing an encoded envelope for the London hardfork.

```zig
StructToTupleType(CancunTransactionEnvelope)
```

## CancunEnvelopeSigned

Tuple representing an encoded envelope for the London hardfork with the signature.

```zig
StructToTupleType(CancunTransactionEnvelopeSigned)
```

## CancunSignedWrapper

Signed cancun transaction converted to wrapper with blobs, commitments and proofs.

```zig
Merge(StructToTupleType(CancunTransactionEnvelopeSigned), struct { []const Blob, []const KZGCommitment, []const KZGProof })
```

## CancunWrapper

Cancun transaction converted to wrapper with blobs, commitments and proofs.

```zig
Merge(StructToTupleType(CancunTransactionEnvelope), struct { []const Blob, []const KZGCommitment, []const KZGProof })
```

## Eip7702Envelope

Tuple representing EIP 7702 authorization envelope tuple.

```zig
StructToTupleType(Eip7702TransactionEnvelope)
```

## Eip7702EnvelopeSigned

Tuple representing EIP 7702 authorization envelope tuple with the signature.

```zig
StructToTupleType(Eip7702TransactionEnvelopeSigned)
```

## LegacyEnvelope

Tuple representing an encoded envelope for a legacy transaction.

```zig
StructToTupleType(Omit(LegacyTransactionEnvelope, &.{"chainId"}))
```

## LegacyEnvelopeSigned

Tuple representing an encoded envelope for a legacy transaction with the signature.

```zig
StructToTupleType(Omit(LegacyTransactionEnvelopeSigned, &.{"chainId"}))
```

## LondonEnvelope

Tuple representing an encoded envelope for the London hardfork.

```zig
StructToTupleType(LondonTransactionEnvelope)
```

## LondonEnvelopeSigned

Tuple representing an encoded envelope for the London hardfork with the signature.

```zig
StructToTupleType(LondonTransactionEnvelopeSigned)
```

## TransactionTypes

All of the transaction types.

### Properties

```zig
enum {
  legacy = 0x00
  berlin = 0x01
  london = 0x02
  cancun = 0x03
  eip7702 = 0x04
  deposit = 0x7e
  _
}
```

## TransactionEnvelope

The transaction envelope that will be serialized before getting sent to the network.

### Properties

```zig
union(enum) {
  berlin: BerlinTransactionEnvelope
  cancun: CancunTransactionEnvelope
  eip7702: Eip7702TransactionEnvelope
  legacy: LegacyTransactionEnvelope
  london: LondonTransactionEnvelope
}
```

## Eip7702TransactionEnvelope

The transaction envelope from eip7702.

### Properties

```zig
struct {
  chainId: u64
  nonce: u64
  maxPriorityFeePerGas: u64
  maxFeePerGas: u64
  gas: u64
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  authorizationList: []const AuthorizationPayload
}
```

## CancunTransactionEnvelope

The transaction envelope from the Cancun hardfork

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  gas: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  maxFeePerBlobGas: Gwei
  blobVersionedHashes: ?[]const Hash = null
}
```

## LondonTransactionEnvelope

The transaction envelope from the London hardfork

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  gas: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
}
```

## BerlinTransactionEnvelope

The transaction envelope from the Berlin hardfork

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  gas: Gwei
  gasPrice: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
}
```

## LegacyTransactionEnvelope

The transaction envelope from a legacy transaction

### Properties

```zig
struct {
  chainId: usize = 0
  nonce: u64
  gas: Gwei
  gasPrice: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
}
```

## AccessList

Struct representing the accessList field.

### Properties

```zig
struct {
  address: Address
  storageKeys: []const Hash
}
```

## AuthorizationPayload

EIP7702 authorization payload.

### Properties

```zig
struct {
  chain_id: u64
  address: Address
  nonce: u64
  y_parity: u8
  r: u256
  s: u256
}
```

## AccessListResult

Struct representing the result of create accessList

### Properties

```zig
struct {
  accessList: []const AccessList
  gasUsed: Gwei
}
```

## TransactionEnvelopeSigned

Signed transaction envelope with the signature fields

### Properties

```zig
union(enum) {
  berlin: BerlinTransactionEnvelopeSigned
  cancun: CancunTransactionEnvelopeSigned
  eip7702: Eip7702TransactionEnvelopeSigned
  legacy: LegacyTransactionEnvelopeSigned
  london: LondonTransactionEnvelopeSigned
}
```

## Eip7702TransactionEnvelopeSigned

The transaction envelope from eip7702.

### Properties

```zig
struct {
  chainId: u64
  nonce: u64
  maxPriorityFeePerGas: u64
  maxFeePerGas: u64
  gas: u64
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  authorizationList: []const AuthorizationPayload
  v: u2
  r: u256
  s: u256
}
```

## CancunTransactionEnvelopeSigned

The transaction envelope from the London hardfork with the signature fields

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  gas: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  maxFeePerBlobGas: Gwei
  blobVersionedHashes: ?[]const Hash = null
  v: u2
  r: u256
  s: u256
}
```

## LondonTransactionEnvelopeSigned

The transaction envelope from the London hardfork with the signature fields

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  gas: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  v: u2
  r: u256
  s: u256
}
```

## BerlinTransactionEnvelopeSigned

The transaction envelope from the Berlin hardfork with the signature fields

### Properties

```zig
struct {
  chainId: usize
  nonce: u64
  gas: Gwei
  gasPrice: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  accessList: []const AccessList
  v: u2
  r: u256
  s: u256
}
```

## LegacyTransactionEnvelopeSigned

The transaction envelope from a legacy transaction with the signature fields

### Properties

```zig
struct {
  chainId: usize = 0
  nonce: u64
  gas: Gwei
  gasPrice: Gwei
  to: ?Address = null
  value: Wei
  data: ?Hex = null
  v: usize
  r: ?u256
  s: ?u256
}
```

## UnpreparedTransactionEnvelope

Same as `Envelope` but were all fields are optionals.

### Properties

```zig
struct {
  type: TransactionTypes
  chainId: ?usize = null
  nonce: ?u64 = null
  maxFeePerBlobGas: ?Gwei = null
  maxPriorityFeePerGas: ?Gwei = null
  maxFeePerGas: ?Gwei = null
  gas: ?Gwei = null
  gasPrice: ?Gwei = null
  to: ?Address = null
  value: ?Wei = null
  data: ?Hex = null
  accessList: ?[]const AccessList = null
  blobVersionedHashes: ?[]const Hash = null
  authList: ?[]const AuthorizationPayload = null
}
```

## LondonPendingTransaction

The representation of a London hardfork pending transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: u4
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  type: TransactionTypes
  accessList: []const AccessList
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  chainId: usize
  yParity: u1
}
```

## LegacyPendingTransaction

The legacy representation of a pending transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: usize
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  type: TransactionTypes
  chainId: ?usize = null
}
```

## L2Transaction

The Cancun hardfork representation of a transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: usize
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  sourceHash: ?Hash = null
  isSystemTx: ?bool = null
  index: u64
  l1BlockNumber: u64
  l1Timestamp: u64
  l1TxOrigin: ?Hash
  queueIndex: ?u64
  queueOrigin: []const u8
  rawTransaction: Hex
}
```

## CancunTransaction

The Cancun hardfork representation of a transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: u4
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  sourceHash: ?Hash = null
  isSystemTx: ?bool = null
  type: TransactionTypes
  accessList: []const AccessList
  blobVersionedHashes: []const Hash
  maxFeePerBlobGas: Gwei
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  chainId: usize
  yParity: ?u1 = null
}
```

## LondonTransaction

The London hardfork representation of a transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: u4
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  sourceHash: ?Hash = null
  isSystemTx: ?bool = null
  type: TransactionTypes
  accessList: []const AccessList
  maxPriorityFeePerGas: Gwei
  maxFeePerGas: Gwei
  chainId: usize
  yParity: ?u1 = null
}
```

## BerlinTransaction

The Berlin hardfork representation of a transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: u8
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  sourceHash: ?Hash = null
  isSystemTx: ?bool = null
  type: TransactionTypes
  accessList: []const AccessList
  chainId: usize
  yParity: ?u1 = null
}
```

## LegacyTransaction

The legacy representation of a transaction.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: usize
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  sourceHash: ?Hash = null
  isSystemTx: ?bool = null
  type: ?TransactionTypes = null
  chainId: ?usize = null
}
```

## Transaction

All transactions objects that one might find whilest interaction
with the JSON RPC server.

### Properties

```zig
union(enum) {
  /// Legacy type transactions.
  legacy: LegacyTransaction
  /// Berlin hardfork transactions that might have the accessList.
  berlin: BerlinTransaction
  /// London hardfork transaction objects.
  london: LondonTransaction
  /// Cancun hardfork transactions.
  cancun: CancunTransaction
  /// L2 transaction objects
  l2_transaction: L2Transaction
  /// L2 Deposit transaction
  deposit: DepositTransactionSigned
}
```

## LegacyReceipt

The london and other hardforks transaction receipt representation

### Properties

```zig
struct {
  transactionHash: Hash
  transactionIndex: u64
  blockHash: Hash
  blockNumber: ?u64
  from: Address
  to: ?Address
  cumulativeGasUsed: Gwei
  effectiveGasPrice: Gwei
  gasUsed: Gwei
  contractAddress: ?Address
  logs: Logs
  logsBloom: Hex
  blobGasPrice: ?u64 = null
  type: ?TransactionTypes = null
  root: ?Hex = null
  status: ?bool = null
  deposit_nonce: ?usize = null
}
```

## CancunReceipt

Cancun transaction receipt representation

### Properties

```zig
struct {
  transactionHash: Hash
  transactionIndex: u64
  blockHash: Hash
  blockNumber: ?u64
  from: Address
  to: ?Address
  cumulativeGasUsed: Gwei
  effectiveGasPrice: Gwei
  blobGasPrice: Gwei
  blobGasUsed: Gwei
  gasUsed: Gwei
  contractAddress: ?Address
  logs: Logs
  logsBloom: Hex
  type: ?TransactionTypes = null
  root: ?Hex = null
  status: ?bool = null
  deposit_nonce: ?usize = null
}
```

## OpstackReceipt

L2 transaction receipt representation

### Properties

```zig
struct {
  transactionHash: Hash
  transactionIndex: u64
  blockHash: Hash
  blockNumber: ?u64
  from: Address
  to: ?Address
  gasUsed: Gwei
  cumulativeGasUsed: Gwei
  contractAddress: ?Address
  logs: Logs
  status: ?bool = null
  logsBloom: Hex
  type: ?TransactionTypes = null
  effectiveGasPrice: ?Gwei = null
  deposit_nonce: ?usize = null
  l1Fee: Wei
  l1GasPrice: Gwei
  l1GasUsed: Gwei
  l1FeeScalar: ?f64 = null
  root: ?Hex = null
}
```

## DepositReceipt

L2 Deposit transaction receipt representation

### Properties

```zig
struct {
  transactionHash: Hash
  transactionIndex: u64
  blockHash: Hash
  blockNumber: ?u64
  from: Address
  to: ?Address
  cumulativeGasUsed: Gwei
  gasUsed: Gwei
  contractAddress: ?Address
  logs: Logs
  status: ?bool = null
  logsBloom: Hex
  type: ?TransactionTypes = null
  effectiveGasPrice: ?Gwei = null
  deposit_nonce: ?usize = null
  depositNonce: ?u64
  depositNonceVersion: ?u64 = null
  root: ?Hex = null
}
```

## ArbitrumReceipt

Arbitrum transaction receipt representation

### Properties

```zig
struct {
  transactionHash: Hash
  blockHash: Hash
  blockNumber: ?u64
  logsBloom: Hex
  l1BlockNumber: Wei
  contractAddress: ?Address
  transactionIndex: u64
  gasUsedForL1: Gwei
  type: ?TransactionTypes = null
  gasUsed: Gwei
  cumulativeGasUsed: Gwei
  from: Address
  to: ?Address
  effectiveGasPrice: ?Gwei = null
  logs: Logs
  root: ?Hex = null
  status: ?bool = null
  deposit_nonce: ?usize = null
}
```

## TransactionReceipt

All possible transaction receipts

### Properties

```zig
union(enum) {
  legacy: LegacyReceipt
  cancun: CancunReceipt
  op_receipt: OpstackReceipt
  arbitrum_receipt: ArbitrumReceipt
  deposit_receipt: DepositReceipt
}
```

## EthCall

The representation of an `eth_call` struct.

### Properties

```zig
union(enum) {
  legacy: LegacyEthCall
  london: LondonEthCall
}
```

## LondonEthCall

The representation of an London hardfork `eth_call` struct where all fields are optional
These are optionals so that when we stringify we can
use the option `ignore_null_fields`

### Properties

```zig
struct {
  from: ?Address = null
  maxPriorityFeePerGas: ?Gwei = null
  maxFeePerGas: ?Gwei = null
  gas: ?Gwei = null
  to: ?Address = null
  value: ?Wei = null
  data: ?Hex = null
}
```

## LegacyEthCall

The representation of an `eth_call` struct where all fields are optional
These are optionals so that when we stringify we can
use the option `ignore_null_fields`

### Properties

```zig
struct {
  from: ?Address = null
  gasPrice: ?Gwei = null
  gas: ?Gwei = null
  to: ?Address = null
  value: ?Wei = null
  data: ?Hex = null
}
```

## EstimateFeeReturn

Return struct for fee estimation calculation.

### Properties

```zig
union(enum) {
  london: struct {
    max_priority_fee: Gwei,
    max_fee_gas: Gwei,
}
  legacy: struct {
    gas_price: Gwei,
}
  cancun: struct {
    max_priority_fee: Gwei,
    max_fee_gas: Gwei,
    max_fee_per_blob: Gwei,
}
}
```

## FeeHistory

Provides recent fee market data that consumers can use to determine

### Properties

```zig
struct {
  /// List of each block's base fee
  baseFeePerGas: []const u256
  /// List of each block's base blob fee
  baseFeePerBlobGas: ?[]const u256 = null
  /// Ratio of gas used out of the total available limit
  gasUsedRatio: []const f64
  /// Ratio of blob gas used out of the total available limit
  blobGasUsedRatio: ?[]const f64 = null
  /// Block corresponding to first response value
  oldestBlock: u64
  /// List every txs priority fee per block
  /// Depending on the blockCount or the newestBlock this can be null
  reward: ?[]const []const u256 = null
}
```

## DepositTransaction

Op stack deposit transaction representation.

### Properties

```zig
struct {
  sourceHash: Hash
  from: Address
  to: ?Address
  mint: u256
  value: Wei
  gas: Gwei
  isSystemTx: bool
  data: ?Hex
}
```

## DepositTransactionSigned

Op stack deposit transaction representation with the signed parameters.

### Properties

```zig
struct {
  hash: Hash
  nonce: u64
  blockHash: ?Hash
  blockNumber: ?u64
  transactionIndex: ?u64
  from: Address
  to: ?Address
  value: Wei
  gasPrice: Gwei
  gas: Gwei
  input: Hex
  v: usize
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  r: u256
  /// Represented as values instead of the hash because
  /// a valid signature is not guaranteed to be 32 bits
  s: u256
  type: TransactionTypes
  sourceHash: Hex
  mint: ?u256 = null
  isSystemTx: ?bool = null
  depositReceiptVersion: ?u64 = null
}
```

## DepositData

Op stack deposit data.

### Properties

```zig
struct {
  mint: u256
  value: Wei
  gas: Gwei
  creation: bool
  data: ?Hex
}
```

## TransactionDeposited

Op stack return type when decoding a deposit transaction from the contract.

### Properties

```zig
struct {
  from: Address
  to: Address
  version: u256
  opaqueData: Hex
  logIndex: usize
  blockHash: Hash
}
```

## DepositTransactionEnvelope

Op stack deposit envelope to be serialized.

### Properties

```zig
struct {
  gas: ?Gwei = null
  mint: ?Wei = null
  value: ?Wei = null
  creation: bool = false
  data: ?Hex = null
  to: ?Address = null
}
```

