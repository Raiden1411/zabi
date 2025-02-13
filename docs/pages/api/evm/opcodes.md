## instruction_table

Comptime generated table from EVM instructions.

```zig
InstructionTable.generateTable(.{
    .STOP = .{ .execution = instructions.control.stopInstruction, .max_stack = maxStack(1024, 0, 0) },
    .ADD = .{ .execution = instructions.arithmetic.addInstruction, .max_stack = maxStack(1024, 2, 1) },
    .MUL = .{ .execution = instructions.arithmetic.mulInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SUB = .{ .execution = instructions.arithmetic.subInstruction, .max_stack = maxStack(1024, 2, 1) },
    .DIV = .{ .execution = instructions.arithmetic.divInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SDIV = .{ .execution = instructions.arithmetic.signedDivInstruction, .max_stack = maxStack(1024, 2, 1) },
    .MOD = .{ .execution = instructions.arithmetic.modInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SMOD = .{ .execution = instructions.arithmetic.signedModInstruction, .max_stack = maxStack(1024, 2, 1) },
    .ADDMOD = .{ .execution = instructions.arithmetic.modAdditionInstruction, .max_stack = maxStack(1024, 3, 1) },
    .MULMOD = .{ .execution = instructions.arithmetic.modMultiplicationInstruction, .max_stack = maxStack(1024, 3, 1) },
    .EXP = .{ .execution = instructions.arithmetic.exponentInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SIGNEXTEND = .{ .execution = instructions.arithmetic.signExtendInstruction, .max_stack = maxStack(1024, 2, 1) },
    .LT = .{ .execution = instructions.bitwise.lowerThanInstruction, .max_stack = maxStack(1024, 2, 1) },
    .GT = .{ .execution = instructions.bitwise.greaterThanInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SLT = .{ .execution = instructions.bitwise.signedLowerThanInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SGT = .{ .execution = instructions.bitwise.signedGreaterThanInstruction, .max_stack = maxStack(1024, 2, 1) },
    .EQ = .{ .execution = instructions.bitwise.equalInstruction, .max_stack = maxStack(1024, 2, 1) },
    .ISZERO = .{ .execution = instructions.bitwise.isZeroInstruction, .max_stack = maxStack(1024, 2, 1) },
    .AND = .{ .execution = instructions.bitwise.andInstruction, .max_stack = maxStack(1024, 2, 1) },
    .OR = .{ .execution = instructions.bitwise.orInstruction, .max_stack = maxStack(1024, 2, 1) },
    .XOR = .{ .execution = instructions.bitwise.xorInstruction, .max_stack = maxStack(1024, 2, 1) },
    .NOT = .{ .execution = instructions.bitwise.notInstruction, .max_stack = maxStack(1024, 2, 1) },
    .BYTE = .{ .execution = instructions.bitwise.byteInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SHL = .{ .execution = instructions.bitwise.shiftLeftInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SHR = .{ .execution = instructions.bitwise.shiftRightInstruction, .max_stack = maxStack(1024, 2, 1) },
    .SAR = .{ .execution = instructions.bitwise.signedShiftRightInstruction, .max_stack = maxStack(1024, 2, 1) },
    .KECCAK256 = .{ .execution = instructions.system.keccakInstruction, .max_stack = maxStack(1024, 2, 1) },
    .ADDRESS = .{ .execution = instructions.system.addressInstruction, .max_stack = maxStack(1024, 0, 1) },
    .BALANCE = .{ .execution = instructions.host.balanceInstruction, .max_stack = maxStack(1024, 1, 1) },
    .ORIGIN = .{ .execution = instructions.enviroment.originInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CALLER = .{ .execution = instructions.system.callerInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CALLVALUE = .{ .execution = instructions.system.callValueInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CALLDATALOAD = .{ .execution = instructions.system.callDataLoadInstruction, .max_stack = maxStack(1024, 1, 1) },
    .CALLDATASIZE = .{ .execution = instructions.system.callDataSizeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CALLDATACOPY = .{ .execution = instructions.system.callDataCopyInstruction, .max_stack = maxStack(1024, 3, 0) },
    .CODESIZE = .{ .execution = instructions.system.codeSizeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CODECOPY = .{ .execution = instructions.system.codeCopyInstruction, .max_stack = maxStack(1024, 3, 0) },
    .GASPRICE = .{ .execution = instructions.enviroment.gasPriceInstruction, .max_stack = maxStack(1024, 0, 1) },
    .EXTCODESIZE = .{ .execution = instructions.host.extCodeSizeInstruction, .max_stack = maxStack(1024, 1, 1) },
    .EXTCODECOPY = .{ .execution = instructions.host.extCodeSizeInstruction, .max_stack = maxStack(1024, 4, 0) },
    .RETURNDATASIZE = .{ .execution = instructions.system.returnDataSizeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .RETURNDATACOPY = .{ .execution = instructions.system.returnDataCopyInstruction, .max_stack = maxStack(1024, 3, 0) },
    .EXTCODEHASH = .{ .execution = instructions.host.extCodeHashInstruction, .max_stack = maxStack(1024, 1, 1) },
    .BLOCKHASH = .{ .execution = instructions.host.blockHashInstruction, .max_stack = maxStack(1024, 1, 1) },
    .COINBASE = .{ .execution = instructions.enviroment.coinbaseInstruction, .max_stack = maxStack(1024, 0, 1) },
    .TIMESTAMP = .{ .execution = instructions.enviroment.timestampInstruction, .max_stack = maxStack(1024, 0, 1) },
    .NUMBER = .{ .execution = instructions.enviroment.blockNumberInstruction, .max_stack = maxStack(1024, 0, 1) },
    .PREVRANDAO = .{ .execution = instructions.enviroment.difficultyInstruction, .max_stack = maxStack(1024, 0, 1) },
    .GASLIMIT = .{ .execution = instructions.enviroment.gasLimitInstruction, .max_stack = maxStack(1024, 0, 1) },
    .CHAINID = .{ .execution = instructions.enviroment.chainIdInstruction, .max_stack = maxStack(1024, 0, 1) },
    .SELFBALANCE = .{ .execution = instructions.host.selfBalanceInstruction, .max_stack = maxStack(1024, 0, 1) },
    .BASEFEE = .{ .execution = instructions.enviroment.baseFeeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .BLOBHASH = .{ .execution = instructions.enviroment.blobHashInstruction, .max_stack = maxStack(1024, 1, 1) },
    .BLOBBASEFEE = .{ .execution = instructions.enviroment.blobBaseFeeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .POP = .{ .execution = instructions.stack.popInstruction, .max_stack = maxStack(1024, 1, 0) },
    .MLOAD = .{ .execution = instructions.memory.mloadInstruction, .max_stack = maxStack(1024, 1, 1) },
    .MSTORE = .{ .execution = instructions.memory.mstoreInstruction, .max_stack = maxStack(1024, 2, 0) },
    .MSTORE8 = .{ .execution = instructions.memory.mstore8Instruction, .max_stack = maxStack(1024, 2, 0) },
    .SLOAD = .{ .execution = instructions.host.sloadInstruction, .max_stack = maxStack(1024, 1, 1) },
    .SSTORE = .{ .execution = instructions.host.sstoreInstruction, .max_stack = maxStack(1024, 2, 0) },
    .JUMP = .{ .execution = instructions.control.jumpInstruction, .max_stack = maxStack(1024, 1, 0) },
    .JUMPI = .{ .execution = instructions.control.conditionalJumpInstruction, .max_stack = maxStack(1024, 2, 0) },
    .PC = .{ .execution = instructions.control.programCounterInstruction, .max_stack = maxStack(1024, 0, 1) },
    .MSIZE = .{ .execution = instructions.memory.msizeInstruction, .max_stack = maxStack(1024, 0, 1) },
    .GAS = .{ .execution = instructions.system.gasInstruction, .max_stack = maxStack(1024, 0, 1) },
    .JUMPDEST = .{ .execution = instructions.control.jumpDestInstruction, .max_stack = maxStack(1024, 0, 0) },
    .TLOAD = .{ .execution = instructions.host.tloadInstruction, .max_stack = maxStack(1024, 1, 1) },
    .TSTORE = .{ .execution = instructions.host.tstoreInstruction, .max_stack = maxStack(1024, 2, 0) },
    .MCOPY = .{ .execution = instructions.memory.mcopyInstruction, .max_stack = maxStack(1024, 3, 0) },
    .PUSH0 = .{ .execution = instructions.stack.pushZeroInstruction, .max_stack = maxStack(1024, 0, 1) },
    .PUSH1 = .{ .execution = makePushInstruction(1), .max_stack = maxStack(1024, 0, 1) },
    .PUSH2 = .{ .execution = makePushInstruction(2), .max_stack = maxStack(1024, 0, 1) },
    .PUSH3 = .{ .execution = makePushInstruction(3), .max_stack = maxStack(1024, 0, 1) },
    .PUSH4 = .{ .execution = makePushInstruction(4), .max_stack = maxStack(1024, 0, 1) },
    .PUSH5 = .{ .execution = makePushInstruction(5), .max_stack = maxStack(1024, 0, 1) },
    .PUSH6 = .{ .execution = makePushInstruction(6), .max_stack = maxStack(1024, 0, 1) },
    .PUSH7 = .{ .execution = makePushInstruction(7), .max_stack = maxStack(1024, 0, 1) },
    .PUSH8 = .{ .execution = makePushInstruction(8), .max_stack = maxStack(1024, 0, 1) },
    .PUSH9 = .{ .execution = makePushInstruction(9), .max_stack = maxStack(1024, 0, 1) },
    .PUSH10 = .{ .execution = makePushInstruction(10), .max_stack = maxStack(1024, 0, 1) },
    .PUSH11 = .{ .execution = makePushInstruction(11), .max_stack = maxStack(1024, 0, 1) },
    .PUSH12 = .{ .execution = makePushInstruction(12), .max_stack = maxStack(1024, 0, 1) },
    .PUSH13 = .{ .execution = makePushInstruction(13), .max_stack = maxStack(1024, 0, 1) },
    .PUSH14 = .{ .execution = makePushInstruction(14), .max_stack = maxStack(1024, 0, 1) },
    .PUSH15 = .{ .execution = makePushInstruction(15), .max_stack = maxStack(1024, 0, 1) },
    .PUSH16 = .{ .execution = makePushInstruction(16), .max_stack = maxStack(1024, 0, 1) },
    .PUSH17 = .{ .execution = makePushInstruction(17), .max_stack = maxStack(1024, 0, 1) },
    .PUSH18 = .{ .execution = makePushInstruction(18), .max_stack = maxStack(1024, 0, 1) },
    .PUSH19 = .{ .execution = makePushInstruction(19), .max_stack = maxStack(1024, 0, 1) },
    .PUSH20 = .{ .execution = makePushInstruction(20), .max_stack = maxStack(1024, 0, 1) },
    .PUSH21 = .{ .execution = makePushInstruction(21), .max_stack = maxStack(1024, 0, 1) },
    .PUSH22 = .{ .execution = makePushInstruction(22), .max_stack = maxStack(1024, 0, 1) },
    .PUSH23 = .{ .execution = makePushInstruction(23), .max_stack = maxStack(1024, 0, 1) },
    .PUSH24 = .{ .execution = makePushInstruction(24), .max_stack = maxStack(1024, 0, 1) },
    .PUSH25 = .{ .execution = makePushInstruction(25), .max_stack = maxStack(1024, 0, 1) },
    .PUSH26 = .{ .execution = makePushInstruction(26), .max_stack = maxStack(1024, 0, 1) },
    .PUSH27 = .{ .execution = makePushInstruction(27), .max_stack = maxStack(1024, 0, 1) },
    .PUSH28 = .{ .execution = makePushInstruction(28), .max_stack = maxStack(1024, 0, 1) },
    .PUSH29 = .{ .execution = makePushInstruction(29), .max_stack = maxStack(1024, 0, 1) },
    .PUSH30 = .{ .execution = makePushInstruction(30), .max_stack = maxStack(1024, 0, 1) },
    .PUSH31 = .{ .execution = makePushInstruction(31), .max_stack = maxStack(1024, 0, 1) },
    .PUSH32 = .{ .execution = makePushInstruction(32), .max_stack = maxStack(1024, 0, 1) },
    .DUP1 = .{ .execution = makeDupInstruction(1), .max_stack = maxStack(1024, 1, 2) },
    .DUP2 = .{ .execution = makeDupInstruction(2), .max_stack = maxStack(1024, 2, 3) },
    .DUP3 = .{ .execution = makeDupInstruction(3), .max_stack = maxStack(1024, 3, 4) },
    .DUP4 = .{ .execution = makeDupInstruction(4), .max_stack = maxStack(1024, 4, 5) },
    .DUP5 = .{ .execution = makeDupInstruction(5), .max_stack = maxStack(1024, 5, 6) },
    .DUP6 = .{ .execution = makeDupInstruction(6), .max_stack = maxStack(1024, 6, 7) },
    .DUP7 = .{ .execution = makeDupInstruction(7), .max_stack = maxStack(1024, 7, 8) },
    .DUP8 = .{ .execution = makeDupInstruction(8), .max_stack = maxStack(1024, 8, 9) },
    .DUP9 = .{ .execution = makeDupInstruction(9), .max_stack = maxStack(1024, 10, 10) },
    .DUP10 = .{ .execution = makeDupInstruction(10), .max_stack = maxStack(1024, 10, 11) },
    .DUP11 = .{ .execution = makeDupInstruction(11), .max_stack = maxStack(1024, 11, 12) },
    .DUP12 = .{ .execution = makeDupInstruction(12), .max_stack = maxStack(1024, 12, 13) },
    .DUP13 = .{ .execution = makeDupInstruction(13), .max_stack = maxStack(1024, 13, 14) },
    .DUP14 = .{ .execution = makeDupInstruction(14), .max_stack = maxStack(1024, 14, 15) },
    .DUP15 = .{ .execution = makeDupInstruction(15), .max_stack = maxStack(1024, 15, 16) },
    .DUP16 = .{ .execution = makeDupInstruction(16), .max_stack = maxStack(1024, 16, 17) },
    .SWAP1 = .{ .execution = makeSwapInstruction(1), .max_stack = maxStack(1024, 2, 2) },
    .SWAP2 = .{ .execution = makeSwapInstruction(2), .max_stack = maxStack(1024, 3, 3) },
    .SWAP3 = .{ .execution = makeSwapInstruction(3), .max_stack = maxStack(1024, 4, 4) },
    .SWAP4 = .{ .execution = makeSwapInstruction(4), .max_stack = maxStack(1024, 5, 5) },
    .SWAP5 = .{ .execution = makeSwapInstruction(5), .max_stack = maxStack(1024, 6, 6) },
    .SWAP6 = .{ .execution = makeSwapInstruction(6), .max_stack = maxStack(1024, 7, 7) },
    .SWAP7 = .{ .execution = makeSwapInstruction(7), .max_stack = maxStack(1024, 8, 8) },
    .SWAP8 = .{ .execution = makeSwapInstruction(8), .max_stack = maxStack(1024, 9, 9) },
    .SWAP9 = .{ .execution = makeSwapInstruction(9), .max_stack = maxStack(1024, 10, 10) },
    .SWAP10 = .{ .execution = makeSwapInstruction(10), .max_stack = maxStack(1024, 11, 11) },
    .SWAP11 = .{ .execution = makeSwapInstruction(11), .max_stack = maxStack(1024, 12, 12) },
    .SWAP12 = .{ .execution = makeSwapInstruction(12), .max_stack = maxStack(1024, 13, 13) },
    .SWAP13 = .{ .execution = makeSwapInstruction(13), .max_stack = maxStack(1024, 14, 14) },
    .SWAP14 = .{ .execution = makeSwapInstruction(14), .max_stack = maxStack(1024, 15, 15) },
    .SWAP15 = .{ .execution = makeSwapInstruction(15), .max_stack = maxStack(1024, 16, 16) },
    .SWAP16 = .{ .execution = makeSwapInstruction(16), .max_stack = maxStack(1024, 17, 17) },
    .LOG0 = .{ .execution = makeLogInstruction(0), .max_stack = maxStack(1024, 2, 0) },
    .LOG1 = .{ .execution = makeLogInstruction(1), .max_stack = maxStack(1024, 3, 0) },
    .LOG2 = .{ .execution = makeLogInstruction(2), .max_stack = maxStack(1024, 4, 0) },
    .LOG3 = .{ .execution = makeLogInstruction(3), .max_stack = maxStack(1024, 5, 0) },
    .LOG4 = .{ .execution = makeLogInstruction(4), .max_stack = maxStack(1024, 6, 0) },
    .CREATE = .{ .execution = makeCreateInstruction(false), .max_stack = maxStack(1024, 3, 1) },
    .CALL = .{ .execution = instructions.contract.callInstruction, .max_stack = maxStack(1024, 7, 1) },
    .CALLCODE = .{ .execution = instructions.contract.callCodeInstruction, .max_stack = maxStack(1024, 7, 1) },
    .RETURN = .{ .execution = instructions.control.returnInstruction, .max_stack = maxStack(1024, 2, 0) },
    .DELEGATECALL = .{ .execution = instructions.contract.delegateCallInstruction, .max_stack = maxStack(1024, 6, 1) },
    .CREATE2 = .{ .execution = makeCreateInstruction(true), .max_stack = maxStack(1024, 6, 0) },
    .STATICCALL = .{ .execution = instructions.contract.staticCallInstruction, .max_stack = maxStack(1024, 6, 1) },
    .REVERT = .{ .execution = instructions.control.revertInstruction, .max_stack = maxStack(1024, 2, 0) },
    .INVALID = .{ .execution = instructions.control.invalidInstruction, .max_stack = maxStack(1024, 0, 0) },
    .SELFDESTRUCT = .{ .execution = instructions.host.selfDestructInstruction, .max_stack = maxStack(1024, 1, 0) },
})
```

