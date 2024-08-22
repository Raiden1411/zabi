## EncodeErrors

## PreEncodedParam

## Deinit

## AbiEncoded

## Deinit

## EncodeAbiConstructorComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

## EncodeAbiErrorComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

## EncodeAbiFunctionComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

## EncodeAbiFunctionOutputsComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

## EncodeAbiParametersComptime
Main function that will be used to encode abi paramters.\
This will allocate and a ArenaAllocator will be used to manage the memory.\
Caller owns the memory.

## EncodeAbiParametersLeakyComptime
Subset function used for encoding. Its highly recommend to use an ArenaAllocator
or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
and with those all of the memory can be freed at once.\
Caller owns the memory.

## EncodeAbiParameters
Main function that will be used to encode abi paramters.\
This will allocate and a ArenaAllocator will be used to manage the memory.\
Caller owns the memory.\
If the parameters are comptime know consider using `encodeAbiParametersComptime`
This will provided type safe values to be passed into the function.\
However runtime reflection will happen to best determine what values should be used based
on the parameters passed in.

## EncodeAbiParametersLeaky
Subset function used for encoding. Its highly recommend to use an ArenaAllocator
or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
and with those all of the memory can be freed at once.\
Caller owns the memory.\
If the parameters are comptime know consider using `encodeAbiParametersComptimeLeaky`
This will provided type safe values to be passed into the function.\
However runtime reflection will happen to best determine what values should be used based
on the parameters passed in.

## EncodePacked
Encode values based on solidity's `encodePacked`.\
Solidity types are infered from zig ones since it closely follows them.\
Caller owns the memory and it must free them.

