const std = @import("std");

pub fn encodeNumber(comptime T: type, num: T) ![32]u8 {
    const info = @typeInfo(T);
    if (info != .Int) return error.InvalidIntType;
    if (num > std.math.maxInt(T)) return error.Overflow;

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(T, &buffer, num, .big);

    return buffer;
}

pub fn encodeAddress(addr: []const u8) ![32]u8 {
    var addr_bytes: [20]u8 = undefined;
    var padded: [32]u8 = [_]u8{0} ** 32;

    std.mem.copyForwards(u8, padded[12..], try std.fmt.hexToBytes(&addr_bytes, addr[2..]));
    return padded;
}

pub fn encodeBool(b: bool) [32]u8 {
    return if (b) [_]u8{0} ** 31 ++ [_]u8{1} else [_]u8{0} ** 32;
}

pub fn encodeString(str: []const u8, alloc: std.mem.Allocator) ![][32]u8 {
    const hex = std.fmt.fmtSliceHexLower(str);
    const ceil: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(hex.data.len))) / 32);

    var list = std.ArrayList([32]u8).init(alloc);
    errdefer list.deinit();

    const size = try encodeNumber(u256, str.len);
    try list.append(size);

    var i: usize = 0;
    while (ceil >= i) : (i += 1) {
        const start = i * 32;
        const end = (i + 1) * 32;
        try list.append(try zeroPad(hex.data[start..if (end > hex.data.len) hex.data.len else end]));
    }

    return try list.toOwnedSlice();
}

fn concat(slices: [][32]u8, alloc: std.mem.Allocator) ![]u8 {
    var buffer = try alloc.alloc(u8, slices.len * 32);
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
    const a = try encodeNumber(i256, std.math.maxInt(i256));
    const b = try encodeAddress("0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5");
    const d = try encodeNumber(u256, std.math.maxInt(u256));
    const c = encodeBool(true);
    const f = try encodeString("wagmi", std.testing.allocator);
    defer std.testing.allocator.free(f);

    std.debug.print("\nEncoded Uint: {s}\n", .{std.fmt.bytesToHex(d, .lower)});
    std.debug.print("Encoded Int: {s}\n", .{std.fmt.bytesToHex(a, .lower)});
    std.debug.print("Encoded Address: {s}\n", .{std.fmt.bytesToHex(b, .lower)});
    std.debug.print("Encoded bool: {s}\n", .{std.fmt.bytesToHex(c, .lower)});
    const cc = try concat(f, std.testing.allocator);
    defer std.testing.allocator.free(cc);
    std.debug.print("Encoded string: {s}\n", .{std.fmt.fmtSliceHexLower(cc)});
    // std.debug.print("FOO: {s}\n", .{std.fmt.fmtSliceHexLower("Hello World!")});
}
