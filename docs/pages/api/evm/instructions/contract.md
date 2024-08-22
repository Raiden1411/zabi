## CallInstruction
Performs call instruction for the interpreter.\
CALL -> 0xF1

## CallCodeInstruction
Performs callcode instruction for the interpreter.\
CALLCODE -> 0xF2

## CreateInstruction
Performs create instruction for the interpreter.\
CREATE -> 0xF0 and CREATE2 -> 0xF5

## DelegateCallInstruction
Performs delegatecall instruction for the interpreter.\
DELEGATECALL -> 0xF4

## StaticCallInstruction
Performs staticcall instruction for the interpreter.\
STATICCALL -> 0xFA

## CalculateCall

## GetMemoryInputsAndRanges
Gets the memory slice and the ranges used to grab it.\
This also resizes the interpreter's memory.

## ResizeMemoryAndGetRange
Resizes the memory as gets the offset ranges.

