## Bytecode
State of the contract's bytecode.

## Deinit
Clears the analyzed jump table.

## GetJumpTable
Returns the jump_table is the bytecode state is `analyzed`
otherwise it will return null.

## GetCodeBytes
Grabs the bytecode independent of the current state.

## AnalyzedBytecode
Representation of the analyzed bytecode.

## Init
Creates an instance of `AnalyzedBytecode`.

## Deinit
Free's the underlaying allocated memory
Assumes that the bytecode was already padded and memory was allocated.

## JumpTable
Essentially a `BitVec`

## Init
Creates the jump table. Provided size must follow the two's complement.

## Deinit
Free's the underlaying buffer.

## Set
Sets or unset a bit at the given position.

## Peek
Gets if a bit is set at a given position.

## IsValid
Check if the provided position results in a valid bit set.

