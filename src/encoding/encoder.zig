const std = @import("std");
const abi = @import("../abi/abi_parameter.zig");
const meta = @import("../meta/meta.zig");
const testing = std.testing;
const assert = std.debug.assert;

/// Types
const AbiParameter = abi.AbiParameter;
const AbiParameterToPrimative = meta.AbiParameterToPrimative;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
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
pub fn encodeAbiConstructorComptime(alloc: Allocator, comptime constructor: Constructor, values: AbiParametersToPrimative(constructor.inputs)) EncodeErrors![]u8 {
    const encoded_params = try encodeAbiParametersComptime(alloc, constructor.inputs, values);
    defer encoded_params.deinit();

    const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
    defer alloc.free(hexed);

    return hexed;
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiErrorComptime(alloc: Allocator, comptime err: Error, values: AbiParametersToPrimative(err.inputs)) EncodeErrors![]u8 {
    const prep_signature = try err.allocPrepare(alloc);
    defer alloc.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    const encoded_params = try encodeAbiParametersComptime(alloc, err.inputs, values);
    defer encoded_params.deinit();

    const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
    defer alloc.free(hexed);

    const buffer = try alloc.alloc(u8, 8 + hexed.len);

    @memcpy(buffer[0..8], hash_hex[0..8]);
    @memcpy(buffer[8..], hexed);

    return buffer;
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiFunctionComptime(alloc: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.inputs)) EncodeErrors![]u8 {
    const prep_signature = try function.allocPrepare(alloc);
    defer alloc.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    const encoded_params = try encodeAbiParametersComptime(alloc, function.inputs, values);
    defer encoded_params.deinit();

    const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
    defer alloc.free(hexed);

    const buffer = try alloc.alloc(u8, 8 + hexed.len);

    @memcpy(buffer[0..8], hash_hex[0..8]);
    @memcpy(buffer[8..], hexed);

    return buffer;
}
/// Encode the struct signature based on the values provided.
/// Caller owns the memory.
pub fn encodeAbiFunctionOutputsComptime(alloc: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.outputs)) EncodeErrors![]u8 {
    const prep_signature = try function.allocPrepare(alloc);
    defer alloc.free(prep_signature);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prep_signature, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    const encoded_params = try encodeAbiParametersComptime(alloc, function.outputs, values);
    defer encoded_params.deinit();

    const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
    defer alloc.free(hexed);

    const buffer = try alloc.alloc(u8, 8 + hexed.len);

    @memcpy(buffer[0..8], hash_hex[0..8]);
    @memcpy(buffer[8..], hexed);

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
    if (fields != .Struct)
        @compileError("Expected " ++ @typeName(@TypeOf(values)) ++ " to be a tuple value instead");

    if (!fields.Struct.is_tuple)
        @compileError("Expected " ++ @typeName(@TypeOf(values)) ++ " to be a tuple value instead");

    const prepared = try preEncodeParams(alloc, params, values);
    const data = try encodeParameters(alloc, prepared);

    return data;
}

fn encodeParameters(alloc: Allocator, params: []PreEncodedParam) ![]u8 {
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
            const size = try encodeNumber(alloc, u256, s_size + d_size);
            try list.append(alloc, .{ .static = size.encoded, .dynamic = param.encoded });

            d_size += param.encoded.len;
        } else {
            try list.append(alloc, .{ .static = param.encoded, .dynamic = "" });
        }
    }

    const static = try std.mem.concat(alloc, u8, list.items(.static));
    const dynamic = try std.mem.concat(alloc, u8, list.items(.dynamic));
    const concated = try std.mem.concat(alloc, u8, &.{ static, dynamic });

    return concated;
}

