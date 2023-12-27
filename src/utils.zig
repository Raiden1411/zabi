const std = @import("std");
const ParamType = @import("param_type.zig").ParamType;

const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
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

pub fn encodeAbiParameters(alloc: std.mem.Allocator, params: []const ParamType, values: anytype) !AbiEncoded {
    var abi_encoded = AbiEncoded{ .arena = try alloc.create(std.heap.ArenaAllocator), .data = undefined };
    errdefer alloc.destroy(abi_encoded.arena);

    abi_encoded.arena.* = std.heap.ArenaAllocator.init(alloc);
    errdefer abi_encoded.arena.deinit();

    const allocator = abi_encoded.arena.allocator();
    abi_encoded.data = try encodeAbiParametersLeaky(allocator, params, values);

    return abi_encoded;
}

pub fn encodeAbiParametersLeaky(alloc: std.mem.Allocator, params: []const ParamType, values: anytype) ![]u8 {
    if (params.len != values.len) return error.LengthMismatch;

    const prepared = try preEncodeParams(params, alloc, values);
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

fn preEncodeParams(params: []const ParamType, alloc: std.mem.Allocator, values: anytype) ![]PreEncodedParam {
    std.debug.assert(values.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    for (values, params) |value, param| {
        const pre_encoded = try preEncodeParam(param, alloc, value);
        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

fn preEncodeParam(param: ParamType, alloc: std.mem.Allocator, value: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Pointer => {
            if (info.Pointer.size != .Slice and info.Pointer.size != .One) @compileError("Invalid Pointer size. Expected Slice or comptime know string");

            switch (info.Pointer.child) {
                u8 => return switch (param) {
                    .string, .bytes => try encodeString(value, alloc),
                    .fixedBytes => |val| try encodeFixedBytes(val, value, alloc),
                    inline else => return error.InvalidParamType,
                },
                inline else => return switch (param) {
                    .dynamicArray => |val| try encodeArray(val, alloc, value, null),
                    .fixedArray => |val| try encodeArray(val.child, alloc, value, val.size),
                    inline else => return error.InvalidParamType,
                },
            }
        },
        .Bool => {
            return switch (param) {
                .bool => try encodeBool(value, alloc),
                inline else => return error.InvalidParamType,
            };
        },
        .Int, .ComptimeInt => {
            return switch (info.Int.signedness) {
                .signed => try encodeNumber(i256, value, alloc),
                .unsigned => try encodeNumber(u256, value, alloc),
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

pub fn encodeFixedBytes(size: usize, bytes: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    if (size > 32) return error.InvalidBits;
    if (bytes.len > size) return error.Overflow;

    return .{ .dynamic = false, .encoded = try zeroPad(alloc, bytes) };
}

pub fn encodeArray(param_type: *const ParamType, alloc: std.mem.Allocator, values: anytype, size: ?usize) !PreEncodedParam {
    const dynamic = size == null;

    var list = std.ArrayList(PreEncodedParam).init(alloc);

    var has_dynamic = false;
    const param = param_type.*;

    for (values) |value| {
        const pre = try preEncodeParam(param, alloc, value);

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

fn concatPreEncodedStruct(slices: []PreEncodedParam, alloc: std.mem.Allocator) ![]u8 {
    var len: usize = 0;
    for (slices) |slice| {
        len += slice.encoded.len;
    }

    var buffer = try alloc.alloc(u8, len);
    len = 0;

    for (slices) |slice| {
        @memcpy(buffer[len .. slice.encoded.len + len], slice.encoded);
        len = slice.encoded.len;
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
    const val = &[_][]const []const u256{&[_][]const u256{&[_]u256{ 123456789, 987654321 }}};

    const pre_encoded = try encodeAbiParameters(std.testing.allocator, &[_]ParamType{ParamType{ .dynamicArray = &.{ .dynamicArray = &.{ .uint = 256 } } }}, val);
    defer pre_encoded.deinit();

    std.debug.print("Foo: {s}\n", .{std.fmt.fmtSliceHexLower(pre_encoded.data)});
}