## Opcodes

EVM Opcodes.

### Properties

```zig
enum {
  STOP = 0x00
  ADD = 0x01
  MUL = 0x02
  SUB = 0x03
  DIV = 0x04
  SDIV = 0x05
  MOD = 0x06
  SMOD = 0x07
  ADDMOD = 0x08
  MULMOD = 0x09
  EXP = 0x0a
  SIGNEXTEND = 0x0b
  LT = 0x10
  GT = 0x11
  SLT = 0x12
  SGT = 0x13
  EQ = 0x14
  ISZERO = 0x15
  AND = 0x16
  OR = 0x17
  XOR = 0x18
  NOT = 0x19
  BYTE = 0x1a
  SHL = 0x1b
  SHR = 0x1c
  SAR = 0x1d
  KECCAK256 = 0x20
  ADDRESS = 0x30
  BALANCE = 0x31
  ORIGIN = 0x32
  CALLER = 0x33
  CALLVALUE = 0x34
  CALLDATALOAD = 0x35
  CALLDATASIZE = 0x36
  CALLDATACOPY = 0x37
  CODESIZE = 0x38
  CODECOPY = 0x39
  GASPRICE = 0x3a
  EXTCODESIZE = 0x3b
  EXTCODECOPY = 0x3c
  RETURNDATASIZE = 0x3d
  RETURNDATACOPY = 0x3e
  EXTCODEHASH = 0x3f
  BLOCKHASH = 0x40
  COINBASE = 0x41
  TIMESTAMP = 0x42
  NUMBER = 0x43
  PREVRANDAO = 0x44
  GASLIMIT = 0x45
  CHAINID = 0x46
  SELFBALANCE = 0x47
  BASEFEE = 0x48
  BLOBHASH = 0x49
  BLOBBASEFEE = 0x4a
  POP = 0x50
  MLOAD = 0x51
  MSTORE = 0x52
  MSTORE8 = 0x53
  SLOAD = 0x54
  SSTORE = 0x55
  JUMP = 0x56
  JUMPI = 0x57
  PC = 0x58
  MSIZE = 0x59
  GAS = 0x5a
  JUMPDEST = 0x5b
  TLOAD = 0x5c
  TSTORE = 0x5d
  MCOPY = 0x5e
  PUSH0 = 0x5f
  PUSH1 = 0x60
  PUSH2 = 0x61
  PUSH3 = 0x62
  PUSH4 = 0x63
  PUSH5 = 0x64
  PUSH6 = 0x65
  PUSH7 = 0x66
  PUSH8 = 0x67
  PUSH9 = 0x68
  PUSH10 = 0x69
  PUSH11 = 0x6a
  PUSH12 = 0x6b
  PUSH13 = 0x6c
  PUSH14 = 0x6d
  PUSH15 = 0x6e
  PUSH16 = 0x6f
  PUSH17 = 0x70
  PUSH18 = 0x71
  PUSH19 = 0x72
  PUSH20 = 0x73
  PUSH21 = 0x74
  PUSH22 = 0x75
  PUSH23 = 0x76
  PUSH24 = 0x77
  PUSH25 = 0x78
  PUSH26 = 0x79
  PUSH27 = 0x7a
  PUSH28 = 0x7b
  PUSH29 = 0x7c
  PUSH30 = 0x7d
  PUSH31 = 0x7e
  PUSH32 = 0x7f
  DUP1 = 0x80
  DUP2 = 0x81
  DUP3 = 0x82
  DUP4 = 0x83
  DUP5 = 0x84
  DUP6 = 0x85
  DUP7 = 0x86
  DUP8 = 0x87
  DUP9 = 0x88
  DUP10 = 0x89
  DUP11 = 0x8a
  DUP12 = 0x8b
  DUP13 = 0x8c
  DUP14 = 0x8d
  DUP15 = 0x8e
  DUP16 = 0x8f
  SWAP1 = 0x90
  SWAP2 = 0x91
  SWAP3 = 0x92
  SWAP4 = 0x93
  SWAP5 = 0x94
  SWAP6 = 0x95
  SWAP7 = 0x96
  SWAP8 = 0x97
  SWAP9 = 0x98
  SWAP10 = 0x99
  SWAP11 = 0x9a
  SWAP12 = 0x9b
  SWAP13 = 0x9c
  SWAP14 = 0x9d
  SWAP15 = 0x9e
  SWAP16 = 0x9f
  LOG0 = 0xa0
  LOG1 = 0xa1
  LOG2 = 0xa2
  LOG3 = 0xa3
  LOG4 = 0xa4
  CREATE = 0xf0
  CALL = 0xf1
  CALLCODE = 0xf2
  RETURN = 0xf3
  DELEGATECALL = 0xf4
  CREATE2 = 0xf5
  STATICCALL = 0xfa
  REVERT = 0xfd
  INVALID = 0xfe
  SELFDESTRUCT = 0xff
}
```

