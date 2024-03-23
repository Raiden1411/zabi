const std = @import("std");

const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;

pub const English = Wordlist.loadRawList(@embedFile("path_to_file.txt"));

pub fn mnemonicToSeed(password: []const u8) ![64]u8 {
    var buffer: [64]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(buffer[0..], password, "mnemonic", 2048, HmacSha512);

    return buffer;
}

pub const Wordlist = struct {
    const List = @This();

    const list_count: u16 = 2048;

    word_list: [Wordlist.list_count][]const u8,

    pub fn loadRawList(raw_list: []const u8) List {
        return .{ .word_list = loadList(raw_list) };
    }

    fn loadList(raw_list: []const u8) [Wordlist.list_count][]const u8 {
        var iter = std.mem.tokenizeAny(u8, raw_list, "\n");
        var list_buffer: [Wordlist.list_count][]const u8 = undefined;

        while (iter.next()) |word| {
            list_buffer[iter.index] = word;
        }

        return list_buffer;
    }
};
