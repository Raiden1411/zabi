const std = @import("std");
const testing = std.testing;
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

/// Checks if the given address is a valid ethereum address.
pub fn isAddress(alloc: Allocator, addr: []const u8) !bool {
    if (!std.mem.startsWith(u8, addr, "0x")) return false;
    const address = addr[2..];

    if (address.len != 40) return false;
    const checksumed = try toChecksum(alloc, address);
    defer alloc.free(checksumed);

    return std.mem.eql(u8, address, checksumed);
}

/// Checks if the given hash is a valid 32 bytes hash
pub fn isHash(hash: []const u8) bool {
    if (!std.mem.startsWith(u8, hash, "0x")) return false;
    const hash_slice = hash[2..];

    if (hash_slice.len != 64) return false;

    for (0..hash_slice.len) |i| {
        const char = hash_slice[i];

        switch (char) {
            '0'...'9', 'a'...'f' => continue,
            else => return false,
        }
    }

    return true;
}

pub fn parseEth(value: usize) !u256 {
    const size = value * std.math.pow(u256, 10, 18);

    if (size > std.math.maxInt(u256)) return error.Overflow;

    return size;
}

pub fn parseGwei(value: usize) !u64 {
    const size = value * std.math.pow(u64, 10, 9);

    if (size > std.math.maxInt(u64)) return error.Overflow;

    return size;
}

test "Checksum" {
    const address = "0x407d73d8a49eeb85d32cf465507dd71d507100c1";

    try testing.expect(!try isAddress(testing.allocator, address));
}
