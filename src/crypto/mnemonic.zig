//! Experimental and unaudited code. Use with caution.
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki

const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;

// TODO: Support more languages
/// Wordlist of valid english mnemonic words.
pub const english = Wordlist.loadRawList(@embedFile("wordlists/english.txt"));

/// The array of entropy bytes of an mnemonic passphrase
/// Compilation will fail if the count is not 12/15/18/21/24
pub fn EntropyArray(comptime word_count: comptime_int) type {
    switch (word_count) {
        12, 15, 18, 21, 24 => {},
        else => @compileError(std.fmt.comptimePrint("Unsupported word count of {d}", .{word_count})),
    }

    const entropy_bytes = 32 * word_count / 3;
    return [entropy_bytes / 8]u8;
}
/// Converts a mnemonic passphrase into a hashed seed that
/// can be used later for HDWallets.
///
/// Uses `pbkdf2` for the hashing with `HmacSha512` for the
/// pseudo random function to use
pub fn mnemonicToSeed(password: []const u8) ![64]u8 {
    var buffer: [64]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(buffer[0..], password, "mnemonic", 2048, HmacSha512);

    return buffer;
}
/// Converts the mnemonic phrase into it's entropy representation.
pub fn toEntropy(comptime word_count: comptime_int, password: []const u8, wordlist: ?Wordlist) !EntropyArray(word_count) {
    const words = wordlist orelse english;

    var iter = std.mem.tokenizeAny(u8, password, " ");
    const size = comptime std.math.divCeil(u16, 11 * word_count, 8) catch @compileError("Invalid word_count size");

    var entropy: [size]u8 = [_]u8{0} ** size;

    var count: usize = 0;
    while (iter.next()) |word| {
        const index = words.getIndex(word) orelse return error.InvalidMnemonicWord;

        for (0..11) |bit| {
            if (index & std.math.shl(u16, 1, 10 - bit) != 0) {
                entropy[count >> 3] |= std.math.shl(u8, 1, 7 - (count % 8));
            }
            count += 1;
        }
    }

    const entropy_bytes = comptime 32 * word_count / 3;
    const checksum_bytes = comptime word_count / 3;
    const checksum_mask = ((1 << checksum_bytes) - 1) << (8 - checksum_bytes) & 0xFF;

    var buffer: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(entropy[0 .. entropy_bytes / 8], &buffer, .{});

    const checksum = buffer[0] & checksum_mask;

    if (checksum != entropy[entropy.len - 1] & checksum)
        return error.InvalidMnemonicChecksum;

    return entropy[0 .. entropy_bytes / 8].*;
}

pub fn fromEntropy(allocator: std.mem.Allocator, comptime word_count: comptime_int, entropy_bytes: EntropyArray(word_count), word_list: ?Wordlist) ![]const u8 {
    const list = word_list orelse english;

    var mnemonic = std.ArrayList(u8).init(allocator);
    errdefer mnemonic.deinit();

    var writer = mnemonic.writer();

    var indices = std.ArrayList(u16).init(allocator);
    errdefer indices.deinit();

    try indices.append(0);

    var remainder: u8 = 11;
    for (entropy_bytes) |bit| {
        if (remainder > 8) {
            indices.items[indices.items.len - 1] <<= 8;
            indices.items[indices.items.len - 1] |= bit;

            remainder -= 8;
        } else {
            indices.items[indices.items.len - 1] <<= @truncate(remainder);

            indices.items[indices.items.len - 1] |= std.math.shr(u16, bit, 8 - remainder);

            try indices.append(bit & (std.math.shl(u8, 1, 8 - remainder) - 1) & 0xFF);
            remainder += 3;
        }
    }

    const checksum_bits = comptime entropy_bytes.len / 4;

    var buffer: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&entropy_bytes, &buffer, .{});

    const checksum = try utils.bytesToInt(u16, buffer[0..1]);
    const checksum_mask = checksum & ((1 << checksum_bits) - 1) << (8 - checksum_bits) & 0xFF;

    indices.items[indices.items.len - 1] <<= checksum_bits;
    indices.items[indices.items.len - 1] |= checksum_mask >> (8 - checksum_bits);

    const indices_slice = try indices.toOwnedSlice();
    defer allocator.free(indices_slice);

    for (indices_slice, 0..) |indice, i| {
        try writer.writeAll(list.word_list[indice]);
        if (i < indices_slice.len - 1)
            try writer.writeByte(' ');
    }

    return try mnemonic.toOwnedSlice();
}

// TODO: Normalize words from list.
/// The word lists that are valid for mnemonic passphrases.
pub const Wordlist = struct {
    const List = @This();

    const list_count: u16 = 2048;

    word_list: [Wordlist.list_count][]const u8,

    /// Loads word in it's raw format and parses it.
    /// It expects that the string is seperated by "\n"
    pub fn loadRawList(raw_list: []const u8) List {
        return .{ .word_list = loadList(raw_list) };
    }
    /// Performs binary search on the word list
    /// as we assume that the list is alphabetically ordered.
    ///
    /// Returns null if the word isn't on the list
    pub fn getIndex(self: List, word: []const u8) ?u16 {
        if (word.len == 0)
            return null;

        var left: u16 = 0;
        var right: u16 = 2047;

        while (left <= right) {
            const middle = left + @divFloor(right - left, 2);

            const compare = std.mem.order(u8, self.word_list[middle], word);

            switch (compare) {
                .eq => return middle,
                .gt => right = middle - 1,
                .lt => left = middle + 1,
            }
        }

        return null;
    }

    fn loadList(raw_list: []const u8) [Wordlist.list_count][]const u8 {
        @setEvalBranchQuota(100000);

        var iter = std.mem.tokenize(u8, raw_list, "\n");
        var list_buffer: [Wordlist.list_count][]const u8 = undefined;

        var count: usize = 0;
        while (iter.next()) |word| {
            list_buffer[count] = word;
            count += 1;
        }

        return list_buffer;
    }
};

test "Index" {
    {
        const index = english.getIndex("actor");

        try testing.expectEqual(index.?, 21);
    }
}

test "English" {
    {
        const seed = "test test test test test test test test test test test junk";
        const entropy = try toEntropy(12, seed, null);

        const bar = try fromEntropy(testing.allocator, 12, entropy, null);
        defer testing.allocator.free(bar);

        try testing.expectEqualStrings(seed, bar);
    }
    {
        const seed = "test test test test test test test test test test test test";

        try testing.expectError(error.InvalidMnemonicChecksum, toEntropy(12, seed, null));
    }
    {
        const seed = "asdasdas test test test test test test test test test test test";

        try testing.expectError(error.InvalidMnemonicWord, toEntropy(12, seed, null));
    }
}
