const std = @import("std");
const ParamType = @import("param_type.zig").ParamType;

const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
};

pub fn encodeParameters(params: []PreEncodedParam, alloc: std.mem.Allocator) ![]u8 {
    var s_size = 0;

    for (params) |param| {
        if (param.dynamic) s_size += 32 else s_size += param.encoded.len;
    }

    var static_list = std.ArrayList([]u8).init(alloc);
    errdefer static_list.deinit();

    var dynamic_list = std.ArrayList([]u8).init(alloc);
    errdefer dynamic_list.deinit();

    var d_size = 0;
    for (params) |param| {
        if (param.dynamic) {
            const size = try encodeNumber(u256, s_size + d_size, alloc);
            errdefer size.deinit(alloc);

            try static_list.append(size.encoded);
            try dynamic_list.append(param.encoded);

            d_size += param.encoded.len;
        } else {
            try static_list.append(param.encoded);
        }
    }

    const static = try concat(try static_list.toOwnedSlice(), alloc);
    errdefer alloc.free(static);

    const dynamic = try concat(try dynamic_list.toOwnedSlice(), alloc);
    errdefer alloc.free(dynamic);

    const concated = try std.mem.concat(alloc, u8, &.{ static, dynamic });
    errdefer alloc.free(concated);

    return concated;
}

pub fn preEncodeParams(params: []const ParamType, alloc: std.mem.Allocator, values: anytype) ![]PreEncodedParam {
    std.debug.assert(values.len > 0);

    var list = std.ArrayList(PreEncodedParam).init(alloc);
    errdefer list.deinit();

    for (values, params) |value, param| {
        const pre_encoded = try preEncodeParam(param, alloc, value);
        errdefer pre_encoded.deinit(alloc);

        try list.append(pre_encoded);
    }

    return list.toOwnedSlice();
}

pub fn preEncodeParam(param: ParamType, alloc: std.mem.Allocator, value: anytype) !PreEncodedParam {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Pointer => {
            if (info.Pointer.size != .Slice and info.Pointer.size != .One) @compileError("Invalid Pointer size. Expected Slice or comptime know string");

            return switch (param) {
                .string, .bytes => try encodeString(value, alloc),
                .fixedBytes => |val| try encodeFixedBytes(val, value, alloc),
                .address => try encodeAddress(value, alloc),
                inline else => return error.InvalidParamType,
            };
        },
        .Bool => {
            return switch (param) {
                .bool => try encodeBool(value, alloc),
                inline else => return error.InvalidParamType,
            };
        },
        .Int, .ComptimeInt => {
            return switch (param) {
                .int => try encodeNumber(i256, value, alloc),
                .uint => try encodeNumber(u256, value, alloc),
                inline else => return error.InvalidParamType,
            };
        },
        inline else => @compileError(@typeName(@TypeOf(value)) ++ " type is not supported"),
    }
}

pub fn encodeNumber(comptime T: type, num: T, alloc: std.mem.Allocator) !PreEncodedParam {
    const info = @typeInfo(T);
    if (info != .Int) return error.InvalidIntType;
    if (num > std.math.maxInt(T)) return error.Overflow;

    var buffer = try alloc.alloc(u8, 32);
    errdefer alloc.free(buffer);
    std.mem.writeInt(T, buffer[0..32], num, .big);

    return .{ .dynamic = false, .encoded = buffer };
}

pub fn encodeAddress(addr: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    var addr_bytes: [20]u8 = undefined;
    var padded = try alloc.alloc(u8, 32);
    errdefer alloc.free(padded);

    @memset(padded, 0);
    std.mem.copyForwards(u8, padded[12..], try std.fmt.hexToBytes(&addr_bytes, addr[2..]));

    return .{ .dynamic = false, .encoded = padded };
}

pub fn encodeBool(b: bool, alloc: std.mem.Allocator) !PreEncodedParam {
    var padded = try alloc.alloc(u8, 32);
    errdefer alloc.free(padded);

    @memset(padded, 0);
    padded[padded.len - 1] = @intFromBool(b);

    return .{ .dynamic = false, .encoded = padded };
}

