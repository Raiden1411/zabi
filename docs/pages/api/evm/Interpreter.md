## InterpreterActions
The set of next interpreter actions.

## Deinit
Clears any memory with the associated action.

## InterpreterStatus
The status of execution for the interpreter.

## InterpreterInitOptions
Set of default options that the interperter needs
for it to be able to run.

## Init
Sets the interpreter to it's expected initial state.\
Copy's the contract's bytecode independent of it's state.

## Deinit
Clear memory and destroy's any created pointers.

## AdvanceProgramCounter
Moves the `program_counter` by one.

## RunInstruction
Runs a single instruction based on the `program_counter`
position and the associated bytecode. Doesn't move the counter.

## Run
Runs the associated contract bytecode.\
Depending on the interperter final `status` this can return errors.\
The bytecode that will get run will be padded with `STOP` instructions
at the end to make sure that we don't have index out of bounds panics.

## Resize
Resizes the inner memory size. Adds gas expansion cost to
the gas tracker.

