const std = @import("std");
const abi = @import("abi_parameter.zig");
const ParamType = @import("param_type.zig").ParamType;

const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
};

fn ParamTypeToPrimativeType(comptime param_type: ParamType) type {
    return switch (param_type) {
        .string, .bytes, .address => []const u8,
        .bool => bool,
        .fixedBytes => []const u8,
        .int => i256,
        .uint => u256,
        .dynamicArray => []const ParamTypeToPrimativeType(param_type.dynamicArray.*),
        .fixedArray => [param_type.fixedArray.size]ParamTypeToPrimativeType(param_type.fixedArray.child.*),
        inline else => void,
    };
}
pub fn AbiParameterToPrimative(comptime param: abi.AbiParameter) type {
    const PrimativeType = ParamTypeToPrimativeType(param.type);

    if (PrimativeType == void) {
        if (param.components) |components| {
            var fields: [components.len]std.builtin.Type.StructField = undefined;
            for (components, 0..) |component, i| {
                const FieldType = AbiParameterToPrimative(component);
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = FieldType,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = if (@sizeOf(FieldType) > 0) @alignOf(FieldType) else 0,
                };
            }

            return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
        } else @compileError("Expected components to not be null");
    }
    return PrimativeType;
}

pub fn AbiParametersToPrimative(comptime paramters: []const abi.AbiParameter) type {
    var fields: [paramters.len]std.builtin.Type.StructField = undefined;

    for (paramters, 0..) |paramter, i| {
        const FieldType = AbiParameterToPrimative(paramter);

        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = FieldType,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(FieldType) > 0) @alignOf(FieldType) else 0,
        };
    }
    return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}

const EncodeErrors = std.mem.Allocator.Error || error{ InvalidIntType, Overflow, BufferExceedsMaxSize, InvalidBits, InvalidLength, NoSpaceLeft, InvalidCharacter };

const Params = union(enum) {
    bool: bool,
    uint: u256,
    int: i256,
    fixedBytes: struct {
        size: usize,
        data: []const u8,
    },
    bytes: []const u8,
    address: []const u8,
    string: []const u8,
    tuple: []const Params,
    fixedArray: struct { size: usize, child: []const Params },
    dynamicArray: []const Params,
};

pub const AbiEncoded = struct {
    arena: *std.heap.ArenaAllocator,
    data: []u8,

    pub fn deinit(self: @This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();

        allocator.destroy(self.arena);
    }
};

pub fn encodeAbiParameters(alloc: std.mem.Allocator, comptime parameters: []const abi.AbiParameter, values: AbiParametersToPrimative(parameters)) !AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(std.heap.ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = std.heap.ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, parameters, values);

    return abi_encoded;
}

pub fn encodeAbiParametersLeaky(alloc: std.mem.Allocator, comptime params: []const abi.AbiParameter, values: AbiParametersToPrimative(params)) ![]u8 {
    if (params.len == 0) return "";

    const prepared = try preEncodeParams(params, values, alloc);
    const data = try encodeParameters(prepared, alloc);

    return data;
}

