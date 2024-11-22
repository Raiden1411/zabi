const std = @import("std");
const abi = zabi_abi.abi_parameter;
const meta = @import("zabi-meta").abi;
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;
const zabi_abi = @import("zabi-abi");

const assert = std.debug.assert;

/// Types
const AbiParameter = abi.AbiParameter;
const AbiParameterToPrimative = meta.AbiParameterToPrimative;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const ArrayList = std.ArrayList;
const ByteAlignedInt = std.math.ByteAlignedInt;
const Constructor = zabi_abi.abitypes.Constructor;
const Error = zabi_abi.abitypes.Error;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Function = zabi_abi.abitypes.Function;
const ParamType = zabi_abi.param_type.ParamType;

/// Set of errors while perfoming abi encoding.
pub const EncodeErrors = Allocator.Error || error{NoSpaceLeft};

/// Runtime value representation for abi encoding.
pub const AbiEncodedValues = union(enum) {
    bool: bool,
    uint: u256,
    int: i256,
    address: Address,
    fixed_bytes: []u8,
    string: []const u8,
    bytes: []const u8,
    fixed_array: []const AbiEncodedValues,
    dynamic_array: []const AbiEncodedValues,
    tuple: []const AbiEncodedValues,

    /// Checks if the given values is a dynamic abi value.
    pub fn isDynamic(self: @This()) bool {
        switch (self) {
            .bool,
            .uint,
            .int,
            .address,
            .fixed_bytes,
            => return false,
            .string,
            .bytes,
            .dynamic_array,
            => return true,
            .fixed_array,
            => |values| return values[0].isDynamic(),
            .tuple,
            => |values| for (values) |value| {
                if (value.isDynamic())
                    return true;
            } else return false,
        }
    }
};

// The possible value types.
const ParameterType = enum {
    dynamic,
    static,
};

/// The encoded values inner structure representation.
pub const PreEncodedStructure = struct {
    type: ParameterType,
    encoded: []const u8,

    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.encoded);
    }
};

