const std = @import("std");
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Converts ethereum address to checksum
pub fn toChecksum(alloc: Allocator, address: []const u8) ![]u8 {
    var buf: [40]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, address);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(lower, &hashed, .{});
    const hex = std.fmt.bytesToHex(hashed, .lower);

    const checksum = try alloc.alloc(u8, 40);
    for (checksum, 0..) |*c, i| {
        const char = lower[i];

        if (try std.fmt.charToDigit(hex[i], 16) > 7) {
            c.* = std.ascii.toUpper(char);
        } else {
            c.* = char;
        }
    }

    return checksum;
}
