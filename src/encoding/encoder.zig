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
const ArrayListWriter = std.ArrayList(u8).Writer;
const Allocator = std.mem.Allocator;
const Constructor = zabi_abi.abitypes.Constructor;
const Error = zabi_abi.abitypes.Error;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Function = zabi_abi.abitypes.Function;
const ParamType = zabi_abi.param_type.ParamType;

/// Set of errors while perfoming abi encoding.
pub const EncodeErrors = Allocator.Error || error{
    InvalidIntType,
    Overflow,
    BufferExceedsMaxSize,
    InvalidBits,
    InvalidLength,
    NoSpaceLeft,
    InvalidCharacter,
    InvalidParamType,
};

pub const EncodedValues = struct {
    dynamic: bool,
    encoded: []const u8,
};

pub fn encodeAbiParameters(
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) ![]u8 {
    var encoder: AbiEncoder = .empty;
    try encoder.preEncodeAbiParamters(params, allocator, values);

    return encoder.encodePointers(allocator);
}

pub const AbiEncoder = struct {
    pub const Self = @This();

    pub const empty: Self = .{
        .stack = .empty,
        .heads = .empty,
        .tails = .empty,
    };

    stack: std.ArrayListUnmanaged(EncodedValues),
    heads: std.ArrayListUnmanaged(u8),
    tails: std.ArrayListUnmanaged(u8),

    pub fn encodeAbiParameterV2(self: *Self, comptime param: AbiParameter, allocator: Allocator, value: AbiParameterToPrimative(param)) ![]u8 {
        const static_size = calculateStaticSize(param);

        const encoded = switch (param.type) {
            .bool => return encodeBoolean(value)[0..],
            .int => return encodeBoolean(i256, value)[0..],
            .uint => return encodeNumber(u256, value)[0..],
            .address => encodeAddress(value)[0..],
            .fixedBytes => |bytes| encodeFixedBytes(bytes, value)[0..],
            .string,
            .bytes,
            => encodeString(allocator, value),
            else => @compileError("Unsupported"),
        };

        var dynamic_size = 0;

        if (isDynamicType(param)) {
            const size = encodeNumber(u256, dynamic_size + static_size);

            try self.heads.appendSlice(allocator, size[0..]);
            try self.tails.appendSlice(allocator, encoded);

            dynamic_size += @intCast(encoded.len);
        } else {
            try self.heads.appendSlice(allocator, encoded);
        }

        const tails_slice = try self.tails.toOwnedSlice(allocator);
        defer allocator.free(tails_slice);

        try self.heads.appendSlice(tails_slice);
        return self.heads.toOwnedSlice(allocator);
    }

    pub fn encodePointers(self: *Self, allocator: Allocator) ![]u8 {
        const slice = try self.stack.toOwnedSlice(allocator);
        defer {
            for (slice) |s| allocator.free(s.encoded);
            allocator.free(slice);
        }

        var static_size: u32 = 0;
        var dynamic_size: u32 = 0;
        var tails_size: u32 = 0;

        // Calculates the expected memory size and pointer index start.
        {
            for (slice) |param| {
                if (param.dynamic) {
                    static_size += 32;
                    tails_size += 32 + @as(u32, @intCast(param.encoded.len));
                } else static_size += @intCast(param.encoded.len);
            }
        }

        try self.heads.ensureUnusedCapacity(allocator, static_size + tails_size);
        try self.tails.ensureUnusedCapacity(allocator, tails_size);

        for (slice) |param| {
            if (param.dynamic) {
                const size = encodeNumber(u256, dynamic_size + static_size);

                self.heads.appendSliceAssumeCapacity(size[0..]);
                self.tails.appendSliceAssumeCapacity(param.encoded);

                dynamic_size += @intCast(param.encoded.len);
            } else {
                self.heads.appendSliceAssumeCapacity(param.encoded);
            }
        }

        const tails_slice = try self.tails.toOwnedSlice(allocator);
        defer allocator.free(tails_slice);

        self.heads.appendSliceAssumeCapacity(tails_slice);
        return self.heads.toOwnedSlice(allocator);
    }

    pub fn encodeAbiParameters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) ![]u8 {
        try self.preEncodeAbiParamters(params, allocator, values);

        return self.encodePointers(allocator);
    }

    pub fn preEncodeAbiParamters(
        self: *Self,
        comptime params: []const AbiParameter,
        allocator: Allocator,
        values: AbiParametersToPrimative(params),
    ) !void {
        try self.stack.ensureUnusedCapacity(allocator, values.len);

        inline for (params, values) |param, value| {
            try self.preEncodeAbiParameter(param, allocator, value);
        }
    }

    pub fn preEncodeAbiParameter(
        self: *Self,
        comptime param: AbiParameter,
        allocator: Allocator,
        value: AbiParameterToPrimative(param),
    ) !void {
        switch (param.type) {
            .bool => {
                const encoded = encodeBoolean(value);

                self.stack.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .int => {
                const encoded = encodeNumber(i256, value);

                self.stack.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .uint => {
                const encoded = encodeNumber(u256, value);

                self.stack.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .address => {
                const encoded = encodeAddress(value);

                self.stack.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .fixedBytes => |bytes| {
                const encoded = encodeFixedBytes(bytes, value);

                self.stack.appendAssumeCapacity(.{
                    .encoded = try allocator.dupe(u8, encoded[0..]),
                    .dynamic = false,
                });
            },
            .string,
            .bytes,
            => {
                const encoded = try encodeString(allocator, value);

                self.stack.appendAssumeCapacity(.{
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
                try recursize.stack.ensureUnusedCapacity(allocator, arr_info.size);

                inline for (value) |val| {
                    try recursize.preEncodeAbiParameter(new_parameter, allocator, val);
                }

                if (isDynamicType(param)) {
                    const slice = try recursize.encodePointers(allocator);

                    return self.stack.appendAssumeCapacity(.{
                        .dynamic = true,
                        .encoded = slice,
                    });
                }

                const slice = try recursize.stack.toOwnedSlice(allocator);
                defer {
                    for (slice) |s| allocator.free(s.encoded);
                    allocator.free(slice);
                }

                var list = std.ArrayList(u8).init(allocator);
                errdefer list.deinit();

                for (slice) |s| {
                    try list.writer().writeAll(s.encoded);
                }

                try self.stack.append(allocator, .{
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
                try recursize.stack.ensureUnusedCapacity(allocator, value.len);

                for (value) |val| {
                    try recursize.preEncodeAbiParameter(new_parameter, allocator, val);
                }

                const size = encodeNumber(u256, value.len);

                const slice = try recursize.encodePointers(allocator);
                defer allocator.free(slice);

                self.stack.appendAssumeCapacity(.{
                    .dynamic = true,
                    .encoded = try std.mem.concat(allocator, u8, &.{ size[0..], slice }),
                });
            },
            .tuple => {
                if (param.components) |components| {
                    var recursize: Self = .empty;
                    try recursize.stack.ensureUnusedCapacity(allocator, std.meta.fields(@TypeOf(value)).len);

                    inline for (components) |component| {
                        try recursize.preEncodeAbiParameter(component, allocator, @field(value, component.name));
                    }

                    if (isDynamicType(param)) {
                        const slice = try recursize.encodePointers(allocator);

                        return self.stack.appendAssumeCapacity(.{
                            .dynamic = true,
                            .encoded = slice,
                        });
                    }

                    const slice = try recursize.stack.toOwnedSlice(allocator);
                    defer {
                        for (slice) |s| allocator.free(s.encoded);
                        allocator.free(slice);
                    }

                    var list = std.ArrayList(u8).init(allocator);
                    errdefer list.deinit();

                    for (slice) |s| {
                        try list.writer().writeAll(s.encoded);
                    }

                    try self.stack.append(allocator, .{
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

pub inline fn calculateStaticSize(comptime param: AbiParameter) u32 {
    switch (param.type) {
        .bool,
        .int,
        .uint,
        .fixedBytes,
        .@"enum",
        .bytes,
        .string,
        .dynamicArray,
        .address,
        => return 32,
        .fixedArray => |arr_info| {
            const new_parameter: AbiParameter = .{
                .type = arr_info.child.*,
                .name = param.name,
                .internalType = param.internalType,
                .components = param.components,
            };

            if (isDynamicType(new_parameter))
                return 32;

            return @intCast(calculateStaticSize(new_parameter) * arr_info.size);
        },
        .tuple => {
            var offset: u32 = 0;
            inline for (param.components orelse @compileError("Expected components to not be null")) |component| {
                if (isDynamicType(component)) {
                    return 32;
                } else offset += calculateStaticSize(component);
            }

            return offset;
        },
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
