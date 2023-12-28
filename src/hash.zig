const std = @import("std");
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

pub fn hashSliced(buf: []const u8) []const u8 {
    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(buf, &hashed, .{});

    const hexed = std.fmt.bytesToHex(hashed, .lower);

    return hexed[0..8];
}
