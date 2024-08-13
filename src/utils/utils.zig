const constants = @import("constants.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const EthCall = transaction.EthCall;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Checks if a given type is static
pub inline fn isStaticType(comptime T: type) bool {
    const info = @typeInfo(T);

    switch (info) {
        .Bool, .Int, .Null => return true,
        .Array => return false,
        .Struct => inline for (info.Struct.fields) |field| {
            if (!isStaticType(field.type)) {
                return false;
            }
        },
        .Pointer => switch (info.Pointer.size) {
            .Many, .Slice, .C => return false,
            .One => return isStaticType(info.Pointer.child),
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
    // It should never reach this
    unreachable;
}
/// Checks if a given type is static
pub inline fn isDynamicType(comptime T: type) bool {
    const info = @typeInfo(T);

    switch (info) {
        .Bool, .Int, .Null => return false,
        .Array => |arr_info| return isDynamicType(arr_info.child),
        .Struct => {
            inline for (info.Struct.fields) |field| {
                const dynamic = isDynamicType(field.type);

                if (dynamic)
                    return true;
            }

            return false;
        },
        .Pointer => switch (info.Pointer.size) {
            .Many, .Slice, .C => return true,
            .One => return isStaticType(info.Pointer.child),
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}
/// Converts ethereum address to checksum
pub fn toChecksum(allocator: Allocator, address: []const u8) ![]u8 {
    var buf: [40]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, if (std.mem.startsWith(u8, address, "0x")) address[2..] else address);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(lower, &hashed, .{});
    const hex = std.fmt.bytesToHex(hashed, .lower);

    const checksum = try allocator.alloc(u8, 42);
    for (checksum[2..], 0..) |*c, i| {
        const char = lower[i];

        if (try std.fmt.charToDigit(hex[i], 16) > 7) {
            c.* = std.ascii.toUpper(char);
        } else {
            c.* = char;
        }
    }

    @memcpy(checksum[0..2], "0x");

    return checksum;
}
/// Checks if the given address is a valid ethereum address.
pub fn isAddress(addr: []const u8) bool {
    if (!std.mem.startsWith(u8, addr, "0x"))
        return false;

    const address = addr[2..];

    if (address.len != 40)
        return false;

    var buf: [40]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, address);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(lower, &hashed, .{});
    const hex = std.fmt.bytesToHex(hashed, .lower);

    var checksum: [42]u8 = undefined;
    for (checksum[2..], 0..) |*c, i| {
        const char = lower[i];

        const char_digit = std.fmt.charToDigit(hex[i], 16) catch return false;
        if (char_digit > 7) {
            c.* = std.ascii.toUpper(char);
        } else {
            c.* = char;
        }
    }

    @memcpy(checksum[0..2], "0x");

    return std.mem.eql(u8, addr, checksum[0..]);
}
/// Convert address to its representing bytes
pub fn addressToBytes(address: []const u8) !Address {
    const addr = if (std.mem.startsWith(u8, address, "0x")) address[2..] else address;

    if (addr.len != 40)
        return error.InvalidAddress;

    var addr_bytes: Address = undefined;
    _ = try std.fmt.hexToBytes(&addr_bytes, addr);

    return addr_bytes;
}
/// Convert a hash to its representing bytes
pub fn hashToBytes(hash: []const u8) !Hash {
    const hash_value = if (std.mem.startsWith(u8, hash, "0x")) hash[2..] else hash;

    if (hash_value.len != 64)
        return error.InvalidHash;

    var hash_bytes: Hash = undefined;
    _ = try std.fmt.hexToBytes(&hash_bytes, hash_value);

    return hash_bytes;
}
/// Checks if a given string is a hex string;
pub fn isHexString(value: []const u8) bool {
    for (value) |char| {
        switch (char) {
            '0'...'9', 'a'...'f', 'A'...'F' => continue,
            else => return false,
        }
    }

    return true;
}
/// Checks if the given hash is a valid 32 bytes hash
pub fn isHash(hash: []const u8) bool {
    if (!std.mem.startsWith(u8, hash, "0x")) return false;
    const hash_slice = hash[2..];

    if (hash_slice.len != 64) return false;

    return isHashString(hash_slice);
}
/// Check if a string is a hash string
pub fn isHashString(hash: []const u8) bool {
    for (hash) |char| {
        switch (char) {
            '0'...'9', 'a'...'f' => continue,
            else => return false,
        }
    }

    return true;
}
/// Convert value into u256 representing ether value
/// Ex: 1 * 10 ** 18 = 1 ETH
pub fn parseEth(value: usize) !u256 {
    const size = value * std.math.pow(u256, 10, 18);

    if (size > std.math.maxInt(u256))
        return error.Overflow;

    return size;
}
/// Convert value into u64 representing ether value
/// Ex: 1 * 10 ** 9 = 1 GWEI
pub fn parseGwei(value: usize) !u64 {
    const size = value * std.math.pow(u64, 10, 9);

    if (size > std.math.maxInt(u64))
        return error.Overflow;

    return size;
}
/// Finds the size of an int and writes to the buffer accordingly.
pub inline fn formatInt(int: u256, buffer: *[32]u8) u8 {
    inline for (1..32) |i| {
        if (int < (1 << (8 * i))) {
            buffer.* = @bitCast(@byteSwap(int));
            return i;
        }
    }

    buffer.* = @bitCast(@byteSwap(int));
    return 32;
}
/// Computes the size of a given int
pub inline fn computeSize(int: u256) u8 {
    inline for (1..32) |i| {
        if (int < (1 << (8 * i))) {
            return i;
        }
    }

    return 32;
}
/// Similar to `parseInt` but handles the hex bytes and not the
/// hex represented string.
pub fn bytesToInt(comptime T: type, slice: []u8) !T {
    const info = @typeInfo(T);
    const IntType = std.meta.Int(info.Int.signedness, @max(8, info.Int.bits));
    var x: IntType = 0;

    for (slice, 0..) |bit, i| {
        x += std.math.shl(T, bit, (slice.len - 1 - i) * 8);
    }

    return if (T == IntType)
        x
    else
        std.math.cast(T, x) orelse return error.Overflow;
}
/// Calcutates the blob gas price
pub fn calcultateBlobGasPrice(excess_gas: u64) u128 {
    var index: usize = 1;
    var output: u128 = 0;
    var acc: u128 = constants.MIN_BLOB_GASPRICE * constants.BLOB_GASPRICE_UPDATE_FRACTION;

    while (acc > 0) : (index += 1) {
        output += acc;

        acc = (acc * excess_gas) / (3 * index);
    }

    return @divFloor(output, constants.BLOB_GASPRICE_UPDATE_FRACTION);
}
/// Saturated addition. If it overflows it will return the max `T`
pub fn saturatedAddition(comptime T: type, a: T, b: T) T {
    comptime std.debug.assert(@typeInfo(T) == .Int); // Only supports int types

    const result, const overflow = @addWithOverflow(a, b);

    if (@bitCast(overflow))
        return std.math.maxInt(T);

    return @intCast(result);
}
/// Saturated multiplication. If it overflows it will return the max `T`
pub fn saturatedMultiplication(comptime T: type, a: T, b: T) T {
    std.debug.assert(@typeInfo(T) == .Int); // Only supports int types

    const result, const overflow = @mulWithOverflow(a, b);

    if (@bitCast(overflow))
        return std.math.maxInt(T);

    return @intCast(result);
}

test "IsAddress" {
    const address = "0x407d73d8a49eeb85d32cf465507dd71d507100c1";

    try testing.expect(!isAddress(address));
    try testing.expect(!isAddress("0x"));
    try testing.expect(!isAddress(""));
    try testing.expect(!isAddress("0x00000000000000000000000000000000000000000000000000000000"));
    try testing.expect(isAddress("0x0000000000000000000000000000000000000000"));
    try testing.expect(isAddress("0x407D73d8a49eeb85D32Cf465507dd71d507100c1"));
}

test "AddressToBytes" {
    try testing.expectError(error.InvalidAddress, addressToBytes("0x000000000000000000000000"));
    try testing.expectError(error.InvalidAddress, addressToBytes("000000000"));
}

test "HashToBytes" {
    try testing.expectError(error.InvalidHash, hashToBytes("0x000000000000000000000000"));
    try testing.expectError(error.InvalidHash, hashToBytes("000000000"));
}

test "BytesToInt" {
    const a = try bytesToInt(u256, @constCast(&[_]u8{ 0x12, 0x34, 0x56 }));
    const b = try std.fmt.parseInt(u256, "123456", 16);

    try testing.expectEqual(a, b);
}
