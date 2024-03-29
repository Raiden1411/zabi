const std = @import("std");
const testing = std.testing;
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

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

pub fn isLabelHash(label: []const u8) bool {
    if (label.len != 66)
        return false;

    if (label[0] != '[')
        return false;

    if (label[65] != ']')
        return false;

    return utils.isHexString(label);
}

pub fn hashName(name: []const u8) !Hash {
    var hashed_result: Hash = [_]u8{0} ** 32;

    if (name.len == 0)
        return hashed_result;

    var iter = std.mem.splitBackwards(u8, name, ".");

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

pub fn convertEnsToBytes(out: []u8, label: []const u8) usize {
    if (label.len == 0) {
        out[0] = 1;
        return @intCast(0);
    }

    var iter = std.mem.tokenizeSequence(u8, label, ".");

    var position: usize = 0;
    while (iter.next()) |name| {
        if (name.len > 255) {
            out[position] = 32;
            position += 1;

            var hash: Hash = undefined;
            Keccak256.hash(name, &hash, .{});

            @memcpy(out[position .. 32 + position], hash[0..]);
            position += 32;
        } else {
            out[position] = @truncate(name.len);
            position += 1;

            @memcpy(out[position .. position + name.len], name[0..]);
            position += name.len;
        }
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
    const name = "zzabi.eth";
    var buffer: [512]u8 = undefined;

    const bytes_read = convertEnsToBytes(buffer[0..], name);

    std.debug.print("FOOO: 0x{s}\n", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
}
