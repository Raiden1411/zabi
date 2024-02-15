# Encode

## AbiEncoded

Return type for abi encoding.

```zig
const AbiEncoded = struct {
    arena: *ArenaAllocator,
    data: []u8,

    pub fn deinit(self: @This()) void {...}
};
```

## AbiDecoded

Return type for abi parameter decoding 

```zig
fn AbiDecoded(comptime params: []const AbiParameter) type {
    return struct {
        arena: *ArenaAllocator,
        values: AbiParametersToPrimative(params),

        pub fn deinit(self: @This()) void {...}
    };
}
```

## AbiDecodedRuntime

Return type for abi decoding where the parameters are only runtime know.

```zig
fn AbiDecodedRuntime(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .Struct and !info.Struct.is_tuple)
        @compileError("Expected tuple return type");

    return struct {
        arena: *ArenaAllocator,
        values: T,

        pub fn deinit(self: @This()) void {...}
    };
}
```

## AbiSignatureDecoded

Return type for abi struct signatures decoding 

```zig
fn AbiSignatureDecoded(comptime params: []const AbiParameter) type {
    return struct {
        arena: *ArenaAllocator,
        name: []const u8,
        values: AbiParametersToPrimative(params),

        pub fn deinit(self: @This()) void {...}
    };
}
```

## AbiSignatureDecodedRuntime

Return type for abi decoding where the struct signatures are only runtime know.

```zig
fn AbiSignatureDecodedRuntime(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        name: []const u8,
        values: T,

        pub fn deinit(self: @This()) void {...}
    };
}
```

## DecodedOptions

Set of options that can be used to alter the decoding behaviour.

```zig
const DecodeOptions = struct {
    /// Max amount of bytes allowed to be read by the decoder.
    /// This avoid a DoS vulnerability discovered here:
    /// https://github.com/paulmillr/micro-eth-signer/discussions/20
    max_bytes: u16 = 1024,
    /// By default this is false.
    allow_junk_data: bool = false,
};
```
