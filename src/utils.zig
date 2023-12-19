const std = @import("std");

pub fn encodeUnsignedNumber(num: u256) [32]u8 {
    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, num, .big);

    return buffer;
}

pub fn encodeSignedNumber(num: i256) [32]u8 {
    var buffer: [32]u8 = undefined;
    std.mem.writeInt(i256, &buffer, num, .big);

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

test "fooo" {
    const a = encodeSignedNumber(std.math.maxInt(i256));
    const b = try encodeAddress("0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5");
    const c = encodeBool(true);
    const d = encodeUnsignedNumber(std.math.maxInt(u256));

    std.debug.print("\nEncoded Uint: {s}\n", .{std.fmt.bytesToHex(d, .lower)});
    std.debug.print("Encoded Int: {s}\n", .{std.fmt.bytesToHex(a, .lower)});
    std.debug.print("Encoded Address: {s}\n", .{std.fmt.bytesToHex(b, .lower)});
    std.debug.print("Encoded bool: {s}\n", .{std.fmt.bytesToHex(c, .lower)});
}
