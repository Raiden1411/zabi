const std = @import("std");
const utils = @import("../utils/utils.zig");
const wasm = @import("wasm.zig");

/// Convert a value to ethereum's `Gwei` value.
pub export fn parseGwei(value: usize) u64 {
    return utils.parseGwei(value) catch @panic("Overflow");
}
/// Converts and address to its underlaying bytes.
///
/// Assumes that `out_buffer` is the correct size of 20 bytes.
pub export fn addressToBytes(expect_address: [*]const u8, len: usize, out_buffer: [*]u8) bool {
    const addr = utils.addressToBytes(expect_address[0..len]) catch return false;
    @memcpy(out_buffer[0..20], addr[0..]);

    return true;
}
/// Converts an hash to its underlaying bytes.
///
/// Assumes that `out_buffer` is the correct size of 32 bytes.
pub export fn hashToBytes(expected_address: [*]const u8, len: usize, out_buffer: [*]u8) bool {
    const hash = utils.hashToBytes(expected_address[0..len]) catch return false;
    @memcpy(out_buffer[0..32], hash[0..]);

    return true;
}
/// Checks that the given slice is an `ethereum` address.
///
/// It will also perform an checksum check.
pub export fn isAddress(expected_address: [*]const u8, len: usize) bool {
    return utils.isAddress(expected_address[0..len]);
}
/// Checks that the given slice is an hash of 32 bytes.
pub export fn isHash(expected_hash: [*]const u8, len: usize) bool {
    return utils.isHash(expected_hash[0..len]);
}
/// Checks if the given slice an hex string.
pub export fn isHexString(expected_hash: [*]const u8, len: usize) bool {
    return utils.isHexString(expected_hash[0..len]);
}
/// Checks if the given slice an hash string.
pub export fn isHashString(expected_hash: [*]const u8, len: usize) bool {
    return utils.isHashString(expected_hash[0..len]);
}
/// Checksum an `ethereum` address.
pub export fn toChecksumAddress(expected_address: [*]const u8, len: usize) [*]u8 {
    const checksum = utils.toChecksum(wasm.allocator, expected_address[0..len]) catch return &[_]u8{};

    return checksum.ptr;
}
/// Convert an `Uint8Array` bytes into a `isize`.
///
/// Returns -1 if the value overflows.
pub export fn bytesToInt(slice: [*]u8, len: usize) isize {
    return utils.bytesToInt(isize, slice[0..len]) catch -1;
}
/// Calculates the blob gas price.
pub export fn calcultateBlobGasPrice(excess_gas: u64) u128 {
    return utils.calcultateBlobGasPrice(excess_gas);
}
/// Performs a saturated addition. Meaning that if the value overflows it will return the max `isize` value.
pub export fn saturatedAddition(value: isize, add: isize) isize {
    return utils.saturatedAddition(isize, value, add);
}
/// Performs a saturated multiplication. Meaning that if the value overflows it will return the max `isize` value.
pub export fn saturatedMultiplication(value: isize, multiplier: isize) isize {
    return utils.saturatedMultiplication(isize, value, multiplier);
}
