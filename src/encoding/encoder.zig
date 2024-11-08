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
const Constructor = zabi_abi.abitypes.Constructor;
const Error = zabi_abi.abitypes.Error;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Function = zabi_abi.abitypes.Function;
const ParamType = zabi_abi.param_type.ParamType;

/// Set of errors while perfoming abi encoding.
pub const EncodeErrors = Allocator.Error || error{NoSpaceLeft};

pub const PreEncodedStructure = struct {
    dynamic: bool,
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

    try encoder.preEncodeAbiParamters(func.inputs, allocator, values);
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

    try encoder.preEncodeAbiParamters(err.inputs, allocator, values);
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
    try encoder.preEncodeAbiParamters(params, allocator, values);

    return encoder.encodePointers(allocator);
}

/// The abi encoding structure used to encoded values with the abi encoding [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
///
/// You can initialize this structure like this:
/// ```zig
/// var encoder: AbiEncoder = .empty;
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
    /// in the `encodePointers` sets to re-arrange the location in the encoded string.
    pre_encoded: ArrayListUnmanaged(PreEncodedStructure),
    /// Stream of encoded values that should show up at the top of the encoded slice.
    heads: ArrayListUnmanaged(u8),
    /// Stream of encoded values that should show up at the enc of the encoded slice.
    tails: ArrayListUnmanaged(u8),
    /// Used to calculated the initial pointer when facing `dynamic` types.
    /// Also used to know the memory size of the `heads` stream.
    heads_size: u32,
    /// Only used to know the memory size of the `tails` stream.
    tails_size: u32,

    /// Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)
    ///
    /// The values types are checked at comptime based on the provided `params`.
    pub fn encodeAbiParameters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) Allocator.Error![]u8 {
        try self.preEncodeAbiParamters(params, allocator, values);

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
            if (param.dynamic) {
                const size = encodeNumber(u256, self.tails.items.len + self.heads_size);

                self.heads.appendSliceAssumeCapacity(size[0..]);
                self.tails.appendSliceAssumeCapacity(param.encoded);
            } else {
                self.heads.appendSliceAssumeCapacity(param.encoded);
            }
        }

        const tails_slice = try self.tails.toOwnedSlice(allocator);
        defer allocator.free(tails_slice);

        self.heads.appendSliceAssumeCapacity(tails_slice);
        return self.heads.toOwnedSlice(allocator);
    }
    /// Encodes the values and places them on the `inner` stack.
    pub fn preEncodeAbiParamters(
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
                    .dynamic = false,
                });
            },
            .int => {
                const encoded = encodeNumber(i256, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .uint => {
                const encoded = encodeNumber(u256, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .address => {
                const encoded = encodeAddress(value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .fixedBytes => |bytes| {
                const encoded = encodeFixedBytes(bytes, value);

                self.heads_size += 32;
                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
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
                    .dynamic = true,
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
                        .dynamic = true,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                defer {
                    for (slice) |s| allocator.free(s.encoded);
                    allocator.free(slice);
                }

                var list = try std.ArrayList(u8).initCapacity(allocator, arr_info.size * 32);
                errdefer list.deinit();

                for (slice) |pre_encoded| {
                    list.appendSliceAssumeCapacity(pre_encoded.encoded);
                }

                self.heads_size += @intCast(list.items.len);
                self.pre_encoded.appendAssumeCapacity(.{
                    .dynamic = false,
                    .encoded = try list.toOwnedSlice(),
                });
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
                    .dynamic = true,
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
                            .dynamic = true,
                            .encoded = slice,
                        });
                    }

                    const slice = try recursize.pre_encoded.toOwnedSlice(allocator);
                    defer {
                        for (slice) |s| allocator.free(s.encoded);
                        allocator.free(slice);
                    }

                    var list = try std.ArrayList(u8).initCapacity(allocator, fields.len * 32);
                    errdefer list.deinit();

                    for (slice) |pre_encoded| {
                        list.appendSliceAssumeCapacity(pre_encoded.encoded);
                    }

                    self.heads_size += @intCast(list.items.len);
                    self.pre_encoded.appendAssumeCapacity(.{
                        .dynamic = false,
                        .encoded = try list.toOwnedSlice(),
                    });
                } else @compileError("Expected tuple parameter components!");
            },
            else => @compileError("Unsupported '" ++ @tagName(param.type) ++ "'"),
        }
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
/// Encode values based on solidity's `encodePacked`.
/// Solidity types are infered from zig ones since it closely follows them.
///
/// Caller owns the memory and it must free them.
pub fn encodePacked(allocator: Allocator, values: anytype) Allocator.Error![]u8 {
    const fields = @typeInfo(@TypeOf(values));

    if (fields != .@"struct" or !fields.@"struct".is_tuple)
        @compileError("Expected " ++ @typeName(@TypeOf(values)) ++ " to be a tuple value instead");

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    inline for (values) |value| {
        try encodePackedParameters(value, &list.writer(), false);
    }

    return list.toOwnedSlice();
}

// Internal
fn encodePackedParameters(value: anytype, writer: anytype, is_slice: bool) !void {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .bool => {
            const as_int = @intFromBool(value);
            if (is_slice) {
                try writer.writeInt(u256, as_int, .big);
            } else try writer.writeInt(u8, as_int, .big);
        },
        .int => return if (is_slice) writer.writeInt(u256, value, .big) else writer.writeInt(@TypeOf(value), value, .big),
        .comptime_int => {
            var buffer: [32]u8 = undefined;
            const size = utils.formatInt(@intCast(value), &buffer);

            if (is_slice)
                try writer.writeAll(buffer[0..])
            else
                try writer.writeAll(buffer[32 - size ..]);
        },
        .optional => |opt_info| {
            if (value) |val| {
                return encodePackedParameters(@as(opt_info.child, val), writer, is_slice);
            }
        },
        .@"enum", .enum_literal => return encodePackedParameters(@tagName(value), writer, is_slice),
        .error_set => return encodePackedParameters(@errorName(value), writer, is_slice),
        .array => |arr_info| {
            if (arr_info.child == u8) {
                if (arr_info.len == 20) {
                    if (is_slice) {
                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buffer[12..], value[0..]);
                        return writer.writeAll(buffer[0..]);
                    } else return writer.writeAll(&value);
                }

                return writer.writeAll(&value);
            }

            for (value) |val| {
                try encodePackedParameters(val, writer, true);
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return encodePackedParameters(value.*, writer, is_slice),
                .Slice => {
                    if (ptr_info.child == u8)
                        return writer.writeAll(value);

                    for (value) |val| {
                        try encodePackedParameters(val, writer, true);
                    }
                },
                else => @compileError("Unsupported ponter type '" ++ @typeName(@TypeOf(value)) ++ "'"),
            }
        },
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                try encodePackedParameters(@field(value, field.name), writer, if (struct_info.is_tuple) true else false);
            }
        },
        else => @compileError("Unsupported type '" ++ @typeName(@TypeOf(value)) ++ "'"),
    }
}

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
