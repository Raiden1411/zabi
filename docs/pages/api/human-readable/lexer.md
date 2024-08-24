## Lexer

Custom Solidity Lexer that is used to generate tokens based
on the provided solidity signature. This is not a fully
solidity compatable Lexer.

### Properties

```zig
struct {
  position: u32
  currentText: [:0]const u8
}
```

## Init
### Signature

```zig
pub fn init(text: [:0]const u8) Lexer
```

## Reset
### Signature

```zig
pub fn reset(self: *Lexer, newText: []const u8, pos: ?u32) void
```

## TokenSlice
### Signature

```zig
pub fn tokenSlice(self: *Lexer, start: usize, end: usize) []const u8
```

## Scan
### Signature

```zig
pub fn scan(self: *Lexer) Token
```

