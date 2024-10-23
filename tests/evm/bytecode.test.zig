const std = @import("std");
const testing = std.testing;

const JumpTable = @import("zabi-evm").bytecode.JumpTable;

test "JumpTable" {
    // With false as the initial value.
    {
        const table = try JumpTable.init(testing.allocator, false, 64);
        defer table.deinit(testing.allocator);

        try testing.expectEqual(8, table.bytes.len);
        try testing.expect(!table.isValid(1));

        table.set(0, true);
        try testing.expect(table.isValid(0));
        table.set(1, true);
        try testing.expect(table.isValid(1));
        try testing.expect(!table.isValid(64));
        try testing.expect(!table.isValid(63));
        table.set(63, true);
        try testing.expect(table.isValid(63));
    }

    // With true as the initial value.
    {
        const table = try JumpTable.init(testing.allocator, true, 64);
        defer table.deinit(testing.allocator);

        try testing.expectEqual(8, table.bytes.len);
        try testing.expect(!table.isValid(1));

        table.set(0, true);
        try testing.expect(table.isValid(0));
        table.set(1, true);
        try testing.expect(table.isValid(1));
        try testing.expect(!table.isValid(64));
        try testing.expect(!table.isValid(63));
        table.set(63, true);
        try testing.expect(table.isValid(63));
    }
}
