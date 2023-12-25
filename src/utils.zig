const std = @import("std");
const ParamType = @import("param_type.zig").ParamType;

const PreEncodedParam = struct {
    dynamic: bool,
    encoded: []u8,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.encoded);
    }
};

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

    var list = std.ArrayList([32]u8).init(alloc);
    errdefer list.deinit();

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, str.len, .big);

    try list.append(buffer);

    var i: usize = 0;
    while (ceil >= i) : (i += 1) {
        const start = i * 32;
        const end = (i + 1) * 32;
        try list.append(try zeroPad(hex.data[start..if (end > hex.data.len) hex.data.len else end]));
    }

    return .{ .dynamic = true, .encoded = try concat(try list.toOwnedSlice(), alloc) };
}

pub fn encodeFixedBytes(size: usize, bytes: []const u8, alloc: std.mem.Allocator) !PreEncodedParam {
    if (size > 32) return error.InvalidBits;
    if (bytes.len > size) return error.Overflow;

    const padded = try alloc.alloc(u8, 32);
    errdefer alloc.free(padded);

    @memset(padded, 0);
    std.mem.copyBackwards(u8, padded, bytes);

    return .{ .dynamic = false, .encoded = padded };
}

// pub fn encodeArray(params: anytype, size: ?usize) ![]u8 {
//     const dynamic = size != null;
// }

fn concat(slices: [][32]u8, alloc: std.mem.Allocator) ![]u8 {
    var buffer = try alloc.alloc(u8, slices.len * 32);
    defer alloc.free(slices);
    errdefer alloc.free(buffer);

    for (slices, 0..) |*slice, i| {
        std.mem.copyForwards(u8, buffer[i * 32 .. (i + 1) * 32], slice);
    }

    return buffer;
}

fn zeroPad(buf: []const u8) ![32]u8 {
    if (buf.len > 32) return error.BufferExceedsMaxSize;
    var padded: [32]u8 = [_]u8{0} ** 32;

    std.mem.copyBackwards(u8, &padded, buf);

    return padded;
}

test "fooo" {
    const pre_encoded = try preEncodeParam(.{ .int = 256 }, std.testing.allocator, 1.01011);
    defer pre_encoded.deinit(std.testing.allocator);

    std.debug.print("Foo: {s}\n", .{std.fmt.fmtSliceHexLower(pre_encoded.encoded)});
}