pub fn encodeString(str: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    const hex = std.fmt.fmtSliceHexLower(str);
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(hex.data.len))) / 32);

    var list = std.ArrayList([]u8).init(alloc);
    errdefer list.deinit();

    const size = try encodeNumber(u256, str.len, alloc);
    errdefer size.deinit(alloc);

    try list.append(size.encoded);

    var i: usize = 0;
    while (ceil >= i) : (i += 1) {
        const start = i * 32;
        const end = (i + 1) * 32;

        const buf = try zeroPad(alloc, hex.data[start..if (end > hex.data.len) hex.data.len else end]);
        errdefer alloc.free(buf);

        try list.append(buf);
    }

    return .{ .dynamic = true, .encoded = try concat(try list.toOwnedSlice(), alloc) };
}

pub fn encodeFixedBytes(size: usize, bytes: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    if (size > 32) return error.InvalidBits;
    if (bytes.len > size) return error.Overflow;

    return .{ .dynamic = false, .encoded = try zeroPad(alloc, bytes) };
}

pub fn encodeArray(param_type: *ParamType, alloc: std.mem.Allocator, values: anytype, size: ?usize) !PreEncodedParam {
    const dynamic = size != null;

    var list = std.ArrayList(PreEncodedParam).init(alloc);
    errdefer list.deinit();

    var has_dynamic = false;
    for (values) |value| {
        const pre = try preEncodeParam(param_type, alloc, value);
        if (pre.dynamic) has_dynamic = true;
        try list.append(pre);
    }

    if (dynamic or has_dynamic) {
        const slices = try list.toOwnedSlice();
        const hex = try encodeParameters(slices, alloc);

        if (dynamic) {
            const len = try encodeNumber(u256, slices.len, alloc);
            errdefer size.deinit(alloc);

            const enc = if (slices.len > 0) try std.mem.concat(alloc, u8, &.{ len.encoded, hex }) else hex;
            errdefer alloc.free(enc);

            return .{ .dynamic = true, .encoded = enc };
        }

        if (has_dynamic) return .{ .dynamic = true, .encoded = hex };
    }

    const concated = try concat(try list.toOwnedSlice(), alloc);
    errdefer alloc.free(concated);

    return .{ .dynamic = false, .encoded = concated };
}

fn concat(slices: anytype, alloc: std.mem.Allocator) ![]u8 {
    var len: usize = 0;
    for (slices) |slice| {
        switch (@typeInfo(@TypeOf(slice))) {
            .Pointer => len += slice.len,
            .Struct => len += slice.encoded.len,
            inline else => return error.InvalidSliceType,
        }
    }

    defer alloc.free(slices);

    var buffer = try alloc.alloc(u8, len);
    errdefer alloc.free(buffer);

    len = 0;
    for (slices) |slice| {
        switch (@typeInfo(@TypeOf(slice))) {
            .Pointer => {
                @memcpy(buffer[len .. slice.len + len], slice);
                len = slice.len;
                alloc.free(slice);
            },
            .Struct => {
                @memcpy(buffer[len .. slice.encoded.len + len], slice.encoded);
                len = slice.encoded.len;
                alloc.free(slice.encoded);
            },
            inline else => return error.InvalidSliceType,
        }
    }

    return buffer;
}

fn zeroPad(alloc: std.mem.Allocator, buf: []const u8) ![]u8 {
    if (buf.len > 32) return error.BufferExceedsMaxSize;
    const padded = try alloc.alloc(u8, 32);
    errdefer alloc.free(padded);

    @memset(padded, 0);
    std.mem.copyBackwards(u8, padded, buf);

    return padded;
}

test "fooo" {
    const pre_encoded = try preEncodeParam(.{ .string = {} }, std.testing.allocator, "foobarbaz");
    defer pre_encoded.deinit(std.testing.allocator);

    std.debug.print("Foo: {s}\n", .{std.fmt.fmtSliceHexLower(pre_encoded.encoded)});
}
