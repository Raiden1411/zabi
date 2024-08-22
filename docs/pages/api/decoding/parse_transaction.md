## ParsedTransaction

## Deinit

## ParseTransaction
Parses unsigned serialized transactions. Creates and arena to manage memory.\
Caller needs to call deinit to free memory.

## ParseTransactionLeaky
Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseEip4844Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseEip1559Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseEip2930Transaction
Parses unsigned serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseLegacyTransaction
Parses unsigned serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseSignedTransaction
Parses signed serialized transactions. Creates and arena to manage memory.\
Caller needs to call deinit to free memory.

## ParseSignedTransactionLeaky
Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseSignedEip4844Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseSignedEip1559Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseSignedEip2930Transaction
Parses signed serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseSignedLegacyTransaction
Parses signed serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

## ParseAccessList
Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.

