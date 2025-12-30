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
            .many, .slice, .c => return false,
            .one => return isStaticType(info.pointer.child),
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
            .many, .slice, .c => return true,
            .one => switch (@typeInfo(info.pointer.child)) {
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
pub fn hashToBytes(
    hash: []const u8,
) error{ InvalidHash, NoSpaceLeft, InvalidLength, InvalidCharacter }!Hash {
    const hash_value = if (std.mem.startsWith(u8, hash, "0x")) hash[2..] else hash;

    if (hash_value.len != 64)
        return error.InvalidHash;

    var hash_bytes: Hash = undefined;
    _ = try std.fmt.hexToBytes(&hash_bytes, hash_value);

    return hash_bytes;
}
/// Checks if a given string is a hex string;
pub fn isHexString(value: []const u8) bool {
    for (value) |char| switch (char) {
        '0'...'9', 'a'...'f', 'A'...'F' => continue,
        else => return false,
    } else return true;
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
    for (hash) |char| switch (char) {
        '0'...'9', 'a'...'f' => continue,
        else => return false,
    } else return true;
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

/// Converts a float type to the provided int type.
/// This doesn't error on aarch64 for the llvm backend
pub fn intFromFloat(comptime T: type, float: anytype) T {
    const Float = switch (@typeInfo(@TypeOf(float))) {
        else => @TypeOf(float),
        .comptime_float => f128, // any float type will do
    };
    const type_info = @typeInfo(T);

    if (type_info.int.bits <= 128) {
        @branchHint(.likely);
        return @intFromFloat(float);
    }

    if (float == 0)
        return 0;

    if (std.math.isInf(@as(Float, @floatCast(float)))) {
        @branchHint(.unlikely);

        if (std.math.isNan(float))
            return 0;

        return if (float > 0) std.math.maxInt(T) else std.math.minInt(T);
    }

    const Repr = std.math.FloatRepr(Float);
    const repr: Repr = @bitCast(@as(Float, @floatCast(float)));

    const raw_mantissa = repr.mantissa;
    const raw_exponent = @intFromEnum(repr.exponent);
    const fractional_bits = std.math.floatFractionalBits(Float);

    const is_subnormal = (raw_exponent == 0);
    const implicit_bit: T = if (is_subnormal) 0 else (@as(T, 1) << fractional_bits);
    const full_mantissa: T = implicit_bit | @as(T, raw_mantissa);

    const bias = @intFromEnum(Repr.BiasedExponent.zero);
    const exp_val = if (is_subnormal)
        1 - @as(i32, @intCast(bias))
    else
        @as(i32, @intCast(raw_exponent)) - @as(i32, @intCast(bias));

    var result: T = 0;
    const shift = exp_val - @as(i32, fractional_bits);

    if (shift >= 0) {
        if (shift < type_info.int.bits) {
            result = full_mantissa << @intCast(shift);
        } else @panic("Cannot fit float into provided integer");
    } else {
        const r_shift = -shift;
        if (r_shift < type_info.int.bits) {
            result = full_mantissa >> @intCast(r_shift);
        } else {
            result = 0;
        }
    }

    if (repr.sign == .negative) {
        if (type_info.int.signedness == .unsigned)
            @panic("Cannot fit float into provided unsigned integer");

        return -%result;
    }

    return result;
}

/// Converts a int type to the provided float type.
/// This doesn't error on aarch64 for the llvm backend
pub fn floatFromInt(comptime Float: type, value: anytype) Float {
    const info_value = @typeInfo(@TypeOf(value));
    const Int = switch (info_value) {
        .comptime_int => std.math.IntFittingRange(value, value),
        .int => @TypeOf(value),
        else => @compileError("Only integers or comptime_int are supported!"),
    };

    const info = @typeInfo(Int);

    // For 128-bit or smaller, the native cast is safe and efficient
    if (info.int.bits <= 128) {
        @branchHint(.likely);

        return @floatFromInt(value);
    }

    // Calculate how many 64-bit limbs we need
    const limb_count = (info.int.bits + 63) / 64;
    var limbs: [limb_count]u64 = undefined;

    // Handle signedness
    const is_negative = value < 0;
    const abs_value = if (is_negative) @as(Int, -%value) else value;

    // Populate limbs (Little Endian)
    inline for (0..limb_count) |i|
        limbs[i] = @truncate(abs_value >> (i * 64));

    const b = std.math.big.int.Const{
        .limbs = &limbs,
        .positive = !is_negative,
    };

    const float, _ = b.toFloat(Float, .nearest_even);

    return float;
}
