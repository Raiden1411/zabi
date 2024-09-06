## ContractComptime
Wrapper on a wallet and comptime know Abi

### Signature

```zig
pub fn ContractComptime(comptime client_type: ClientType) type
```

## SendErrors

Set of possible errors when sending a transaction to the network.

```zig
EncodeErrors || WalletClient.SendSignedTransactionErrors || WalletClient.AssertionErrors || WalletClient.PrepareError
```

## ReadErrors

Set of possible errors when sending a transaction to the network.

```zig
EncodeErrors || WalletClient.Error || DecoderErrors
```

## Init
Initiates the wallet.

### Signature

```zig
pub fn init(opts: ContractInitOpts) WalletClient.InitErrors!*ContractComptime(client_type)
```

## Deinit
Deinits the wallet instance.

### Signature

```zig
pub fn deinit(self: *ContractComptime(client_type)) void
```

## DeployContract
Creates a contract on the network.
If the constructor abi contains inputs it will encode `constructor_args` accordingly.

### Signature

```zig
pub fn deployContract(
    self: *ContractComptime(client_type),
    comptime constructor: Constructor,
    opts: ConstructorOpts(constructor),
) (SendErrors || error{ CreatingContractToKnowAddress, ValueInNonPayableConstructor })!RPCResponse(Hash)
```

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
The transaction will not be added to the blockchain.
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.

RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

### Signature

```zig
pub fn estimateGas(self: *ContractComptime(client_type), call_object: EthCall, opts: BlockNumberRequest) WalletClient.Error!RPCResponse(Gwei)
```

## ReadContractFunction
Uses eth_call to query an contract information.
Only abi items that are either `view` or `pure` will be allowed.
It won't commit a transaction to the network.

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn readContractFunction(
    self: *ContractComptime(client_type),
    comptime func: Function,
    opts: FunctionOpts(func, EthCall),
) (ReadErrors || error{ InvalidFunctionMutability, InvalidRequestTarget })!AbiDecoded(AbiParametersToPrimative(func.outputs))
```

## SimulateWriteCall
Uses eth_call to simulate a contract interaction.
It won't commit a transaction to the network.
I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn simulateWriteCall(
    self: *ContractComptime(client_type),
    comptime func: Function,
    opts: FunctionOpts(func, UnpreparedTransactionEnvelope),
) (ReadErrors || error{ InvalidRequestTarget, UnsupportedTransactionType })!RPCResponse(Hex)
```

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceipt(self: *ContractComptime(client_type), tx_hash: Hash, confirmations: u8) (WalletClient.Error || error{
    FailedToGetReceipt,
    TransactionReceiptNotFound,
    TransactionNotFound,
    InvalidBlockNumber,
    FailedToUnsubscribe,
})!RPCResponse(TransactionReceipt)
```

## WriteContractFunction
Encodes the function arguments based on the function abi item.
Only abi items that are either `payable` or `nonpayable` will be allowed.
It will send the transaction to the network and return the transaction hash.

RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

### Signature

```zig
pub fn writeContractFunction(
    self: *ContractComptime(client_type),
    comptime func: Function,
    opts: FunctionOpts(func, UnpreparedTransactionEnvelope),
) (SendErrors || error{ InvalidFunctionMutability, InvalidRequestTarget, ValueInNonPayableFunction })!RPCResponse(Hash)
```

## Contract
Wrapper on a wallet and Abi

### Signature

```zig
pub fn Contract(comptime client_type: ClientType) type
```

## SendErrors

Set of possible errors when sending a transaction to the network.

```zig
EncodeErrors || WalletClient.SendSignedTransactionErrors ||
            WalletClient.AssertionErrors || WalletClient.PrepareError || error{ AbiItemNotFound, NotSupported }
```

## ReadErrors

Set of possible errors when sending a transaction to the network.

```zig
EncodeErrors || WalletClient.Error || DecoderErrors || error{ AbiItemNotFound, NotSupported }
```

## Init
Starts the wallet instance and sets the abi.

### Signature

```zig
pub fn init(opts: ContractInitOpts) WalletClient.InitErrors!*Contract(client_type)
```

## Deinit
Deinits the wallet instance.

### Signature

```zig
pub fn deinit(self: *Contract(client_type)) void
```

## DeployContract
Creates a contract on the network.
If the constructor abi contains inputs it will encode `constructor_args` accordingly.

### Signature

```zig
pub fn deployContract(
    self: *Contract(client_type),
    constructor_args: anytype,
    bytecode: Hex,
    overrides: UnpreparedTransactionEnvelope,
) (SendErrors || error{ CreatingContractToKnowAddress, ValueInNonPayableConstructor })!RPCResponse(Hash)
```

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
The transaction will not be added to the blockchain.
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.

RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

### Signature

```zig
pub fn estimateGas(
    self: *Contract(client_type),
    call_object: EthCall,
    opts: BlockNumberRequest,
) WalletClient.Error!RPCResponse(Gwei)
```

## ReadContractFunction
Uses eth_call to query an contract information.
Only abi items that are either `view` or `pure` will be allowed.
It won't commit a transaction to the network.

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn readContractFunction(
    self: *Contract(client_type),
    comptime T: type,
    function_name: []const u8,
    function_args: anytype,
    overrides: EthCall,
) (ReadErrors || error{ InvalidFunctionMutability, InvalidRequestTarget })!AbiDecoded(T)
```

## SimulateWriteCall
Uses eth_call to simulate a contract interaction.
It won't commit a transaction to the network.
I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn simulateWriteCall(
    self: *Contract(client_type),
    function_name: []const u8,
    function_args: anytype,
    overrides: UnpreparedTransactionEnvelope,
) (ReadErrors || error{ InvalidRequestTarget, UnsupportedTransactionType })!RPCResponse(Hex)
```

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceipt(self: *ContractComptime(client_type), tx_hash: Hash, confirmations: u8) (WalletClient.Error || error{
    FailedToGetReceipt,
    TransactionReceiptNotFound,
    TransactionNotFound,
    InvalidBlockNumber,
    FailedToUnsubscribe,
})!RPCResponse(TransactionReceipt)
```

## WriteContractFunction
Encodes the function arguments based on the function abi item.
Only abi items that are either `payable` or `nonpayable` will be allowed.
It will send the transaction to the network and return the transaction hash.

RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

### Signature

```zig
pub fn writeContractFunction(
    self: *Contract(client_type),
    function_name: []const u8,
    function_args: anytype,
    overrides: UnpreparedTransactionEnvelope,
) (SendErrors || error{ InvalidFunctionMutability, InvalidRequestTarget, ValueInNonPayableFunction })!RPCResponse(Hash)
```

