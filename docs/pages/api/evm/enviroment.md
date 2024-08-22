## EVMEnviroment
The EVM inner enviroment.

## Default
Creates a default EVM enviroment.

## EffectiveGasPrice
Calculates the effective gas price of the transaction.

## CalculateDataFee
Calculates the `data_fee` of the transaction.\
This will return null if cancun is not enabled.\
See EIP-4844:
<https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>

## CalculateMaxDataFee
Calculates the max `data_fee` of the transaction.\
This will return null if cancun is not enabled.\
See EIP-4844:
<https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>

## ValidateBlockEnviroment
Validates the inner block enviroment based on the provided `SpecId`

## ValidateTransaction
Validates the transaction enviroment.\
For `CANCUN` enabled and later checks the gas price is not more than the transactions max
and checks if the blob_hashes are correctly set.\
For before `CANCUN` checks if `blob_hashes` and `max_fee_per_blob_gas` are null / empty.

## ConfigEnviroment
The EVM Configuration enviroment.

## Default
Returns the set of default values for a `ConfigEnviroment`.

## BlobExcessGasAndPrice
Type that representes the excess blob gas and it's price.

## Init
Calculates the price based on the provided `excess_gas`.

## BlockEnviroment
The block enviroment.

## Default
Returns a set of default values for this `BlockEnviroment`.

## TxEnviroment
The transaction enviroment.

## Default
Returns a default `TxEnviroment`.

## GetTotalBlobGas
Gets the total blob gas in this `TxEnviroment`.

## OptimismFields
Set of `Optimism` fields for the transaction enviroment.

## Default
Returns default values for `OptimismFields`

## AddressKind
The target address kind.

## AnalysisKind
The type of analysis to perform.

