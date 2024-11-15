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