fn encodeParameters(params: []PreEncodedParam, alloc: std.mem.Allocator) ![]u8 {
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
            const size = try encodeNumber(u256, s_size + d_size, alloc);
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

fn preEncodeParams(comptime params: []const abi.AbiParameter, values: AbiParametersToPrimative(params), alloc: std.mem.Allocator) ![]PreEncodedParam {
    std.debug.assert(params.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    inline for (params, values) |param, value| {
        const pre_encoded = try preEncodeParam(param, value, alloc);
        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

fn preEncodeParam(comptime param: abi.AbiParameter, value: anytype, alloc: std.mem.Allocator) !PreEncodedParam {
    // return switch (param.type) {
    //     .string, .bytes => try encodeString(value, alloc),
    //     .address => try encodeAddress(value, alloc),
    //     .fixedBytes => |val| try encodeFixedBytes(val, value, alloc),
    //     .int => try encodeNumber(i256, value, alloc),
    //     .uint => try encodeNumber(u256, value, alloc),
    //     .bool => try encodeBool(value, alloc),
    //     .dynamicArray => try encodeArray(alloc, param, value,  null),
    //     .fixedArray => |val| try encodeArray(alloc, val.child, val.size),
    //     .tuple => |val| try encodeTuples(alloc, val),
    // };
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Pointer => {
            if (info.Pointer.size != .Slice and info.Pointer.size != .One) @compileError("Invalid Pointer size. Expected Slice or comptime know string");

            switch (info.Pointer.child) {
                u8 => return switch (param.type) {
                    .string, .bytes => try encodeString(value, alloc),
                    .fixedBytes => |val| try encodeFixedBytes(val, value, alloc),
                    .address => try encodeAddress(value, alloc),
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
                .bool => try encodeBool(value, alloc),
                inline else => return error.InvalidParamType,
            };
        },
        .Int => {
            return switch (info.Int.signedness) {
                .signed => try encodeNumber(i256, value, alloc),
                .unsigned => try encodeNumber(u256, value, alloc),
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

fn encodeNumber(comptime T: type, num: T, alloc: std.mem.Allocator) !PreEncodedParam {
    const info = @typeInfo(T);
    if (info != .Int) return error.InvalidIntType;
    if (num > std.math.maxInt(T)) return error.Overflow;

    var buffer = try alloc.alloc(u8, 32);
    std.mem.writeInt(T, buffer[0..32], num, .big);

    return .{ .dynamic = false, .encoded = buffer };
}

fn encodeAddress(addr: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    var addr_bytes: [20]u8 = undefined;
    var padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    std.mem.copyForwards(u8, padded[12..], try std.fmt.hexToBytes(&addr_bytes, addr[2..]));

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeBool(b: bool, alloc: std.mem.Allocator) !PreEncodedParam {
    var padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    padded[padded.len - 1] = @intFromBool(b);

    return .{ .dynamic = false, .encoded = padded };
}

fn encodeString(str: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    const hex = std.fmt.fmtSliceHexLower(str);
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(hex.data.len))) / 32);

    var list = std.ArrayList([]u8).init(alloc);
    const size = try encodeNumber(u256, str.len, alloc);

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

fn encodeFixedBytes(size: usize, bytes: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    if (size > 32) return error.InvalidBits;
    if (bytes.len > size) return error.Overflow;

    return .{ .dynamic = false, .encoded = try zeroPad(alloc, bytes) };
}

fn encodeArray(alloc: std.mem.Allocator, comptime param: abi.AbiParameter, values: anytype, size: ?usize) !PreEncodedParam {
    const dynamic = size == null;

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;

    for (values) |value| {
        const pre = try preEncodeParam(param, value, alloc);

        if (pre.dynamic) has_dynamic = true;
        try list.append(pre);
    }

    if (dynamic or has_dynamic) {
        const slices = try list.toOwnedSlice();
        const hex = try encodeParameters(slices, alloc);

        if (dynamic) {
            const len = try encodeNumber(u256, slices.len, alloc);
            const enc = if (slices.len > 0) try std.mem.concat(alloc, u8, &.{ len.encoded, hex }) else len.encoded;

            return .{ .dynamic = true, .encoded = enc };
        }

        if (has_dynamic) return .{ .dynamic = true, .encoded = hex };
    }

    const concated = try concatPreEncodedStruct(try list.toOwnedSlice(), alloc);

    return .{ .dynamic = false, .encoded = concated };
}

fn encodeTuples(alloc: std.mem.Allocator, comptime param: abi.AbiParameter, values: AbiParameterToPrimative(param)) !PreEncodedParam {
    std.debug.assert(values.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;

    if (param.components) |components| {
        inline for (components, values) |component, value| {
            const pre = try preEncodeParam(component, value, alloc);

            if (pre.dynamic) has_dynamic = true;
            try list.append(pre);
        }
    } else return error.InvalidParamType;

    return .{ .dynamic = has_dynamic, .encoded = if (has_dynamic) try encodeParameters(try list.toOwnedSlice(), alloc) else try concatPreEncodedStruct(try list.toOwnedSlice(), alloc) };
}

fn concatPreEncodedStruct(slices: []PreEncodedParam, alloc: std.mem.Allocator) ![]u8 {
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

fn zeroPad(alloc: std.mem.Allocator, buf: []const u8) ![]u8 {
    if (buf.len > 32) return error.BufferExceedsMaxSize;
    const padded = try alloc.alloc(u8, 32);

    @memset(padded, 0);
    std.mem.copyBackwards(u8, padded, buf);

    return padded;
}

test "fooo" {
    const pre_encoded = try encodeAbiParameters(std.testing.allocator, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{ .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .bool = {} }, .name = "baz" }, .{ .type = .{ .address = {} }, .name = "boo" } } }}, .{.{ 420, true, "0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC" }});
    defer pre_encoded.deinit();

    std.debug.print("Foo: {s}\n", .{std.fmt.fmtSliceHexLower(pre_encoded.data)});
}
