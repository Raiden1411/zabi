const std = @import("std");
const abi = @import("../abi/abi_parameter.zig");
const meta = @import("../meta/meta.zig");
const testing = std.testing;
const types = @import("../meta/ethereum.zig");
const utils = @import("../utils.zig");
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

pub const EncodeErrors = std.mem.Allocator.Error || error{ InvalidIntType, Overflow, BufferExceedsMaxSize, InvalidBits, InvalidLength, NoSpaceLeft, InvalidCharacter, InvalidParamType };

pub const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
};

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

    if (fields != .Struct or !fields.Struct.is_tuple)
        @compileError("Expected " ++ @typeName(@TypeOf(values)) ++ " to be a tuple value instead");

    const prepared = try preEncodeParams(alloc, params, values);
    const data = try encodeParameters(alloc, prepared);

    return data;
}

fn encodeParameters(allocator: Allocator, params: []PreEncodedParam) ![]u8 {
    const s_size: usize = params.len * 32;

    var list_dynamic = std.ArrayList(u8).init(allocator);
    errdefer list_dynamic.deinit();

    var list_static = std.ArrayList(u8).init(allocator);
    errdefer list_static.deinit();

    var dynamic_writer = list_dynamic.writer();
    var static_writer = list_static.writer();

    var d_size: usize = 0;
    for (params) |param| {
        if (param.dynamic) {
            try static_writer.writeInt(u256, s_size + d_size, .big);
            try dynamic_writer.writeAll(param.encoded);

            d_size += param.encoded.len;
        } else {
            try static_writer.writeAll(param.encoded);
        }
    }

    const slice = try list_dynamic.toOwnedSlice();
    defer allocator.free(slice);

    try static_writer.writeAll(slice);

    return try list_static.toOwnedSlice();
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
        .Pointer => |ptr_info| {
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

                        return switch (param.type) {
                            .string, .bytes => try encodeString(allocator, slice),
                            inline else => return error.InvalidParamType,
                        };
                    }

                    switch (param.type) {
                        .dynamicArray => |val| {
                            // zig fmt: off
                            const new_parameter: AbiParameter = .{
                                .type = val.*,
                                .name = param.name,
                                .internalType = param.internalType,
                                .components = param.components
                            };
                            // zig fmt: on

                            return try encodeArray(allocator, new_parameter, value, null);
                        },
                        else => return error.InvalidParamType,
                    }
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
            }
        },
        .Bool => {
            return switch (param.type) {
                .bool => try encodeBool(allocator, value),
                inline else => return error.InvalidParamType,
            };
        },
        .Int => {
            return switch (info.Int.signedness) {
                .signed => try encodeNumber(allocator, i256, value),
                .unsigned => try encodeNumber(allocator, u256, value),
            };
        },
        .ComptimeInt => {
            return switch (param.type) {
                .int => try encodeNumber(allocator, i256, value),
                .uint => try encodeNumber(allocator, u256, value),
                inline else => error.InvalidParamType,
            };
        },
        .Struct => {
            return switch (param.type) {
                .tuple => try encodeTuples(allocator, param, value),
                inline else => error.InvalidParamType,
            };
        },
        .Array => |arr_info| {
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
                            .string, .bytes => try encodeString(allocator, slice),
                            inline else => return error.InvalidParamType,
                        };
                    },
                }
            }
            return switch (param.type) {
                .fixedArray => |val| {
                    // zig fmt: off
                    const new_parameter: AbiParameter = .{
                        .type = val.child.*,
                        .name = param.name,
                        .internalType = param.internalType,
                        .components = param.components
                    };
                    // zig fmt: on
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
    const info = @typeInfo(@TypeOf(values)).Struct;
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

test "Bool" {
    try testEncode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{true});
    try testEncode("0000000000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{false});
}

test "Uint/Int" {
    try testEncode("0000000000000000000000000000000000000000000000000000000000000005", &.{.{ .type = .{ .uint = 8 }, .name = "foo" }}, .{5});
    try testEncode("0000000000000000000000000000000000000000000000000000000000010f2c", &.{.{ .type = .{ .uint = 256 }, .name = "foo" }}, .{69420});
    try testEncode("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb", &.{.{ .type = .{ .int = 256 }, .name = "foo" }}, .{-5});
    try testEncode("fffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a432eb", &.{.{ .type = .{ .int = 64 }, .name = "foo" }}, .{-123456789});
}

test "Address" {
    try testEncode("0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x4648451b5F87FF8F0F7D622bD40574bb97E25980")});
    try testEncode("000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x388C818CA8B9251b393131C08a736A67ccB19297")});
}

