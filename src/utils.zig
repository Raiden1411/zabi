const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");

// Types
const Allocator = std.mem.Allocator;
const EthCall = transaction.EthCall;
const EthCallHexed = transaction.EthCallHexed;
const LondonEthCallHexed = transaction.LondonEthCallHexed;
const LegacyEthCallHexed = transaction.LegacyEthCallHexed;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Converts ethereum address to checksum
pub fn toChecksum(alloc: Allocator, address: []const u8) ![]u8 {
    var buf: [40]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, if (std.mem.startsWith(u8, address, "0x")) address[2..] else address);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(lower, &hashed, .{});
    const hex = std.fmt.bytesToHex(hashed, .lower);

    const checksum = try alloc.alloc(u8, 42);
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
pub fn isAddress(alloc: Allocator, addr: []const u8) !bool {
    if (!std.mem.startsWith(u8, addr, "0x")) return false;
    const address = addr[2..];

    if (address.len != 40) return false;
    const checksumed = try toChecksum(alloc, address);
    defer alloc.free(checksumed);

    return std.mem.eql(u8, addr, checksumed);
}

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

    for (0..hash_slice.len) |i| {
        const char = hash_slice[i];

        switch (char) {
            '0'...'9', 'a'...'f' => continue,
            else => return false,
        }
    }

    return true;
}
/// Converts a `EthCall` struct into all hex values.
pub fn hexifyEthCall(alloc: Allocator, call_object: EthCall) !EthCallHexed {
    const call: EthCallHexed = call: {
        switch (call_object) {
            .london => |tx| {
                const eip1559_call: LondonEthCallHexed = .{
                    .value = if (tx.value) |value| try std.fmt.allocPrint(alloc, "0x{x}", .{value}) else null,
                    .gas = if (tx.gas) |gas| try std.fmt.allocPrint(alloc, "0x{x}", .{gas}) else null,
                    .maxFeePerGas = if (tx.maxFeePerGas) |fees| try std.fmt.allocPrint(alloc, "0x{x}", .{fees}) else null,
                    .maxPriorityFeePerGas = if (tx.maxPriorityFeePerGas) |max_fees| try std.fmt.allocPrint(alloc, "0x{x}", .{max_fees}) else null,
                    .from = tx.from,
                    .to = tx.to,
                    .data = tx.data,
                };

                break :call .{ .london = eip1559_call };
            },
            .legacy => |tx| {
                const legacy_call: LegacyEthCallHexed = .{
                    .value = if (tx.value) |value| try std.fmt.allocPrint(alloc, "0x{x}", .{value}) else null,
                    .gasPrice = if (tx.gasPrice) |gas_price| try std.fmt.allocPrint(alloc, "0x{x}", .{gas_price}) else null,
                    .gas = if (tx.gas) |gas| try std.fmt.allocPrint(alloc, "0x{x}", .{gas}) else null,
                    .from = tx.from,
                    .to = tx.to,
                    .data = tx.data,
                };

                break :call .{ .legacy = legacy_call };
            },
        }
    };

    return call;
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
    if (int < (1 << 8)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 1;
    }
    if (int < (1 << 16)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 2;
    }
    if (int < (1 << 24)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 3;
    }
    if (int < (1 << 32)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 4;
    }
    if (int < (1 << 40)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 5;
    }
    if (int < (1 << 48)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 6;
    }
    if (int < (1 << 56)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 7;
    }
    if (int < (1 << 64)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 8;
    }
    if (int < (1 << 72)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 9;
    }

    if (int < (1 << 80)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 10;
    }

    if (int < (1 << 88)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 11;
    }

    if (int < (1 << 96)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 12;
    }

    if (int < (1 << 104)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 13;
    }

    if (int < (1 << 112)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 14;
    }

    if (int < (1 << 120)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 15;
    }

    if (int < (1 << 128)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 16;
    }

    if (int < (1 << 136)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 17;
    }

    if (int < (1 << 144)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 18;
    }

    if (int < (1 << 152)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 19;
    }

    if (int < (1 << 160)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 20;
    }

    if (int < (1 << 168)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 21;
    }

    if (int < (1 << 176)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 22;
    }

    if (int < (1 << 184)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 23;
    }

    if (int < (1 << 192)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 24;
    }

    if (int < (1 << 200)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 25;
    }

    if (int < (1 << 208)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 26;
    }

    if (int < (1 << 216)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 27;
    }

    if (int < (1 << 224)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 28;
    }

    if (int < (1 << 232)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 29;
    }

    if (int < (1 << 240)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 30;
    }

    if (int < (1 << 248)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 31;
    }

    buffer.* = @bitCast(@byteSwap(int));
    return 32;
}
/// Computes the size of a given int
pub inline fn computeSize(int: u256) u8 {
    if (int < (1 << 8)) return 1;
    if (int < (1 << 16)) return 2;
    if (int < (1 << 24)) return 3;
    if (int < (1 << 32)) return 4;
    if (int < (1 << 40)) return 5;
    if (int < (1 << 48)) return 6;
    if (int < (1 << 56)) return 7;
    if (int < (1 << 64)) return 8;
    if (int < (1 << 72)) return 9;
    if (int < (1 << 80)) return 10;
    if (int < (1 << 88)) return 11;
    if (int < (1 << 96)) return 12;
    if (int < (1 << 104)) return 13;
    if (int < (1 << 112)) return 14;
    if (int < (1 << 120)) return 15;
    if (int < (1 << 128)) return 16;
    if (int < (1 << 136)) return 17;
    if (int < (1 << 144)) return 18;
    if (int < (1 << 152)) return 19;
    if (int < (1 << 160)) return 20;
    if (int < (1 << 168)) return 21;
    if (int < (1 << 176)) return 22;
    if (int < (1 << 184)) return 23;
    if (int < (1 << 192)) return 24;
    if (int < (1 << 200)) return 25;
    if (int < (1 << 208)) return 26;
    if (int < (1 << 216)) return 27;
    if (int < (1 << 224)) return 28;
    if (int < (1 << 232)) return 29;
    if (int < (1 << 240)) return 30;
    if (int < (1 << 248)) return 31;

    return 32;
}

test "Checksum" {
    const address = "0x407d73d8a49eeb85d32cf465507dd71d507100c1";

    try testing.expect(!try isAddress(testing.allocator, address));
}
