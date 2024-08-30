const english = @import("../../crypto/mnemonic.zig").english;
const std = @import("std");
const testing = std.testing;

const fromEntropy = @import("../../crypto/mnemonic.zig").fromEntropy;
const toEntropy = @import("../../crypto/mnemonic.zig").toEntropy;

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