test "Fixed Bytes" {
    try testEncode("0123456789000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 5 }, .name = "foo" }}, .{[5]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 }});
    try testEncode("0123456789000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 10 }, .name = "foo" }}, .{[5]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 } ++ [_]u8{0x00} ** 5});
}

test "Bytes/String" {
    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .{"foo"});
    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .bytes = {} }, .name = "foo" }}, .{"foo"});
}

test "Arrays" {
    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &ParamType{ .int = 256 } }, .name = "foo" }}, .{&[_]i256{ 4, 2, 0 }});

    try testEncode("00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .int = 256 }, .size = 2 } }, .name = "foo" }}, .{[2]i256{ 4, 2 }});
    try testEncode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .name = "foo" }}, .{[2][]const u8{ "foo", "bar" }});
    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }}, .{&[_][]const u8{ "foo", "bar" }});
    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626172000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000362617a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .size = 3 } }, .name = "foo" }}, .{[3][2][]const u8{ .{ "foo", "bar" }, .{ "baz", "boo" }, .{ "fizz", "buzz" } }});
    try testEncode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000666697a7a7a7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000362757a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000662757a7a7a7a0000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .dynamicArray = &.{ .string = {} } }, .size = 2 } }, .name = "foo" }}, .{[2][]const []const u8{ &.{ "foo", "bar", "fizzzz", "buz" }, &.{ "fizz", "buzz", "buzzzz" } }});
}

test "Tuples" {
    try testEncode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }}, .{.{ .bar = true }});
    try testEncode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }}, .{.{ .bar = .{ .baz = true } }});
    try testEncode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{.{ .bar = true, .baz = 69, .fizz = "buzz" }});
    try testEncode("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{&.{.{ .bar = true, .baz = 69, .fizz = "buzz" }}});
}

test "Multiple" {
    try testEncode("0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000001a40000000000000000000000000000000000000000000000000000000000010f2c", &.{ .{ .type = .{ .uint = 256 }, .name = "foo" }, .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .int = 120 } }, .name = "baz" } }, .{ 69, true, &[_]i120{ 69, 420, 69420 } });

    const params: []const AbiParameter = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }};

    try testEncode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000a45500000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001c666f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f00000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018424f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f00000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009", params, .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }});

    const none = try encodeAbiParameters(testing.allocator, &.{}, .{});
    defer none.deinit();

    try testing.expectEqualStrings("", none.data);
}

test "Errors" {
    try testing.expectError(error.InvalidParamType, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .fixedBytes = 5 }, .name = "foo" }}, .{true}));
    try testing.expectError(error.InvalidParamType, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .int = 5 }, .name = "foo" }}, .{true}));
    try testing.expectError(error.InvalidParamType, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .tuple = {} }, .name = "foo" }}, .{.{ .bar = "foo" }}));
    try testing.expectError(error.InvalidParamType, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .uint = 5 }, .name = "foo" }}, .{"foo"}));
    try testing.expectError(error.InvalidParamType, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .{[_][]const u8{"foo"}}));
    try testing.expectError(error.InvalidLength, encodeAbiParameters(testing.allocator, &.{.{ .type = .{ .fixedBytes = 55 }, .name = "foo" }}, .{"foo"}));
}

test "Selectors" {
    _ = @import("selector_test.zig");
}

fn testEncode(expected: []const u8, comptime params: []const AbiParameter, values: AbiParametersToPrimative(params)) !void {
    const encoded = try encodeAbiParametersComptime(testing.allocator, params, values);
    defer encoded.deinit();

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded.data)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings(expected, hex);
}
