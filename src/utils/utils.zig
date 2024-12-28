const constants = @import("constants.zig");
const std = @import("std");
const testing = std.testing;
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const zabi_types = @import("zabi-types");

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
        .bool, .int, .null => return true,
        .array => return false,
        .@"struct" => inline for (info.@"struct".fields) |field| {
            if (!isStaticType(field.type)) {
                return false;
            }
        },
        .pointer => switch (info.pointer.size) {
            .Many, .Slice, .C => return false,
            .One => return isStaticType(info.pointer.child),
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
        .bool,
        .int,
        .null,
        .float,
        .comptime_int,
        .comptime_float,
        => return false,
        .array => |arr_info| return isDynamicType(arr_info.child),
        .@"struct" => {
            inline for (info.@"struct".fields) |field| {
                const dynamic = isDynamicType(field.type);

                if (dynamic)
                    return true;
            }

            return false;
        },
        .optional => |opt_info| return isDynamicType(opt_info.child),
        .pointer => switch (info.pointer.size) {
            .Many, .Slice, .C => return true,
            .One => switch (@typeInfo(info.pointer.child)) {
                .array => return true,

                else => return isDynamicType(info.pointer.child),
            },
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}
/// Converts ethereum address to checksum
pub fn toChecksum(
    allocator: Allocator,
    address: []const u8,
) (Allocator.Error || error{ Overflow, InvalidCharacter })![]u8 {
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
pub fn addressToBytes(
    address: []const u8,
) error{ InvalidAddress, NoSpaceLeft, InvalidLength, InvalidCharacter }!Address {
    const addr = if (std.mem.startsWith(u8, address, "0x")) address[2..] else address;

    if (addr.len != 40)
        return error.InvalidAddress;

    var addr_bytes: Address = undefined;
    _ = try std.fmt.hexToBytes(&addr_bytes, addr);

    return addr_bytes;
}
/// Convert a hash to its representing bytes
pub fn hashToBytes(hash: []const u8) error{ InvalidHash, NoSpaceLeft, InvalidLength, InvalidCharacter }!Hash {
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
pub fn parseEth(value: usize) error{Overflow}!u256 {
    const size = value * std.math.pow(u256, 10, 18);

    if (size > std.math.maxInt(u256))
        return error.Overflow;

    return size;
}
/// Convert value into u64 representing ether value
/// Ex: 1 * 10 ** 9 = 1 GWEI
pub fn parseGwei(value: usize) error{Overflow}!u64 {
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
pub fn bytesToInt(comptime T: type, slice: []const u8) error{Overflow}!T {
    const info = @typeInfo(T);
    const IntType = std.meta.Int(info.int.signedness, @max(8, info.int.bits));
    var x: IntType = 0;

    for (slice, 0..) |bit, i| {
        x += std.math.shl(T, if (info.int.bits < 8) @truncate(bit) else bit, (slice.len - 1 - i) * 8);
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
