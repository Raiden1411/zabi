## SerializeTransaction
Main function to serialize transactions.\
Support london, berlin and legacy transaction envelopes.\
For cancun transactions with blobs use the `serializeCancunTransactionWithBlob` function. This
will panic if you call this with the cancun transaction envelope.\
Caller ownes the memory

## SerializeCancunTransaction
Serializes a cancun type transactions without blobs.\
Please use `serializeCancunTransactionWithSidecars` or
`serializeCancunTransactionWithBlobs` if you want to
serialize them as a wrapper

## SerializeCancunTransactionWithBlobs
Serializes a cancun sidecars into the eip4844 wrapper.

## SerializeCancunTransactionWithSidecars
Serializes a cancun sidecars into the eip4844 wrapper.

## SerializeTransactionEIP1559
Function to serialize eip1559 transactions.\
Caller ownes the memory

## SerializeTransactionEIP2930
Function to serialize eip2930 transactions.\
Caller ownes the memory

## SerializeTransactionLegacy
Function to serialize legacy transactions.\
Caller ownes the memory

## PrepareAccessList
Serializes the access list into a slice of tuples of hex values.