fn preEncodeParams(alloc: Allocator, params: []const AbiParameter, values: anytype) ![]PreEncodedParam {
    assert(params.len == values.len);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    inline for (params, values) |param, value| {
        const pre_encoded = try preEncodeParam(alloc, param, value);
        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

fn preEncodeParam(alloc: Allocator, param: AbiParameter, value: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Pointer => {
            if (info.Pointer.size != .Slice and info.Pointer.size != .One)
                @compileError("Invalid Pointer size. Expected Slice or comptime know string");

            if (info.Pointer.size == .One) {
                return switch (param.type) {
                    .string, .bytes => try encodeString(alloc, value),
                    .fixedBytes => |val| try encodeFixedBytes(alloc, val, value),
                    .address => try encodeAddress(alloc, value),
                    inline else => return error.InvalidParamType,
                };
            }

            switch (info.Pointer.child) {
                u8 => return switch (param.type) {
                    .string, .bytes => try encodeString(alloc, value),
                    .fixedBytes => |val| try encodeFixedBytes(alloc, val, value),
                    .address => try encodeAddress(alloc, value),
                    inline else => return error.InvalidParamType,
                },
                inline else => return switch (param.type) {
                    .dynamicArray => |val| try encodeArray(alloc, .{ .type = val.*, .name = param.name, .internalType = param.internalType, .components = param.components }, value, null),
                    inline else => return error.InvalidParamType,
                },
            }
        },
        .Bool => {
            return switch (param.type) {
                .bool => try encodeBool(alloc, value),
                inline else => return error.InvalidParamType,
            };
        },
        .Int => {
            return switch (info.Int.signedness) {
                .signed => try encodeNumber(alloc, i256, value),
                .unsigned => try encodeNumber(alloc, u256, value),
            };
        },
        .ComptimeInt => {
            return switch (param.type) {
                .int => try encodeNumber(alloc, i256, value),
                .uint => try encodeNumber(alloc, u256, value),
                inline else => error.InvalidParamType,
            };
        },
        .Struct => {
            return switch (param.type) {
                .tuple => try encodeTuples(alloc, param, value),
                inline else => error.InvalidParamType,
            };
        },
        .Array => {
            return switch (param.type) {
                .fixedArray => |val| try encodeArray(alloc, .{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }, value, val.size),
                inline else => error.InvalidParamType,
            };
        },

        inline else => @compileError(@typeName(@TypeOf(value)) ++ " type is not supported"),
    }
}

fn encodeNumber(alloc: Allocator, comptime T: type, num: T) !PreEncodedParam {
    if (num > std.math.maxInt(T))
        return error.Overflow;

    var buffer = try alloc.alloc(u8, 32);
    std.mem.writeInt(T, buffer[0..32], num, .big);

    return .{ .dynamic = false, .encoded = buffer };
}

fn encodeAddress(alloc: Allocator, addr: []const u8) !PreEncodedParam {
    var addr_bytes: [20]u8 = undefined;
    var padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    std.mem.copyForwards(u8, padded[12..], try std.fmt.hexToBytes(&addr_bytes, addr[2..]));

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeBool(alloc: Allocator, b: bool) !PreEncodedParam {
    var padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    padded[padded.len - 1] = @intFromBool(b);

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeString(alloc: Allocator, str: []const u8) !PreEncodedParam {
    const hex = std.fmt.fmtSliceHexLower(str);
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(hex.data.len))) / 32);

    var list = std.ArrayList([]u8).init(alloc);
    const size = try encodeNumber(alloc, u256, str.len);

    try list.append(size.encoded);

    var i: usize = 0;
    while (ceil >= i) : (i += 1) {
        const start = i * 32;
        const end = (i + 1) * 32;

        const buf = try zeroPad(alloc, hex.data[start..if (end > hex.data.len) hex.data.len else end]);

        try list.append(buf);
    }

    return .{ .dynamic = true, .encoded = try std.mem.concat(alloc, u8, try list.toOwnedSlice()) };
}

fn encodeFixedBytes(alloc: Allocator, size: usize, bytes: []const u8) !PreEncodedParam {
    var buffer: [32]u8 = undefined;
    const byts = try std.fmt.hexToBytes(&buffer, bytes);

    if (byts.len > 32)
        return error.InvalidBits;

    if (byts.len > size)
        return error.Overflow;

    return .{ .dynamic = false, .encoded = try zeroPad(alloc, byts) };
}

fn encodeArray(alloc: Allocator, param: AbiParameter, values: anytype, size: ?usize) !PreEncodedParam {
    assert(values.len > 0);
    const dynamic = size == null;

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;

    for (values) |value| {
        const pre = try preEncodeParam(alloc, param, value);

        if (pre.dynamic) has_dynamic = true;
        try list.append(pre);
    }

    if (dynamic or has_dynamic) {
        const slices = try list.toOwnedSlice();
        const hex = try encodeParameters(alloc, slices);

        if (dynamic) {
            const len = try encodeNumber(alloc, u256, slices.len);
            const enc = if (slices.len > 0) try std.mem.concat(alloc, u8, &.{ len.encoded, hex }) else len.encoded;

            return .{ .dynamic = true, .encoded = enc };
        }

        if (has_dynamic) return .{ .dynamic = true, .encoded = hex };
    }

    const concated = try concatPreEncodedStruct(alloc, try list.toOwnedSlice());

    return .{ .dynamic = false, .encoded = concated };
}

fn encodeTuples(alloc: std.mem.Allocator, param: AbiParameter, values: anytype) !PreEncodedParam {
    const fields = @typeInfo(@TypeOf(values)).Struct.fields;
    assert(fields.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;

    if (param.components) |components| {
        for (components) |component| {
            inline for (fields) |field| {
                if (std.mem.eql(u8, component.name, field.name)) {
                    const pre = try preEncodeParam(alloc, component, @field(values, field.name));
                    if (pre.dynamic) has_dynamic = true;
                    try list.append(pre);
                }
            }
        }
    } else return error.InvalidParamType;

    return .{ .dynamic = has_dynamic, .encoded = if (has_dynamic) try encodeParameters(alloc, try list.toOwnedSlice()) else try concatPreEncodedStruct(alloc, try list.toOwnedSlice()) };
}

fn concatPreEncodedStruct(alloc: Allocator, slices: []PreEncodedParam) ![]u8 {
    const len = sum: {
        var sum: usize = 0;
        for (slices) |slice| {
            sum += slice.encoded.len;
        }

        break :sum sum;
    };

    var buffer = try alloc.alloc(u8, len);

    var index: usize = 0;
    for (slices) |slice| {
        @memcpy(buffer[index .. index + slice.encoded.len], slice.encoded);
        index += slice.encoded.len;
    }

    return buffer;
}

fn zeroPad(alloc: Allocator, buf: []const u8) ![]u8 {
    const padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    std.mem.copyBackwards(u8, padded, buf);

    return padded;
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
    try testEncode("0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{"0x4648451b5F87FF8F0F7D622bD40574bb97E25980"});
    try testEncode("000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{"0x388C818CA8B9251b393131C08a736A67ccB19297"});
}

test "Fixed Bytes" {
    try testEncode("0123456789000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 5 }, .name = "foo" }}, .{"0123456789"});
    try testEncode("0123456789000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 10 }, .name = "foo" }}, .{"0123456789"});
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
