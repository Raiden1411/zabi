const std = @import("std");
const testing = std.testing;

const Explorer = @import("../../clients/BlockExplorer.zig");
const QueryParameters = Explorer.QueryParameters;

test "QueryParameters" {
    const value: QueryParameters = .{ .module = .account, .action = .balance, .options = .{ .page = 1 }, .apikey = "FOO" };

    {
        var request_buffer: [4 * 1024]u8 = undefined;
        var buf_writter = std.io.fixedBufferStream(&request_buffer);

        try value.buildQuery(.{ .bar = 69 }, buf_writter.writer());

        try testing.expectEqualStrings("?module=account&action=balance&bar=69&page=1&apikey=FOO", buf_writter.getWritten());
    }
    {
        var request_buffer: [4 * 1024]u8 = undefined;
        var buf_writter = std.io.fixedBufferStream(&request_buffer);

        try value.buildDefaultQuery(buf_writter.writer());

        try testing.expectEqualStrings("?module=account&action=balance&page=1&apikey=FOO", buf_writter.getWritten());
    }
}

test "All Ref Decls" {
    std.testing.refAllDecls(Explorer);
}
