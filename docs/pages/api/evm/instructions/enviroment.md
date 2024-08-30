## BaseFeeInstruction
Performs the basefee instruction for the interpreter.
0x48 -> BASEFEE

### Signature

```zig
pub fn baseFeeInstruction(self: *Interpreter) !void
```

## BlobBaseFeeInstruction
Performs the blobbasefee instruction for the interpreter.
0x4A -> BLOBBASEFEE

### Signature

```zig
pub fn blobBaseFeeInstruction(self: *Interpreter) !void
```

## BlobHashInstruction
Performs the blobhash instruction for the interpreter.
0x49 -> BLOBHASH

### Signature

```zig
pub fn blobHashInstruction(self: *Interpreter) !void
```

## BlockNumberInstruction
Performs the number instruction for the interpreter.
0x43 -> NUMBER

### Signature

```zig
pub fn blockNumberInstruction(self: *Interpreter) !void
```

## ChainIdInstruction
Performs the chainid instruction for the interpreter.
0x46 -> CHAINID

### Signature

```zig
pub fn chainIdInstruction(self: *Interpreter) !void
```

## CoinbaseInstruction
Performs the coinbase instruction for the interpreter.
0x41 -> COINBASE

### Signature

```zig
pub fn coinbaseInstruction(self: *Interpreter) !void
```

## DifficultyInstruction
Performs the prevrandao/difficulty instruction for the interpreter.
0x44 -> PREVRANDAO/DIFFICULTY

### Signature

```zig
pub fn difficultyInstruction(self: *Interpreter) !void
```

## GasLimitInstruction
Performs the gaslimit instruction for the interpreter.
0x45 -> GASLIMIT

### Signature

```zig
pub fn gasLimitInstruction(self: *Interpreter) !void
```

## GasPriceInstruction
Performs the gasprice instruction for the interpreter.
0x3A -> GASPRICE

### Signature

```zig
pub fn gasPriceInstruction(self: *Interpreter) !void
```

## OriginInstruction
Performs the origin instruction for the interpreter.
0x32 -> ORIGIN

### Signature

```zig
pub fn originInstruction(self: *Interpreter) !void
```

## TimestampInstruction
Performs the timestamp instruction for the interpreter.
0x42 -> TIMESTAMP

### Signature

```zig
pub fn timestampInstruction(self: *Interpreter) !void
```

