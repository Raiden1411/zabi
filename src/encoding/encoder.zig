const std = @import("std");
const abi = @import("../abi/abi_parameter.zig");
const meta = @import("../meta/abi.zig");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");
const assert = std.debug.assert;

/// Types
const AbiParameter = abi.AbiParameter;
const AbiParameterToPrimative = meta.AbiParameterToPrimative;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Address = types.Address;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Constructor = @import("../abi/abi.zig").Constructor;
const Error = @import("../abi/abi.zig").Error;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Function = @import("../abi/abi.zig").Function;
const ParamType = @import("../abi/param_type.zig").ParamType;

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

/// Return type while pre encoding individual types.
pub const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
};

/// Return type of the abi encoding
pub const AbiEncoded = struct {
    arena: *ArenaAllocator,
    data: []u8,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();

        allocator.destroy(self.arena);
    }
};
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiConstructorComptime(allocator: Allocator, comptime constructor: Constructor, values: AbiParametersToPrimative(constructor.inputs)) EncodeErrors!AbiEncoded {
    return encodeAbiParametersComptime(allocator, constructor.inputs, values);
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiErrorComptime(allocator: Allocator, comptime err: Error, values: AbiParametersToPrimative(err.inputs)) EncodeErrors![]u8 {
    const prep_signature = try err.allocPrepare(allocator);
    defer allocator.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    var encoded_params = try encodeAbiParametersComptime(allocator, err.inputs, values);
    defer encoded_params.deinit();

    const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

    @memcpy(buffer[0..4], hashed[0..4]);
    @memcpy(buffer[4..], encoded_params.data[0..]);

    return buffer;
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiFunctionComptime(allocator: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.inputs)) EncodeErrors![]u8 {
    const prep_signature = try function.allocPrepare(allocator);
    defer allocator.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    if (function.inputs.len == 0) {
        const buffer = try allocator.alloc(u8, 4);

        @memcpy(buffer[0..4], hashed[0..4]);

        return buffer;
    }

    const encoded_params = try encodeAbiParametersComptime(allocator, function.inputs, values);
    defer encoded_params.deinit();

    const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

    @memcpy(buffer[0..4], hashed[0..4]);
    @memcpy(buffer[4..], encoded_params.data[0..]);

    return buffer;
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiFunctionOutputsComptime(allocator: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.outputs)) EncodeErrors![]u8 {
    const prep_signature = try function.allocPrepare(allocator);
    defer allocator.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    const encoded_params = try encodeAbiParametersComptime(allocator, function.outputs, values);
    defer encoded_params.deinit();

    const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

    @memcpy(buffer[0..4], hashed[0..4]);
    @memcpy(buffer[4..], encoded_params.data[0..]);

    return buffer;
}
/// Main function that will be used to encode abi paramters.
/// This will allocate and a ArenaAllocator will be used to manage the memory.
///
/// Caller owns the memory.
pub fn encodeAbiParametersComptime(alloc: Allocator, comptime parameters: []const AbiParameter, values: AbiParametersToPrimative(parameters)) EncodeErrors!AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, parameters, values);

    return abi_encoded;
}
/// Subset function used for encoding. Its highly recommend to use an ArenaAllocator
/// or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
/// and with those all of the memory can be freed at once.
///
/// Caller owns the memory.
pub fn encodeAbiParametersLeakyComptime(alloc: Allocator, comptime params: []const AbiParameter, values: AbiParametersToPrimative(params)) EncodeErrors![]u8 {
    const prepared = try preEncodeParams(alloc, params, values);
    const data = try encodeParameters(alloc, prepared);

    return data;
}

/// Main function that will be used to encode abi paramters.
/// This will allocate and a ArenaAllocator will be used to manage the memory.
///
/// Caller owns the memory.
///
/// If the parameters are comptime know consider using `encodeAbiParametersComptime`
/// This will provided type safe values to be passed into the function.
/// However runtime reflection will happen to best determine what values should be used based
/// on the parameters passed in.
pub fn encodeAbiParameters(alloc: Allocator, parameters: []const AbiParameter, values: anytype) EncodeErrors!AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, parameters, values);

    return abi_encoded;
}

