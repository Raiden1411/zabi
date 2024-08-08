# Decode

## AbiDecoded

Return type for abi parameter decoding 

```zig
fn AbiDecoded(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        values: T,

        pub fn deinit(self: @This()) void {...}
    };
}
```

## DecodedOptions

Set of options that can be used to alter the decoding behaviour.

```zig
pub const DecodeOptions = struct {
    /// Max amount of bytes allowed to be read by the decoder.
    /// This avoid a DoS vulnerability discovered here:
    /// https://github.com/paulmillr/micro-eth-signer/discussions/20
    max_bytes: u16 = 1024,
    /// By default this is false.
    allow_junk_data: bool = false,
    /// Tell the decoder if an allocation should be made.
    /// Allocations are always made if dealing with a type that will require a list i.e `[]const u64`.
    allocate_when: enum { alloc_always, alloc_if_needed } = .alloc_if_needed,
    /// Tells the endianess of the bytes that you want to decode
    /// Addresses are encoded in big endian and bytes1..32 are encoded in little endian.
    /// There might be some cases where you will need to decode a bytes20 and address at the same time.
    /// Since they can represent the same type it's advised to decode the address as `u160` and change this value to `little`.
    /// since it already decodes as big-endian and then `std.mem.writeInt` the value to the expected endianess.
    bytes_endian: Endian = .big,
};
```

## LogDecoderOptions

Set of options that can be used to alter the decoding behaviour.

```zig
pub const LogDecoderOptions = struct {
    /// Optional allocation in the case that you want to create a pointer
    /// That pointer must be destroyed later.
    allocator: ?Allocator = null,
    /// Tells the endianess of the bytes that you want to decode
    /// Addresses are encoded in big endian and bytes1..32 are encoded in little endian.
    /// There might be some cases where you will need to decode a bytes20 and address at the same time.
    /// Since they can represent the same type it's advised to decode the address as `u160` and change this value to `little`.
    /// since it already decodes as big-endian and then `std.mem.writeInt` the value to the expected endianess.
    bytes_endian: Endian = .big,
};
```
