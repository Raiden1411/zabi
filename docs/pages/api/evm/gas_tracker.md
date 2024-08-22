## QUICK_STEP

## FASTEST_STEP

## FAST_STEP

## MID_STEP

## SLOW_STEP

## EXT_STEP

## JUMPDEST

## SELFDESTRUCT

## CREATE

## CALLVALUE

## NEWACCOUNT

## LOG

## LOGDATA

## LOGTOPIC

## KECCAK256

## KECCAK256WORD

## BLOCKHASH

## CODEDEPOSIT

## CONDITION_JUMP_GAS

## RETF_GAS

## DATA_LOAD_GAS

## ISTANBUL_SLOAD_GAS
EIP-1884: Repricing for trie-size-dependent opcodes

## SSTORE_SET

## SSTORE_RESET

## REFUND_SSTORE_CLEARS

## TRANSACTION_ZERO_DATA

## TRANSACTION_NON_ZERO_DATA_INIT

## TRANSACTION_NON_ZERO_DATA_FRONTIER

## EOF_CREATE_GAS

## ACCESS_LIST_ADDRESS

## ACCESS_LIST_STORAGE_KEY

## COLD_SLOAD_COST

## COLD_ACCOUNT_ACCESS_COST

## WARM_STORAGE_READ_COST

## WARM_SSTORE_RESET

## INITCODE_WORD_COST
EIP-3860 : Limit and meter initcode

## CALL_STIPEND

## GasTracker
Gas tracker used to track gas usage by the EVM.

## Init
Sets the tracker's initial state.

## AvailableGas
Returns the remaining gas that can be used.

## UpdateTracker

## CalculateCallCost

## CalculateCodeSizeCost

## CalculateCostPerMemoryWord

## CalculateCreateCost

## CalculateCreate2Cost

## CalculateExponentCost

## CalculateExtCodeCopyCost

## CalculateKeccakCost

## CalculateLogCost

## CalculateMemoryCost

## CalculateMemoryCopyLowCost

## CalculateFrontierSstoreCost

## CalculateIstanbulSstoreCost

## CalculateSloadCost

## CalculateSstoreCost

## CalculateSstoreRefund

## CalculateSelfDestructCost

## WarmOrColdCost