/// Subset function used for encoding. Its highly recommend to use an ArenaAllocator
/// or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
/// and with those all of the memory can be freed at once.
///
/// Caller owns the memory.
///
/// If the parameters are comptime know consider using `encodeAbiParametersComptimeLeaky`
/// This will provided type safe values to be passed into the function.
/// However runtime reflection will happen to best determine what values should be used based
/// on the parameters passed in.
pub fn encodeAbiParametersLeaky(alloc: Allocator, params: []const AbiParameter, values: anytype) EncodeErrors![]u8 {
    const fields = @typeInfo(@TypeOf(values));

    if (fields != .@"struct" or !fields.@"struct".is_tuple)
        @compileError("Expected " ++ @typeName(@TypeOf(values)) ++ " to be a tuple value instead");

    const prepared = try preEncodeParams(alloc, params, values);
    const data = try encodeParameters(alloc, prepared);

    return data;
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
        .vector => |vec_info| {
            for (0..vec_info.len) |i| {
                try encodePackedParameters(value[i], writer, true);
            }
        },
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

fn encodeParameters(allocator: Allocator, params: []PreEncodedParam) ![]u8 {
    var s_size: usize = 0;

    for (params) |param| {
        if (param.dynamic) s_size += 32 else s_size += param.encoded.len;
    }

    const MultiEncoded = std.MultiArrayList(struct {
        static: []u8,
        dynamic: []u8,
    });

    var list: MultiEncoded = .{};

    var d_size: usize = 0;
    for (params) |param| {
        if (param.dynamic) {
            const size = try encodeNumber(allocator, u256, s_size + d_size);
            try list.append(allocator, .{ .static = size.encoded, .dynamic = param.encoded });

            d_size += param.encoded.len;
        } else {
            try list.append(allocator, .{ .static = param.encoded, .dynamic = "" });
        }
    }

    const static = try std.mem.concat(allocator, u8, list.items(.static));
    const dynamic = try std.mem.concat(allocator, u8, list.items(.dynamic));
    const concated = try std.mem.concat(allocator, u8, &.{ static, dynamic });

    return concated;
}

fn preEncodeParams(allocator: Allocator, params: []const AbiParameter, values: anytype) ![]PreEncodedParam {
    assert(params.len == values.len);

    var list = try std.ArrayList(PreEncodedParam).initCapacity(allocator, params.len);

    inline for (params, values) |param, value| {
        const pre_encoded = try preEncodeParam(allocator, param, value);
        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

fn preEncodeParam(allocator: Allocator, param: AbiParameter, value: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try preEncodeParam(allocator, param, value.*),
                .Slice => {
                    if (ptr_info.child == u8) {
                        const slice: []const u8 = slice: {
                            if (std.mem.startsWith(u8, value[0..], "0x")) {
                                break :slice value[2..];
                            }

                            break :slice value[0..];
                        };

                        switch (param.type) {
                            .string, .bytes => return try encodeString(allocator, slice),
                            inline else => return error.InvalidParamType,
                        }
                    }

                    switch (param.type) {
                        .dynamicArray => |val| {
                            const new_parameter: AbiParameter = .{
                                .type = val.*,
                                .name = param.name,
                                .internalType = param.internalType,
                                .components = param.components,
                            };

                            return try encodeArray(allocator, new_parameter, value, null);
                        },
                        else => return error.InvalidParamType,
                    }
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
            }
        },
        .bool => {
            return switch (param.type) {
                .bool => try encodeBool(allocator, value),
                inline else => return error.InvalidParamType,
            };
        },
        .int => {
            return switch (info.int.signedness) {
                .signed => try encodeNumber(allocator, i256, value),
                .unsigned => try encodeNumber(allocator, u256, value),
            };
        },
        .comptime_int => {
            return switch (param.type) {
                .int => try encodeNumber(allocator, i256, value),
                .uint => try encodeNumber(allocator, u256, value),
                inline else => error.InvalidParamType,
            };
        },
        .@"struct" => {
            return switch (param.type) {
                .tuple => try encodeTuples(allocator, param, value),
                inline else => error.InvalidParamType,
            };
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                switch (arr_info.len) {
                    1...19, 21...32 => {
                        switch (param.type) {
                            .fixedBytes => |size| {
                                if (size != arr_info.len)
                                    return error.InvalidLength;

                                return try encodeFixedBytes(allocator, &value);
                            },
                            else => return error.InvalidParamType,
                        }
                    },
                    20 => {
                        switch (param.type) {
                            .fixedBytes => |size| {
                                if (size != arr_info.len)
                                    return error.InvalidLength;

                                return try encodeFixedBytes(allocator, &value);
                            },
                            .address => return try encodeAddress(allocator, value),
                            else => return error.InvalidParamType,
                        }
                    },
                    else => {
                        const slice: []const u8 = slice: {
                            if (std.mem.startsWith(u8, value[0..], "0x")) {
                                break :slice value[2..];
                            }

                            break :slice value[0..];
                        };

                        return switch (param.type) {
                            .string => try encodeString(allocator, slice),
                            .bytes => {
                                const buffer = try allocator.alloc(u8, if (slice.len % 32 == 0) @divExact(slice.len, 2) else slice.len);
                                const hex = try std.fmt.hexToBytes(buffer, slice);

                                return try encodeString(allocator, hex);
                            },
                            inline else => return error.InvalidParamType,
                        };
                    },
                }
            }
            return switch (param.type) {
                .fixedArray => |val| {
                    const new_parameter: AbiParameter = .{
                        .type = val.child.*,
                        .name = param.name,
                        .internalType = param.internalType,
                        .components = param.components,
                    };
                    return try encodeArray(allocator, new_parameter, value, val.size);
                },
                else => return error.InvalidParamType,
            };
        },

        else => @compileError(@typeName(@TypeOf(value)) ++ " type is not supported"),
    }
}

