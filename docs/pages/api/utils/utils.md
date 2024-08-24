## IsStaticType
Checks if a given type is static

### Signature

```zig
pub inline fn isStaticType(comptime T: type) bool
```

## IsDynamicType
Checks if a given type is static

### Signature

```zig
pub inline fn isDynamicType(comptime T: type) bool
```

## ToChecksum
Converts ethereum address to checksum

### Signature

```zig
pub fn toChecksum(allocator: Allocator, address: []const u8) ![]u8
```

## IsAddress
Checks if the given address is a valid ethereum address.

### Signature

```zig
pub fn isAddress(addr: []const u8) bool
```

## AddressToBytes
Convert address to its representing bytes

### Signature

```zig
pub fn addressToBytes(address: []const u8) !Address
```

## HashToBytes
Convert a hash to its representing bytes

### Signature

```zig
pub fn hashToBytes(hash: []const u8) !Hash
```

## IsHexString
Checks if a given string is a hex string;

### Signature

```zig
pub fn isHexString(value: []const u8) bool
```

## IsHash
Checks if the given hash is a valid 32 bytes hash

### Signature

```zig
pub fn isHash(hash: []const u8) bool
```

## IsHashString
Check if a string is a hash string

### Signature

```zig
pub fn isHashString(hash: []const u8) bool
```

## ParseEth
Convert value into u256 representing ether value
Ex: 1 * 10 ** 18 = 1 ETH

### Signature

```zig
pub fn parseEth(value: usize) !u256
```

## ParseGwei
Convert value into u64 representing ether value
Ex: 1 * 10 ** 9 = 1 GWEI

### Signature

```zig
pub fn parseGwei(value: usize) !u64
```

## FormatInt
Finds the size of an int and writes to the buffer accordingly.

### Signature

```zig
pub inline fn formatInt(int: u256, buffer: *[32]u8) u8
```

## ComputeSize
Computes the size of a given int

### Signature

```zig
pub inline fn computeSize(int: u256) u8
```

## BytesToInt
Similar to `parseInt` but handles the hex bytes and not the
hex represented string.

### Signature

```zig
pub fn bytesToInt(comptime T: type, slice: []u8) !T
```

## CalcultateBlobGasPrice
Calcutates the blob gas price

### Signature

```zig
pub fn calcultateBlobGasPrice(excess_gas: u64) u128
```

## SaturatedAddition
Saturated addition. If it overflows it will return the max `T`

### Signature

```zig
pub fn saturatedAddition(comptime T: type, a: T, b: T) T
```

## SaturatedMultiplication
Saturated multiplication. If it overflows it will return the max `T`

### Signature

```zig
pub fn saturatedMultiplication(comptime T: type, a: T, b: T) T
```

