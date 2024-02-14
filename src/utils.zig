const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");

// Types
const Allocator = std.mem.Allocator;
const EthCall = transaction.EthCall;
const EthCallHexed = transaction.EthCallHexed;
const EthCallEip1559Hexed = transaction.EthCallEip1559Hexed;
const EthCallLegacyHexed = transaction.EthCallLegacyHexed;
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
    const call: transaction.EthCallHexed = call: {
        switch (call_object) {
            .eip1559 => |tx| {
                const eip1559_call: EthCallEip1559Hexed = .{
                    .value = if (tx.value) |value| try std.fmt.allocPrint(alloc, "0x{x}", .{value}) else null,
                    .gas = if (tx.gas) |gas| try std.fmt.allocPrint(alloc, "0x{x}", .{gas}) else null,
                    .maxFeePerGas = if (tx.maxFeePerGas) |fees| try std.fmt.allocPrint(alloc, "0x{x}", .{fees}) else null,
                    .maxPriorityFeePerGas = if (tx.maxPriorityFeePerGas) |max_fees| try std.fmt.allocPrint(alloc, "0x{x}", .{max_fees}) else null,
                    .from = tx.from,
                    .to = tx.to,
                    .data = tx.data,
                };

                break :call .{ .eip1559 = eip1559_call };
            },
            .legacy => |tx| {
                const legacy_call: EthCallLegacyHexed = .{
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

    if (size > std.math.maxInt(u256)) return error.Overflow;

    return size;
}
/// Convert value into u64 representing ether value
/// Ex: 1 * 10 ** 9 = 1 GWEI
pub fn parseGwei(value: usize) !u64 {
    const size = value * std.math.pow(u64, 10, 9);

    if (size > std.math.maxInt(u64)) return error.Overflow;

    return size;
}

test "Checksum" {
    const address = "0x407d73d8a49eeb85d32cf465507dd71d507100c1";

    try testing.expect(!try isAddress(testing.allocator, address));
}