fn encodeNumber(allocator: Allocator, comptime T: type, num: T) !PreEncodedParam {
    if (num > std.math.maxInt(T))
        return error.Overflow;

    var buffer = try allocator.alloc(u8, 32);
    std.mem.writeInt(T, buffer[0..32], num, .big);

    return .{ .dynamic = false, .encoded = buffer };
}

fn encodeAddress(allocator: Allocator, addr: Address) !PreEncodedParam {
    var padded = try allocator.alloc(u8, 32);

    @memset(padded, 0);
    @memcpy(padded[12..], addr[0..]);

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeBool(allocator: Allocator, b: bool) !PreEncodedParam {
    var padded = try allocator.alloc(u8, 32);

    @memset(padded, 0);
    padded[padded.len - 1] = @intFromBool(b);

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeString(allocator: Allocator, str: []const u8) !PreEncodedParam {
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(str.len))) / 32);

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var writer = list.writer();
    try writer.writeInt(u256, str.len, .big);

    var buffer = try allocator.alloc(u8, (ceil + 1) * 32);
    defer allocator.free(buffer);

    @memset(buffer[0..], 0);
    @memcpy(buffer[0..str.len], str);
    try writer.writeAll(buffer);

    return .{ .dynamic = true, .encoded = try list.toOwnedSlice() };
}

fn encodeFixedBytes(allocator: Allocator, bytes: []const u8) !PreEncodedParam {
    var buffer = try allocator.alloc(u8, 32);

    @memset(buffer, 0);
    @memcpy(buffer[0..bytes.len], bytes);

    return .{ .dynamic = false, .encoded = buffer };
}

fn encodeArray(allocator: Allocator, param: AbiParameter, values: anytype, size: ?usize) !PreEncodedParam {
    assert(values.len > 0);
    const dynamic = size == null;

    var list = std.ArrayList(PreEncodedParam).init(allocator);

    var has_dynamic = false;

    for (values) |value| {
        const pre = try preEncodeParam(allocator, param, value);

        if (pre.dynamic) has_dynamic = true;
        try list.append(pre);
    }

    if (dynamic or has_dynamic) {
        const slices = try list.toOwnedSlice();
        const hex = try encodeParameters(allocator, slices);

        if (dynamic) {
            const len = try encodeNumber(allocator, u256, slices.len);
            const enc = if (slices.len > 0) try std.mem.concat(allocator, u8, &.{ len.encoded, hex }) else len.encoded;

            return .{ .dynamic = true, .encoded = enc };
        }

        if (has_dynamic) return .{ .dynamic = true, .encoded = hex };
    }

    const concated = try concatPreEncodedStruct(allocator, try list.toOwnedSlice());

    return .{ .dynamic = false, .encoded = concated };
}

fn encodeTuples(allocator: Allocator, param: AbiParameter, values: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(values)).@"struct";
    if (info.is_tuple)
        @compileError("Expected normal struct type but found tuple instead");

    assert(info.fields.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(allocator);

    var has_dynamic = false;

    if (param.components) |components| {
        for (components) |component| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, component.name, field.name)) {
                    const pre = try preEncodeParam(allocator, component, @field(values, field.name));
                    if (pre.dynamic) has_dynamic = true;
                    try list.append(pre);
                }
            }
        }
    } else return error.InvalidParamType;

    const encoded = if (has_dynamic)
        try encodeParameters(allocator, try list.toOwnedSlice())
    else
        try concatPreEncodedStruct(allocator, try list.toOwnedSlice());

    return .{ .dynamic = has_dynamic, .encoded = encoded };
}

fn concatPreEncodedStruct(allocator: Allocator, slices: []PreEncodedParam) ![]u8 {
    const len = sum: {
        var sum: usize = 0;
        for (slices) |slice| {
            sum += slice.encoded.len;
        }

        break :sum sum;
    };

    var buffer = try allocator.alloc(u8, len);

    var index: usize = 0;
    for (slices) |slice| {
        @memcpy(buffer[index .. index + slice.encoded.len], slice.encoded);
        index += slice.encoded.len;
    }

    return buffer;
}