/// Encode an Solidity `Function` type with the signature and the values encoded.
/// The signature is calculated by hashing the formated string generated from the `Function` signature.
pub fn encodeAbiFunction(
    comptime func: Function,
    allocator: Allocator,
    values: AbiParametersToPrimative(func.inputs),
) EncodeErrors![]u8 {
    var buffer: [256]u8 = undefined;

    var stream = std.io.fixedBufferStream(&buffer);
    try func.prepare(stream.writer());

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(stream.getWritten(), &hashed, .{});

    var encoder: AbiEncoder = .empty;

    try encoder.preEncodeAbiParameters(func.inputs, allocator, values);
    try encoder.heads.appendSlice(allocator, hashed[0..4]);

    return encoder.encodePointers(allocator);
}
/// Encode an Solidity `Function` type with the signature and the values encoded.
/// This is will use the `func` outputs values as the parameters.
pub fn encodeAbiFunctionOutputs(
    comptime func: Function,
    allocator: Allocator,
    values: AbiParametersToPrimative(func.outputs),
) Allocator.Error![]u8 {
    return encodeAbiParameters(func.outputs, allocator, values);
}
/// Encode an Solidity `Error` type with the signature and the values encoded.
/// The signature is calculated by hashing the formated string generated from the `Error` signature.
pub fn encodeAbiError(
    comptime err: Error,
    allocator: Allocator,
    values: AbiParametersToPrimative(err.inputs),
) EncodeErrors![]u8 {
    var buffer: [256]u8 = undefined;

    var stream = std.io.fixedBufferStream(&buffer);
    try err.prepare(stream.writer());

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(stream.getWritten(), &hashed, .{});

    var encoder: AbiEncoder = .empty;

    try encoder.preEncodeAbiParameters(err.inputs, allocator, values);
    try encoder.heads.appendSlice(allocator, hashed[0..4]);

    return encoder.encodePointers(allocator);
}
/// Encode an Solidity `Constructor` type with the signature and the values encoded.
pub fn encodeAbiConstructor(
    comptime constructor: Constructor,
    allocator: Allocator,
    values: AbiParametersToPrimative(constructor.inputs),
) Allocator.Error![]u8 {
    return encodeAbiParameters(constructor.inputs, allocator, values);
}
/// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
///
/// The values types are checked at comptime based on the provided `params`.
pub fn encodeAbiParameters(
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) Allocator.Error![]u8 {
    var encoder: AbiEncoder = .empty;
    try encoder.preEncodeAbiParameters(params, allocator, values);

    return encoder.encodePointers(allocator);
}
/// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
///
/// Use this if for some reason you don't know the `Abi` at comptime.
///
/// It's recommended to use `encodeAbiParameters` whenever possible but this is provided as a fallback
/// you cannot use it.
pub fn encodeAbiParametersValues(
    allocator: Allocator,
    values: []const AbiEncodedValues,
) (Allocator.Error || error{InvalidType})![]u8 {
    var encoder: AbiEncoder = .empty;
    try encoder.preEncodeRuntimeValues(allocator, values);

    return encoder.encodePointers(allocator);
}
/// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
///
/// This will use zig's ability to provide compile time reflection based on the `values` provided.
/// The `values` must be a tuple struct. Otherwise it will trigger a compile error.
///
/// By default this provides more support for a greater range on zig types that can be used for encoding.
/// Bellow you will find the list of all supported types and what will they be encoded as.
///
///   * Zig `bool` -> Will be encoded like a boolean value
///   * Zig `?T` -> Only encodes if the value is not null.
///   * Zig `int`, `comptime_int` -> Will be encoded based on the signedness of the integer.
///   * Zig `[N]u8` -> Only support max size of 32. `[20]u8` will be encoded as address types and all other as bytes1..32.
///                    This is the main limitation because abi encoding of bytes1..32 follows little endian and for address follows big endian.
///   * Zig `enum` -> The tagname of the enum encoded as a string/bytes value.
///   * Zig `*T` -> will encoded the child type. If the child type is an `array` it will encode as string/bytes.
///   * Zig `[]const u8`, `[]u8` -> Will encode according the string/bytes specification.
///   * Zig `[]const T` -> Will encode as a dynamic array
///   * Zig `[N]T` -> Will encode as a dynamic value if the child type is of a dynamic type.
///   * Zig `struct` -> Will encode as a dynamic value if the child type is of a dynamic type.
///
/// All other types are currently not supported.
pub fn encodeAbiParametersFromReflection(
    allocator: Allocator,
    values: anytype,
) Allocator.Error![]u8 {
    var encoder: AbiEncoder = .empty;
    try encoder.preEncodeValuesFromReflection(allocator, values);

    return encoder.encodePointers(allocator);
}
/// Encode values based on solidity's `encodePacked`.
/// Solidity types are infered from zig ones since it closely follows them.
///
/// Supported zig types:
///
///   * Zig `bool` -> Will be encoded like a boolean value
///   * Zig `?T` -> Only encodes if the value is not null.
///   * Zig `int`, `comptime_int` -> Will be encoded based on the signedness of the integer.
///   * Zig `[N]u8` -> Only support max size of 32. `[20]u8` will be encoded as address types and all other as bytes1..32.
///                    This is the main limitation because abi encoding of bytes1..32 follows little endian and for address follows big endian.
///   * Zig `enum`, `enum_literal`, `error_set` -> The tagname of the enum or the error_set names will be encoded as a string/bytes value.
///   * Zig `*T` -> will encoded the child type. If the child type is an `array` it will encode as string/bytes.
///   * Zig `[]const u8`, `[]u8` -> Will encode according the string/bytes specification.
///   * Zig `[]const T` -> Will encode as a dynamic array
///   * Zig `[N]T` -> Will encode as a dynamic value if the child type is of a dynamic type.
///   * Zig `struct` -> Will encode as a dynamic value if the child type is of a dynamic type.
///
/// All other types are currently not supported.
///
/// If the value provided is either a `[]const T`, `[N]T`, `[]T`, or `tuple`,
/// the child values will be 32 bit padded.
pub fn encodePacked(
    allocator: Allocator,
    value: anytype,
) Allocator.Error![]u8 {
    var encoder: EncodePacked = .init(allocator, .static);
    errdefer encoder.list.deinit();

    return encoder.encodePacked(value);
}

