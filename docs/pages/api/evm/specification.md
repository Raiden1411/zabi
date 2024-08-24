## SpecId

Specification IDs and their activation block.\
Information can be found here [Ethereum Execution Specification](https://github.com/ethereum/execution-specs)

## Enabled
Checks if a given specification id is enabled.

### Signature

```zig
pub fn enabled(self: SpecId, other: SpecId) bool
```

## ToSpecId
Converts an `u8` to a specId. Return error if the u8 is not valid.

### Signature

```zig
pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId
```

## OptimismSpecId

## Enabled
Checks if a given specification id is enabled.

### Signature

```zig
pub fn enabled(self: OptimismSpecId, other: OptimismSpecId) bool
```

## ToSpecId
Converts an `u8` to a specId. Return error if the u8 is not valid.

### Signature

```zig
pub fn toSpecId(num: u8) error{InvalidEnumTag}!SpecId
```