### ToOpcode
Converts `u8` to associated opcode.
Will return null for unknown opcodes

### Signature

```zig
pub fn toOpcode(num: u8) ?Opcodes
```

## InstructionTable

EVM instruction table.

### Properties

```zig
struct {
  /// Array of instructions.
  inner: [256]Operations
}
```

### GenerateTable
Generates the instruction opcode table.
This is a similar implementation to `std.enums.directEnumArray`

### Signature

```zig
pub fn generateTable(fields: EnumFieldStruct(Opcodes, Operations, null)) InstructionTable
```

### GetInstruction
Gets the associated operation for the provided opcode.

### Signature

```zig
pub fn getInstruction(self: @This(), opcode: u8) Operations
```

## Operations

Opcode operations and checks.

### Properties

```zig
struct {
  /// The execution function attached to the opcode.
  execution: *const fn (ctx: *Interpreter) anyerror!void
  /// The max allowed size of the stack
  max_stack: usize
}
```

## MakeDupInstruction
Creates the dup instructions for the instruction table.

### Signature

```zig
pub fn makeDupInstruction(comptime dup_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Dup
### Signature

```zig
pub fn dup(self: *Interpreter) anyerror!void
```

## MakePushInstruction
Creates the push instructions for the instruction table.

### Signature

```zig
pub fn makePushInstruction(comptime push_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Push
### Signature

```zig
pub fn push(self: *Interpreter) anyerror!void
```

## MakeSwapInstruction
Creates the swap instructions for the instruction table.

### Signature

```zig
pub fn makeSwapInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Swap
### Signature

```zig
pub fn swap(self: *Interpreter) anyerror!void
```

## MakeLogInstruction
Creates the log instructions for the instruction table.

### Signature

```zig
pub fn makeLogInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Log
### Signature

```zig
pub fn log(self: *Interpreter) anyerror!void
```

## MakeCreateInstruction
Creates the log instructions for the instruction table.

### Signature

```zig
pub fn makeCreateInstruction(comptime is_create2: bool) *const fn (ctx: *Interpreter) anyerror!void
```

## Log
### Signature

```zig
pub fn log(self: *Interpreter) anyerror!void
```

## MaxStack
Callculates the max avaliable size of the stack for the operation to execute.

### Signature

```zig
pub fn maxStack(
    comptime limit: comptime_int,
    comptime pop: comptime_int,
    comptime push: comptime_int,
) usize
```