/// The abi encoding structure used to encoded values with the abi encoding [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
///
/// You can initialize this structure like this:
/// ```zig
/// var encoder: AbiEncoder = .empty;
///
/// try encoder.encodeAbiParameters(params, allocator, .{69, 420});
/// defer allocator.free(allocator);
/// ```
pub const AbiEncoder = struct {
    pub const Self = @This();

    /// Sets the initial state of the encoder.
    pub const empty: Self = .{
        .pre_encoded = .empty,
        .heads = .empty,
        .tails = .empty,
        .heads_size = 0,
        .tails_size = 0,
    };

    /// Essentially a `stack` of encoded values that will need to be analysed
    /// in the `encodePointers` step to re-arrange the location in the encoded slice based on
    /// if they are dynamic or static types.
    pre_encoded: ArrayListUnmanaged(PreEncodedStructure),
    /// Stream of encoded values that should show up at the top of the encoded slice.
    heads: ArrayListUnmanaged(u8),
    /// Stream of encoded values that should show up at the end of the encoded slice.
    tails: ArrayListUnmanaged(u8),
    /// Used to calculated the initial pointer when facing `dynamic` types.
    /// Also used to know the memory size of the `heads` stream.
    heads_size: u32,
    /// Only used to know the memory size of the `tails` stream.
    tails_size: u32,

    /// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
    ///
    /// Uses compile time reflection to determine the behaviour. Please check `encodeAbiParametersFromReflection` for more details.
    pub fn encodeAbiParametersFromReflection(
        self: *Self,
        allocator: Allocator,
        values: anytype,
    ) Allocator.Error![]u8 {
        try self.preEncodeValuesFromReflection(allocator, values);

        return self.encodePointers(allocator);
    }
    /// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
    ///
    /// Uses the `AbiEncodedValues` type to determine the correct behaviour.
    pub fn encodeAbiParametersValues(
        self: *Self,
        allocator: Allocator,
        values: []const AbiEncodedValues,
    ) Allocator.Error![]u8 {
        try self.preEncodeRuntimeValues(allocator, values);

        return self.encodePointers(allocator);
    }
    /// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
    ///
    /// The values types are checked at comptime based on the provided `params`.
    pub fn encodeAbiParameters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) Allocator.Error![]u8 {
        try self.preEncodeAbiParameters(params, allocator, values);

        return self.encodePointers(allocator);
    }
    /// Re-arranges the inner stack based on if the value that it's dealing with is either dynamic or now.
    /// Places those values in the `heads` or `tails` streams based on that.
    pub fn encodePointers(self: *Self, allocator: Allocator) Allocator.Error![]u8 {
        const slice = try self.pre_encoded.toOwnedSlice(allocator);
        defer {
            for (slice) |elem| elem.deinit(allocator);
            allocator.free(slice);
        }

        try self.heads.ensureUnusedCapacity(allocator, self.heads_size + self.tails_size);
        try self.tails.ensureUnusedCapacity(allocator, self.tails_size);

        for (slice) |param| {
            switch (param.type) {
                .dynamic => {
                    const size = encodeNumber(u256, self.tails.items.len + self.heads_size);

                    self.heads.appendSliceAssumeCapacity(size[0..]);
                    self.tails.appendSliceAssumeCapacity(param.encoded);
                },
                .static => self.heads.appendSliceAssumeCapacity(param.encoded),
            }
        }

        const tails_slice = try self.tails.toOwnedSlice(allocator);
        defer allocator.free(tails_slice);

        self.heads.appendSliceAssumeCapacity(tails_slice);
        return self.heads.toOwnedSlice(allocator);
    }
    /// Encodes the values and places them on the `inner` stack.
    pub fn preEncodeAbiParameters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) Allocator.Error!void {
        if (@TypeOf(values) == void)
            return;

        try self.pre_encoded.ensureUnusedCapacity(allocator, values.len);

        inline for (params, values) |param, value| {
            try self.preEncodeAbiParameter(param, allocator, value);
        }
    }
    /// Encodes a single value and places them on the `inner` stack.
    pub fn preEncodeAbiParameter(
        self: *Self,
        comptime param: AbiParameter,
        allocator: Allocator,
        value: AbiParameterToPrimative(param),
    ) Allocator.Error!void {
        switch (param.type) {
            .bool => {
                const encoded = encodeBoolean(value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .int => {
                const encoded = encodeNumber(i256, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .uint => {
                const encoded = encodeNumber(u256, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .address => {
                const encoded = encodeAddress(value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .fixedBytes => |bytes| {
                const encoded = encodeFixedBytes(bytes, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .string,
            .bytes,
            => {
                const encoded = try encodeString(allocator, value);

                self.heads_size += 32;
                self.tails_size += @intCast(32 + encoded.len);
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = encoded,
                    .type = .dynamic,
                });
            },
            .fixedArray => |arr_info| {
                const new_parameter: AbiParameter = .{
                    .type = arr_info.child.*,
                    .name = param.name,
                    .internalType = param.internalType,
                    .components = param.components,
                };

                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, arr_info.size);

                inline for (value) |val| {
                    try recursize.preEncodeAbiParameter(new_parameter, allocator, val);
                }

                if (isDynamicType(param)) {
                    const slice = try recursize.encodePointers(allocator);

                    self.heads_size += 32;
                    self.tails_size += @intCast(32 + slice.len);
                    return self.pre_encoded.appendAssumeCapacity(.{
                        .type = .dynamic,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer allocator.free(slice);

                self.heads_size += @intCast(arr_info.size * 32);
                try self.pre_encoded.appendSlice(allocator, slice);
            },
            .dynamicArray => |slice_info| {
                const new_parameter: AbiParameter = .{
                    .type = slice_info.*,
                    .name = param.name,
                    .internalType = param.internalType,
                    .components = param.components,
                };

                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, value.len);

                for (value) |val| {
                    try recursize.preEncodeAbiParameter(new_parameter, allocator, val);
                }

                const size = encodeNumber(u256, value.len);

                const slice = try recursize.encodePointers(allocator);
                defer allocator.free(slice);

                self.heads_size += 32;
                self.tails_size += @intCast(32 + slice.len);

                // Uses the `heads` as a scratch space to concat the slices.
                try recursize.heads.ensureUnusedCapacity(allocator, 32 + slice.len);
                recursize.heads.appendSliceAssumeCapacity(size[0..]);
                recursize.heads.appendSliceAssumeCapacity(slice);

                self.pre_encoded.appendAssumeCapacity(.{
                    .type = .dynamic,
                    .encoded = try recursize.heads.toOwnedSlice(allocator),
                });
            },
            .tuple => {
                if (param.components) |components| {
                    const fields = std.meta.fields(@TypeOf(value));

                    var recursize: Self = .empty;
                    try recursize.pre_encoded.ensureUnusedCapacity(allocator, fields.len);

                    inline for (components) |component| {
                        try recursize.preEncodeAbiParameter(component, allocator, @field(value, component.name));
                    }

                    if (isDynamicType(param)) {
                        const slice = try recursize.encodePointers(allocator);

                        self.heads_size += 32;
                        self.tails_size += @intCast(32 + slice.len);
                        return self.pre_encoded.appendAssumeCapacity(.{
                            .type = .dynamic,
                            .encoded = slice,
                        });
                    }

                    const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                    defer allocator.free(slice);

                    self.heads_size += @intCast(fields.len * 32);
                    try self.pre_encoded.appendSlice(allocator, slice);
                } else @compileError("Expected tuple parameter components!");
            },
            else => @compileError("Unsupported '" ++ @tagName(param.type) ++ "'"),
        }
    }
    /// Pre encodes the parameter values according to the specification and places it on `pre_encoded` arraylist.
    pub fn preEncodeRuntimeValues(
        self: *Self,
        allocator: Allocator,
        values: []const AbiEncodedValues,
    ) (error{InvalidType} || Allocator.Error)!void {
        try self.pre_encoded.ensureUnusedCapacity(allocator, values.len);

        for (values) |value| {
            try self.preEncodeRuntimeValue(allocator, value);
        }
    }
    /// Pre encodes the parameter value according to the specification and places it on `pre_encoded` arraylist.
    ///
    /// This methods and some runtime checks to see if the parameter are valid like `preEncodeAbiParameter` that instead uses
    /// comptime to get the exact expected types.
    pub fn preEncodeRuntimeValue(
        self: *Self,
        allocator: Allocator,
        value: AbiEncodedValues,
    ) (error{InvalidType} || Allocator.Error)!void {
        switch (value) {
            .bool => |val| {
                const encoded = encodeBoolean(val);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .int => |val| {
                const encoded = encodeNumber(i256, val);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .uint => |val| {
                const encoded = encodeNumber(u256, val);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .address => |val| {
                const encoded = encodeAddress(val);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .fixed_bytes => |val| {
                assert(val.len <= 32); // Fixed bytes can only be max 32 in size

                var buffer: [32]u8 = [_]u8{0} ** 32;
                @memcpy(buffer[0..val.len], val);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, buffer[0..]),
                    .type = .static,
                });
            },
            .string,
            .bytes,
            => |val| {
                const encoded = try encodeString(allocator, val);

                self.heads_size += 32;
                self.tails_size += @intCast(32 + encoded.len);
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = encoded,
                    .type = .dynamic,
                });
            },
            .fixed_array => |arr_values| {
                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, arr_values.len);

                const cached: AbiEncodedValues = arr_values[0];

                for (arr_values) |val| {
                    if (std.meta.activeTag(cached) != std.meta.activeTag(val))
                        return error.InvalidType;

                    try recursize.preEncodeRuntimeValue(allocator, val);
                }

                if (value.isDynamic()) {
                    const slice = try recursize.encodePointers(allocator);

                    self.heads_size += 32;
                    self.tails_size += @intCast(32 + slice.len);
                    return self.pre_encoded.appendAssumeCapacity(.{
                        .type = .dynamic,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer allocator.free(slice);

                self.heads_size += @intCast(arr_values.len * 32);
                try self.pre_encoded.appendSlice(allocator, slice);
            },
            .dynamic_array => |arr_values| {
                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, arr_values.len);

                const cached: AbiEncodedValues = arr_values[0];

                for (arr_values) |val| {
                    if (std.meta.activeTag(cached) != std.meta.activeTag(val))
                        return error.InvalidType;

                    try recursize.preEncodeRuntimeValue(allocator, val);
                }

                const size = encodeNumber(u256, arr_values.len);

                const slice = try recursize.encodePointers(allocator);
                defer allocator.free(slice);

                self.heads_size += 32;
                self.tails_size += @intCast(32 + slice.len);

                // Uses the `heads` as a scratch space to concat the slices.
                try recursize.heads.ensureUnusedCapacity(allocator, 32 + slice.len);
                recursize.heads.appendSliceAssumeCapacity(size[0..]);
                recursize.heads.appendSliceAssumeCapacity(slice);

                self.pre_encoded.appendAssumeCapacity(.{
                    .type = .dynamic,
                    .encoded = try recursize.heads.toOwnedSlice(allocator),
                });
            },
            .tuple => |tuple_values| {
                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, tuple_values.len);

                for (tuple_values) |component| {
                    try recursize.preEncodeRuntimeValue(allocator, component);
                }

                if (value.isDynamic()) {
                    const slice = try recursize.encodePointers(allocator);

                    self.heads_size += 32;
                    self.tails_size += @intCast(32 + slice.len);
                    return self.pre_encoded.appendAssumeCapacity(.{
                        .type = .dynamic,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer allocator.free(slice);

                self.heads_size += @intCast(tuple_values.len * 32);
                try self.pre_encoded.appendSlice(allocator, slice);
            },
        }
    }
    /// This will use zig's ability to provide compile time reflection based on the `values` provided.
    /// The `values` must be a tuple struct. Otherwise it will trigger a compile error.
    pub fn preEncodeValuesFromReflection(self: *Self, allocator: Allocator, values: anytype) Allocator.Error!void {
        const info = @typeInfo(@TypeOf(values));

        if (info != .@"struct" or !info.@"struct".is_tuple)
            @compileError("Values must be a tuple struct");

        try self.pre_encoded.ensureUnusedCapacity(allocator, info.@"struct".fields.len);

        inline for (info.@"struct".fields) |field| {
            try self.preEncodeReflection(allocator, @field(values, field.name));
        }
    }
    /// This will use zig's ability to provide compile time reflection based on the `value` provided.
    pub fn preEncodeReflection(self: *Self, allocator: Allocator, value: anytype) Allocator.Error!void {
        const info = @typeInfo(@TypeOf(value));

        switch (info) {
            .bool => {
                const encoded = encodeBoolean(value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .int => |int_info| {
                const encoded = switch (int_info.signedness) {
                    .signed => encodeNumber(i256, value),
                    .unsigned => encodeNumber(u256, value),
                };

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .type = .static,
                });
            },
            .comptime_int => {
                const IntType = std.math.IntFittingRange(value, value);

                return self.preEncodeReflection(allocator, @as(IntType, @intCast(value)));
            },
            .optional => {
                if (value) |val| return self.preEncodeReflection(allocator, val) else @compileError("Unsupported null value");
            },
            .enum_literal,
            .@"enum",
            => {
                const encoded = try encodeString(allocator, @tagName(value));

                self.heads_size += 32;
                self.tails_size += @intCast(32 + encoded.len);

                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = encoded,
                    .type = .dynamic,
                });
            },
            .array => |arr_info| {
                if (arr_info.child == u8) {
                    if (arr_info.len == 20) {
                        const encoded = encodeAddress(value);

                        self.heads_size += 32;
                        return self.pre_encoded.appendAssumeCapacity(.{
                            .encoded = try allocator.dupe(u8, encoded[0..]),
                            .type = .static,
                        });
                    }

                    const encoded = encodeFixedBytes(arr_info.len, value);

                    self.heads_size += 32;
                    return self.pre_encoded.appendAssumeCapacity(.{
                        .encoded = try allocator.dupe(u8, encoded[0..]),
                        .type = .static,
                    });
                }

                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, arr_info.len);

                inline for (value) |val| {
                    try recursize.preEncodeReflection(allocator, val);
                }

                if (utils.isDynamicType(@TypeOf(value))) {
                    const slice = try recursize.encodePointers(allocator);

                    self.heads_size += 32;
                    self.tails_size += @intCast(32 + slice.len);
                    return self.pre_encoded.appendAssumeCapacity(.{
                        .type = .dynamic,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer allocator.free(slice);

                self.heads_size += @intCast(arr_info.len * 32);
                try self.pre_encoded.appendSlice(allocator, slice);
            },
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .array,
                        => {
                            const Slice = []const std.meta.Elem(ptr_info.child);
                            return self.preEncodeReflection(allocator, @as(Slice, value));
                        },
                        else => return self.preEncodeReflection(allocator, value.*),
                    },
                    .Slice => {
                        if (ptr_info.child == u8) {
                            const encoded = try encodeString(allocator, value);

                            self.heads_size += 32;
                            self.tails_size += @intCast(32 + encoded.len);

                            return self.pre_encoded.appendAssumeCapacity(.{
                                .encoded = encoded,
                                .type = .dynamic,
                            });
                        }

                        var recursize: Self = .empty;
                        try recursize.pre_encoded.ensureUnusedCapacity(allocator, value.len);

                        for (value) |val| {
                            try recursize.preEncodeReflection(allocator, val);
                        }

                        const size = encodeNumber(u256, value.len);

                        const slice = try recursize.encodePointers(allocator);
                        defer allocator.free(slice);

                        self.heads_size += 32;
                        self.tails_size += @intCast(32 + slice.len);

                        // Uses the `heads` as a scratch space to concat the slices.
                        try recursize.heads.ensureUnusedCapacity(allocator, 32 + slice.len);
                        recursize.heads.appendSliceAssumeCapacity(size[0..]);
                        recursize.heads.appendSliceAssumeCapacity(slice);

                        self.pre_encoded.appendAssumeCapacity(.{
                            .type = .dynamic,
                            .encoded = try recursize.heads.toOwnedSlice(allocator),
                        });
                    },
                    else => @compileError("Unsupported pointer type '" ++ @tagName(ptr_info.child) ++ "'"),
                }
            },
            .@"struct" => |struct_info| {
                var recursize: Self = .empty;
                try recursize.pre_encoded.ensureUnusedCapacity(allocator, struct_info.fields.len);

                inline for (struct_info.fields) |field| {
                    try recursize.preEncodeReflection(allocator, @field(value, field.name));
                }

                if (utils.isDynamicType(@TypeOf(value))) {
                    const slice = try recursize.encodePointers(allocator);

                    self.heads_size += 32;
                    self.tails_size += @intCast(32 + slice.len);

                    return self.pre_encoded.appendAssumeCapacity(.{
                        .type = .dynamic,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer allocator.free(slice);

                self.heads_size += @intCast(struct_info.fields.len * 32);
                try self.pre_encoded.appendSlice(allocator, slice);
            },
            else => @compileError("Unsupported type '" ++ @typeName(@TypeOf(value)) ++ "'"),
        }
    }
};

/// Similar to `AbiEncoder` but used for packed encoding.
pub const EncodePacked = struct {
    /// Changes the encoder behaviour based on the type of the parameter.
    param_type: ParameterType,
    /// List that is used to write the encoded values too.
    list: ArrayList(u8),

    /// Sets the initial state of the encoder.
    pub fn init(allocator: Allocator, param_type: ParameterType) EncodePacked {
        const list = ArrayList(u8).init(allocator);

        return .{
            .param_type = param_type,
            .list = list,
        };
    }
    /// Abi encodes the values. If the values are dynamic all of the child values
    /// will be encoded as 32 sized values with the expection of []u8 slices.
    pub fn encodePacked(self: *EncodePacked, value: anytype) Allocator.Error![]u8 {
        try self.list.ensureUnusedCapacity(@sizeOf(@TypeOf(value)));
        try self.encodePackedValue(value);

        return self.list.toOwnedSlice();
    }
    /// Handles the encoding based on the value type and writes them to the list.
    pub fn encodePackedValue(self: *EncodePacked, value: anytype) Allocator.Error!void {
        const info = @typeInfo(@TypeOf(value));
        const writer = self.list.writer();

        switch (info) {
            .bool => return switch (self.param_type) {
                .dynamic => writer.writeInt(u256, @intFromBool(value), .big),
                .static => writer.writeInt(u8, @intFromBool(value), .big),
            },
            .int => return switch (self.param_type) {
                .dynamic => writer.writeInt(u256, value, .big),
                .static => writer.writeInt(ByteAlignedInt(@TypeOf(value)), @intCast(value), .big),
            },
            .comptime_int => {
                const IntType = std.math.IntFittingRange(value, value);

                return self.encodePackedValue(@as(IntType, value));
            },
            .optional => if (value) |val| return self.encodePackedValue(val),
            .@"enum",
            .enum_literal,
            => return self.encodePackedValue(@tagName(value)),
            .error_set => return self.encodePackedValue(@errorName(value)),
            .array => |arr_info| {
                if (arr_info.child == u8)
                    switch (self.param_type) {
                        .dynamic => {
                            if (arr_info.len == 20)
                                return writer.writeAll(&encodeAddress(value));
                            return writer.writeAll(&encodeFixedBytes(arr_info.len, value));
                        },
                        .static => return writer.writeAll(&value),
                    };

                self.changeParameterType(.dynamic);
                for (value) |val| {
                    try self.encodePackedValue(val);
                }
            },
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .array => {
                            const Slice = []const std.meta.Elem(ptr_info.child);

                            return self.encodePackedValue(@as(Slice, value));
                        },
                        else => return self.encodePackedValue(value.*),
                    },
                    .Slice => {
                        if (ptr_info.child == u8)
                            return writer.writeAll(value);

                        self.changeParameterType(.dynamic);
                        for (value) |val| {
                            try self.encodePackedValue(val);
                        }
                    },
                    else => @compileError("Unsupported pointer type '" ++ @typeName(@TypeOf(value)) ++ "'"),
                }
            },
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple)
                    self.changeParameterType(.dynamic);

                inline for (struct_info.fields) |field| {
                    try self.encodePackedValue(@field(value, field.name));
                }
            },
            else => @compileError("Unsupported type '" ++ @typeName(@TypeOf(value)) ++ "'"),
        }
    }
    /// Used to change the type of value it's dealing with.
    pub fn changeParameterType(self: *EncodePacked, param_type: ParameterType) void {
        self.param_type = param_type;
    }
};

/// Encodes a boolean value according to the abi encoding specification.
pub fn encodeBoolean(boolean: bool) [32]u8 {
    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, @intFromBool(boolean), .big);

    return buffer;
}
/// Encodes a integer value according to the abi encoding specification.
pub fn encodeNumber(comptime T: type, number: T) [32]u8 {
    const info = @typeInfo(T);
    assert(info == .int);

    var buffer: [@divExact(info.int.bits, 8)]u8 = undefined;
    std.mem.writeInt(T, &buffer, number, .big);

    return buffer;
}
/// Encodes an solidity address value according to the abi encoding specification.
pub fn encodeAddress(address: Address) [32]u8 {
    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, @byteSwap(@as(u160, @bitCast(address))), .big);

    return buffer;
}
/// Encodes an bytes1..32 value according to the abi encoding specification.
pub fn encodeFixedBytes(comptime size: usize, payload: [size]u8) [32]u8 {
    assert(size <= 32);
    const IntType = std.meta.Int(.unsigned, size * 8);

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, @as(IntType, @bitCast(payload)), .little);

    return buffer;
}
/// Encodes an solidity string or bytes value according to the abi encoding specification.
pub fn encodeString(allocator: Allocator, payload: []const u8) Allocator.Error![]u8 {
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(payload.len))) / 32);
    const padded_size = (ceil + 1) * 32;

    var list = try std.ArrayList(u8).initCapacity(allocator, padded_size + 32);
    errdefer list.deinit();

    var writer = list.writer();
    try writer.writeInt(u256, payload.len, .big);

    list.appendSliceAssumeCapacity(payload);
    try writer.writeByteNTimes(0, padded_size - payload.len);

    return list.toOwnedSlice();
}
/// Checks if a given parameter is a dynamic abi type.
pub inline fn isDynamicType(comptime param: AbiParameter) bool {
    switch (param.type) {
        .bool,
        .int,
        .uint,
        .fixedBytes,
        .@"enum",
        .address,
        => return false,
        .string,
        .bytes,
        .dynamicArray,
        => return true,
        .fixedArray => |info| {
            const new_parameter: AbiParameter = .{
                .type = info.child.*,
                .name = param.name,
                .internalType = param.internalType,
                .components = param.components,
            };

            return isDynamicType(new_parameter);
        },
        .tuple => {
            inline for (param.components orelse @compileError("Expected components to not be null")) |component| {
                if (isDynamicType(component))
                    return true;
            } else return false;
        },
    }
}
