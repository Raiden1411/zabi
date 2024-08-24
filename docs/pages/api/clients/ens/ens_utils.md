## ConvertToHash
Converts ens name to it's representing hash.\
Its it's a labelhash it will return the hash bytes.\
Make sure that the string is normalized beforehand.

### Signature

```zig
pub fn convertToHash(label: []const u8) !Hash
```

## IsLabelHash
Checks if a string is a ENS Label hash.

### Signature

```zig
pub fn isLabelHash(label: []const u8) bool
```

## HashName
Hashes the ENS name to it's ens label hash.\
Make sure that the string is normalized beforehand.

### Signature

```zig
pub fn hashName(name: []const u8) !Hash
```

## ConvertEnsToBytes
Converts the ENS names to a bytes representation
Make sure that the string is normalized beforehand.

### Signature

```zig
pub fn convertEnsToBytes(out: []u8, label: []const u8) usize
```

