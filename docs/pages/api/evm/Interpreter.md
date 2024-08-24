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

## InterpreterStatus

The status of execution for the interpreter.

```zig
enum {
    call_or_create,
    call_with_value_not_allowed_in_static_call,
    create_code_size_limit,
    invalid,
    invalid_jump,
    invalid_offset,
    opcode_not_found,
    returned,
    reverted,
    running,
    self_destructed,
    stopped,
}
```

## InterpreterInitOptions

Set of default options that the interperter needs
for it to be able to run.

### Properties

```zig
/// Maximum amount of gas available to perform the operations
gas_limit: u64 = 30_000_000
/// Tells the interperter if it's going to run as a static call
is_static: bool = false
/// Sets the interperter spec based on the hardforks.
spec_id: SpecId = .LATEST
```

## Init
Sets the interpreter to it's expected initial state.\
Copy's the contract's bytecode independent of it's state.

### Signature

```zig
pub fn init(self: *Interpreter, allocator: Allocator, contract_instance: Contract, evm_host: Host, opts: InterpreterInitOptions) !void
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

