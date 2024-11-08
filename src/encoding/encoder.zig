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

/// Encode an Solidity `Error` type with the signature and the values encoded.
/// The signature is calculated by hashing the formated string generated from the `Error` signature.
///
/// Caller owns the memory.
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

/// Encode an Solidity `Error` type with the signature and the values encoded.
/// The signature is calculated by hashing the formated string generated from the `Error` signature.
///
/// Caller owns the memory.
pub fn encodeAbiFunctionOutputs(
    comptime func: Function,
    allocator: Allocator,
    values: AbiParametersToPrimative(func.outputs),
) Allocator.Error![]u8 {
    return encodeAbiParameters(func.outputs, allocator, values);
}

/// Encode an Solidity `Error` type with the signature and the values encoded.
/// The signature is calculated by hashing the formated string generated from the `Error` signature.
///
/// Caller owns the memory.
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

pub fn encodeAbiConstructor(
    comptime constructor: Constructor,
    allocator: Allocator,
    values: AbiParametersToPrimative(constructor.inputs),
) Allocator.Error![]u8 {
    return encodeAbiParameters(constructor.inputs, allocator, values);
}

pub fn encodeAbiParameters(
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) Allocator.Error![]u8 {
    var encoder: AbiEncoder = .empty;
    try encoder.preEncodeAbiParamters(params, allocator, values);

    return encoder.encodePointers(allocator);
}

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

    pre_encoded: ArrayListUnmanaged(PreEncodedStructure),
    heads: ArrayListUnmanaged(u8),
    tails: ArrayListUnmanaged(u8),
    heads_size: u32,
    tails_size: u32,

    pub fn encodeAbiParameters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) Allocator.Error![]u8 {
        try self.preEncodeAbiParamters(params, allocator, values);

        return self.encodePointers(allocator);
    }

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

    pub fn preEncodeAbiParamters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) Allocator.Error!void {
        try self.pre_encoded.ensureUnusedCapacity(allocator, values.len);

        inline for (params, values) |param, value| {
            try self.preEncodeAbiParameter(param, allocator, value);
        }
    }

    pub fn preEncodeAbiParameter(
        self: *Self,
        comptime param: AbiParameter,
        allocator: Allocator,
        value: AbiParameterToPrimative(param),
    ) Allocator.Error!void {
        switch (param.type) {
            .bool => {
                const encoded = encodeBoolean(value);

                self.pre_encoded.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
                self.heads_size += 32;
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

    pub fn encodeBoolean(boolean: bool) [32]u8 {
        var buffer: [32]u8 = undefined;
        std.mem.writeInt(u256, &buffer, @intFromBool(boolean), .big);

        return buffer;
    }

    pub fn encodeNumber(comptime T: type, number: T) [32]u8 {
        const info = @typeInfo(T);
        assert(info == .int);

        var buffer: [@divExact(info.int.bits, 8)]u8 = undefined;
        std.mem.writeInt(T, &buffer, number, .big);

        return buffer;
    }

    pub fn encodeAddress(address: [20]u8) [32]u8 {
        var buffer: [32]u8 = undefined;
        std.mem.writeInt(u256, &buffer, @byteSwap(@as(u160, @bitCast(address))), .big);

        return buffer;
    }

    pub fn encodeFixedBytes(comptime size: usize, payload: [size]u8) [32]u8 {
        assert(size <= 32);
        const IntType = std.meta.Int(.unsigned, size * 8);

        var buffer: [32]u8 = undefined;
        std.mem.writeInt(u256, &buffer, @as(IntType, @bitCast(payload)), .little);

        return buffer;
    }

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
};

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
