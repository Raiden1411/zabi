const std = @import("std");
const abi = @import("abi_parameter.zig");
const assert = std.debug.assert;
const AbiParameterToPrimative = @import("types.zig").AbiParameterToPrimative;
const AbiParametersToPrimative = @import("types.zig").AbiParametersToPrimative;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Constructor = @import("abi.zig").Constructor;
const Error = @import("abi.zig").Error;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Function = @import("abi.zig").Function;
const ParamType = @import("param_type.zig").ParamType;

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

pub fn encodeAbiConstructorComptime(alloc: Allocator, comptime constructor: Constructor, values: AbiParametersToPrimative(constructor.inputs)) EncodeErrors![]u8 {
    const encoded_params = try encodeAbiParametersComptime(alloc, constructor.inputs, values);
    defer encoded_params.deinit();

    const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
    defer alloc.free(hexed);

    return hexed;
}

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

pub fn encodeAbiParameters(alloc: Allocator, parameters: []const abi.AbiParameter, values: anytype) EncodeErrors!AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, parameters, values);

    return abi_encoded;
}

pub fn encodeAbiParametersLeaky(alloc: Allocator, params: []const abi.AbiParameter, values: anytype) EncodeErrors![]u8 {
    const prepared = try preEncodeParams(alloc, params, values);
    const data = try encodeParameters(alloc, prepared);

    return data;
}

pub fn encodeAbiParametersComptime(alloc: Allocator, comptime parameters: []const abi.AbiParameter, values: AbiParametersToPrimative(parameters)) EncodeErrors!AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, parameters, values);

    return abi_encoded;
}

pub fn encodeAbiParametersLeakyComptime(alloc: Allocator, comptime params: []const abi.AbiParameter, values: AbiParametersToPrimative(params)) EncodeErrors![]u8 {
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

fn preEncodeParams(alloc: Allocator, params: []const abi.AbiParameter, values: anytype) ![]PreEncodedParam {
    assert(params.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    inline for (params, values) |param, value| {
        const pre_encoded = try preEncodeParam(alloc, param, value);
        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

fn preEncodeParam(alloc: Allocator, param: abi.AbiParameter, value: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Pointer => {
            if (info.Pointer.size != .Slice and info.Pointer.size != .One) @compileError("Invalid Pointer size. Expected Slice or comptime know string");

            return switch (param.type) {
                .string, .bytes => try encodeString(alloc, value),
                .fixedBytes => |val| try encodeFixedBytes(alloc, val, value),
                .address => try encodeAddress(alloc, value),
                .dynamicArray => |val| try encodeArray(alloc, .{ .type = val.*, .name = param.name, .internalType = param.internalType, .components = param.components }, value, null),
                inline else => return error.InvalidParamType,
            };
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
    const info = @typeInfo(T);
    if (info != .Int) return error.InvalidIntType;
    if (num > std.math.maxInt(T)) return error.Overflow;

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
    if (size > 32) return error.InvalidBits;
    if (bytes.len > size) return error.Overflow;

    return .{ .dynamic = false, .encoded = try zeroPad(alloc, bytes) };
}

fn encodeArray(alloc: Allocator, param: abi.AbiParameter, values: anytype, size: ?usize) !PreEncodedParam {
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

fn encodeTuples(alloc: std.mem.Allocator, param: abi.AbiParameter, values: anytype) !PreEncodedParam {
    std.debug.assert(values.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;

    if (param.components) |components| {
        inline for (components, values) |component, value| {
            const pre = try preEncodeParam(alloc, component, value);

            if (pre.dynamic) has_dynamic = true;
            try list.append(pre);
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
    if (buf.len > 32) return error.BufferExceedsMaxSize;
    const padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    std.mem.copyBackwards(u8, padded, buf);

    return padded;
}

test "fooo" {
    // const pre_encoded = try encodeAbiParameters(std.testing.allocator, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{ .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .bool = {} }, .name = "baz" }, .{ .type = .{ .address = {} }, .name = "boo" } } }}, .{.{ 420, true, "0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC" }});
    // defer pre_encoded.deinit();
    //
    // std.debug.print("Foo: {s}\n", .{std.fmt.fmtSliceHexLower(pre_encoded.data)});

    const function: Function = .{ .type = .function, .name = "bar", .stateMutability = .nonpayable, .inputs = &.{.{ .name = "a", .type = .{ .uint = 256 } }}, .outputs = &.{} };

    const encoded = try encodeAbiFunctionComptime(std.testing.allocator, function, .{1});
    defer std.testing.allocator.free(encoded);
    std.debug.print("FOOO: {s}\n", .{encoded});
}
