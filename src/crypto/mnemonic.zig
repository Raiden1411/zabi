const std = @import("std");
const testing = std.testing;

const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;

pub const English = Wordlist.loadRawList(@embedFile("wordlists/english.txt"));

pub fn mnemonicToSeed(password: []const u8) ![64]u8 {
    var buffer: [64]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(buffer[0..], password, "mnemonic", 2048, HmacSha512);

    return buffer;
}

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
            const ceil = std.math.divCeil(u16, right - left, 2) catch unreachable;
            const middle = left + ceil;

            const compare = std.mem.order(u8, self.word_list[middle], word);

            switch (compare) {
                .eq => return middle,
                .gt => right = middle + 1,
                .lt => left = middle - 1,
            }
        }

        return null;
    }

    fn loadList(raw_list: []const u8) [Wordlist.list_count][]const u8 {
        @setEvalBranchQuota(50000);

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
    const index = English.getIndex("actor");

    try testing.expectEqual(index.?, 21);
}
