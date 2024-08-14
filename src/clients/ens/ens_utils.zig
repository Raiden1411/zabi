const std = @import("std");
const testing = std.testing;
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Converts ens name to it's representing hash.
/// Its it's a labelhash it will return the hash bytes.
/// Make sure that the string is normalized beforehand.
pub fn convertToHash(label: []const u8) !Hash {
    var hashed: Hash = undefined;

    if (label.len == 0) {
        hashed = [_]u8{0} ** 32;
        return hashed;
    }

    if (isLabelHash(label)) {
        const hex_label = label[1..65];
        _ = try std.fmt.hexToBytes(hashed[0..], hex_label);

        return hashed;
    }

    Keccak256.hash(label, &hashed, .{});

    return hashed;
}
/// Checks if a string is a ENS Label hash.
pub fn isLabelHash(label: []const u8) bool {
    if (label.len != 66)
        return false;

    if (label[0] != '[')
        return false;

    if (label[65] != ']')
        return false;

    return utils.isHexString(label);
}
/// Hashes the ENS name to it's ens label hash.
/// Make sure that the string is normalized beforehand.
pub fn hashName(name: []const u8) !Hash {
    var hashed_result: Hash = [_]u8{0} ** 32;

    if (name.len == 0)
        return hashed_result;

    var iter = std.mem.splitBackwardsAny(u8, name, ".");

    while (iter.next()) |label| {
        var bytes: Hash = undefined;

        if (isLabelHash(label)) {
            _ = try std.fmt.hexToBytes(bytes[0..], label[1..65]);
        } else Keccak256.hash(label, &bytes, .{});

        var concated: [64]u8 = undefined;
        @memcpy(concated[0..32], hashed_result[0..]);
        @memcpy(concated[32..64], bytes[0..]);

        Keccak256.hash(concated[0..], &hashed_result, .{});
    }

    return hashed_result;
}
/// Converts the ENS names to a bytes representation
/// Make sure that the string is normalized beforehand.
pub fn convertEnsToBytes(out: []u8, label: []const u8) usize {
    if (label.len == 0) {
        // We ensure that we have atleast 1 byte to write.
        std.debug.assert(out.len > 0);

        out[0] = 1;
        return @intCast(0);
    }

    var iter = std.mem.tokenizeSequence(u8, label, ".");

    var position: usize = 0;
    while (iter.next()) |name| {
        if (name.len > 255) {
            // We need atleast 68 bytes to work for cases where the len is
            // higher than 255;
            std.debug.assert(out.len > position + 67);

            out[position] = 66;
            position += 1;

            var hash: Hash = undefined;
            Keccak256.hash(name, &hash, .{});

            out[position] = '[';
            const hexed = std.fmt.bytesToHex(hash, .lower);
            @memcpy(out[position + 1 .. 65 + position], hexed[0..]);
            out[position + 65] = ']';

            position += 66;
        } else {
            // We assert that we can write to the buffer
            std.debug.assert(out.len > name.len + position);

            out[position] = @truncate(name.len);
            position += 1;

            @memcpy(out[position .. position + name.len], name[0..]);
            position += name.len;
        }
        // We assert that we still have enough room
        // to write to the buffer;
        std.debug.assert(out.len > position);
    }

    // We assert that we still have enough room
    // to write to the buffer;
    std.debug.assert(out.len >= position);
    if (position != label.len) {
        out[position] = 0;
        return position + 1;
    }

    return position;
}

test "Namehash" {
    const hash = try hashName("zzabi.eth");
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x5ebecd8698825286699948626f12835f42f21c118e164aba567ede63911000c8", hex);
}

test "EnsToBytes" {
    {
        const name = "zzabi.eth";
        var buffer: [11]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x057a7a6162690365746800", hex);
    }
    {
        const name = "zzabi.zig.eth";
        var buffer: [15]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x057a7a616269037a69670365746800", hex);
    }
    {
        const name = "f" ** 256;
        var buffer: [68]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x425b316462356632623439323936626434316439316462636130373938633335393764633036656561623166623661386437326235393233343264633762336133365d00", hex);
    }
    {
        const name = "[1db5f2b49296bd41d91dbca0798c3597dc06eeab1fb6a8d72b592342dc7b3a36]";
        var buffer: [68]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x425b316462356632623439323936626434316439316462636130373938633335393764633036656561623166623661386437326235393233343264633762336133365d00", hex);
    }
}
