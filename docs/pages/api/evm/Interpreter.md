## InterpreterActions

The set of next interpreter actions.

### Properties

```zig
/// Call action.
call_action: CallAction
/// Create action.
create_action: CreateAction
/// Return action.
return_action: ReturnAction
/// No action for the interpreter to take.
no_action
```

### Deinit
Clears any memory with the associated action.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

## Deinit
Clears any memory with the associated action.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

## InterpreterStatus

The status of execution for the interpreter.

## InterpreterInitOptions

Set of default options that the interperter needs
for it to be able to run.

## Init
Sets the interpreter to it's expected initial state.\
Copy's the contract's bytecode independent of it's state.

### Signature

```zig
pub fn init(self: *Interpreter, allocator: Allocator, contract_instance: Contract, evm_host: Host, opts: InterpreterInitOptions) !void
```

## Deinit
Clear memory and destroy's any created pointers.

### Signature

```zig
pub fn deinit(self: *Interpreter) void
```

## AdvanceProgramCounter
Moves the `program_counter` by one.

### Signature

```zig
pub fn advanceProgramCounter(self: *Interpreter) void
```

## RunInstruction
Runs a single instruction based on the `program_counter`
position and the associated bytecode. Doesn't move the counter.

### Signature

```zig
pub fn runInstruction(self: *Interpreter) !void
```

## Run
Runs the associated contract bytecode.\
Depending on the interperter final `status` this can return errors.\
The bytecode that will get run will be padded with `STOP` instructions
at the end to make sure that we don't have index out of bounds panics.

### Signature

```zig
pub fn run(self: *Interpreter) !InterpreterActions
```

## Resize
Resizes the inner memory size. Adds gas expansion cost to
the gas tracker.

### Signature

```zig
pub fn resize(self: *Interpreter, new_size: u64) !void
```

