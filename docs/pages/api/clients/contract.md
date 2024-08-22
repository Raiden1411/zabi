## ContractComptime
Wrapper on a wallet and comptime know Abi

## Init
Deinits the wallet instance.

## Deinit
Deinits the wallet instance.

## DeployContract
Creates a contract on the network.\
If the constructor abi contains inputs it will encode `constructor_args` accordingly.

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.\
The transaction will not be added to the blockchain.\
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.\
RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

## ReadContractFunction
Uses eth_call to query an contract information.\
Only abi items that are either `view` or `pure` will be allowed.\
It won't commit a transaction to the network.\
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

## SimulateWriteCall
Uses eth_call to simulate a contract interaction.\
It won't commit a transaction to the network.\
I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.\
This is retry based on either the amount of `confirmations` given.\
If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.\
RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

## WriteContractFunction
Encodes the function arguments based on the function abi item.\
Only abi items that are either `payable` or `nonpayable` will be allowed.\
It will send the transaction to the network and return the transaction hash.\
RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

## Contract
Wrapper on a wallet and Abi

## Init

## Deinit
Deinits the wallet instance.

## DeployContract
Creates a contract on the network.\
If the constructor abi contains inputs it will encode `constructor_args` accordingly.

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.\
The transaction will not be added to the blockchain.\
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.\
RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

## ReadContractFunction
Uses eth_call to query an contract information.\
Only abi items that are either `view` or `pure` will be allowed.\
It won't commit a transaction to the network.\
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

## SimulateWriteCall
Uses eth_call to simulate a contract interaction.\
It won't commit a transaction to the network.\
I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.\
This is retry based on either the amount of `confirmations` given.\
If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.\
RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

## WriteContractFunction
Encodes the function arguments based on the function abi item.\
Only abi items that are either `payable` or `nonpayable` will be allowed.\
It will send the transaction to the network and return the transaction hash.\
RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

