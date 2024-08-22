## AnalyzeBytecode
Analyzes the raw bytecode into a `analyzed` state. If the provided
code is already analyzed then it will just return it.

## CreateJumpTable
Creates the jump table based on the provided bytecode. Assumes that
this was already padded in advance.

