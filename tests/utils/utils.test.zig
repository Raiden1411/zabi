const std = @import("std");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const addressToBytes = utils.addressToBytes;
const bytesToInt = utils.bytesToInt;
const hashToBytes = utils.hashToBytes;
const isAddress = utils.isAddress;

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

test "FloatToInt" {
    try testing.expectEqual(utils.floatFromInt(f64, 1), @as(f64, @floatFromInt(1)));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u8)), @as(f64, @floatFromInt(std.math.maxInt(u8))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u16)), @as(f64, @floatFromInt(std.math.maxInt(u16))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u32)), @as(f64, @floatFromInt(std.math.maxInt(u32))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u64)), @as(f64, @floatFromInt(std.math.maxInt(u64))));

    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u128)), @as(f64, @floatFromInt(std.math.maxInt(u128))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u129)), @as(f64, @floatFromInt(std.math.maxInt(u129))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u256)), @as(f64, @floatFromInt(std.math.maxInt(u256))));
    try testing.expectEqual(utils.floatFromInt(f64, std.math.maxInt(u512)), @as(f64, @floatFromInt(std.math.maxInt(u512))));
}

test "IntToFloat" {
    try testing.expectEqual(utils.intFromFloat(u8, 1.0), @as(u8, @intFromFloat(1.0)));
    try testing.expectEqual(utils.intFromFloat(i8, -1.0), @as(i8, @intFromFloat(-1.0)));
    try testing.expectEqual(utils.intFromFloat(u16, 1000.1234), @as(u16, @intFromFloat(1000.1234)));
    try testing.expectEqual(utils.intFromFloat(i16, std.math.minInt(i16)), @as(i16, @intFromFloat(std.math.minInt(i16))));
    try testing.expectEqual(utils.intFromFloat(u64, 10000000000.1234), @as(u64, @intFromFloat(10000000000.1234)));
    try testing.expectEqual(utils.intFromFloat(i64, std.math.minInt(i64)), @as(i64, @intFromFloat(std.math.minInt(i64))));
    try testing.expectEqual(utils.intFromFloat(u128, 1000000000000000000.1234), @as(u128, @intFromFloat(1000000000000000000.1234)));
    try testing.expectEqual(utils.intFromFloat(i128, std.math.minInt(i128) + 1.000001), @as(i128, @intFromFloat(std.math.minInt(i128) + 1.000001)));
    try testing.expectEqual(utils.intFromFloat(u256, 1000000000000000000000000000000000000.1234), @as(u256, @intFromFloat(1000000000000000000000000000000000000.1234)));
    try testing.expectEqual(utils.intFromFloat(i256, std.math.minInt(i256) + 1.000001), @as(i256, @intFromFloat(std.math.minInt(i256) + 1.000001)));
    try testing.expectEqual(utils.intFromFloat(u512, 1000000000000000000000000000000000000000000000000000000000000000.1234), @as(u512, @intFromFloat(1000000000000000000000000000000000000000000000000000000000000000.1234)));
    try testing.expectEqual(utils.intFromFloat(i512, std.math.minInt(i512) + 1.000001), @as(i512, @intFromFloat(std.math.minInt(i512) + 1.000001)));
}
