const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const abi_source = @embedFile("abi/abi.zig");

    var ast = try std.zig.Ast.parse(gpa.allocator(), abi_source, .zig);
    defer ast.deinit(gpa.allocator());

    const tokens: []const std.zig.Token.Tag = ast.tokens.items(.tag);

    var state: State = .none;

    var abi_file = try std.fs.cwd().createFile("src/foo.md", .{});
    defer abi_file.close();

    for (tokens, 0..) |token, index| {
        switch (token) {
            .keyword_pub => state = .public,
            .keyword_const => state = if (state == .public) .constant_decl else continue,
            .keyword_fn => state = if (state == .public) .fn_decl else continue,
            .identifier => {
                switch (state) {
                    .fn_decl => {
                        try abi_file.writeAll("### ");

                        const func_name = ast.tokenSlice(@intCast(index));
                        const upper = std.ascii.toUpper(func_name[0]);

                        try abi_file.writer().writeByte(upper);
                        try abi_file.writeAll(func_name[1..]);

                        try abi_file.writeAll("\n");

                        const doc_comments = try eatDocComments(gpa.allocator(), @intCast(index - 2), ast, tokens);
                        defer gpa.allocator().free(doc_comments);

                        try abi_file.writeAll(doc_comments);

                        state = .none;
                    },
                    .constant_decl => {
                        try abi_file.writeAll("## ");
                        try abi_file.writeAll(ast.tokenSlice(@intCast(index)));
                        try abi_file.writeAll("\n");

                        const doc_comments = try eatDocComments(gpa.allocator(), @intCast(index - 2), ast, tokens);
                        defer gpa.allocator().free(doc_comments);

                        try abi_file.writeAll(doc_comments);

                        state = .none;
                    },
                    else => continue,
                }
            },
            else => continue,
        }
    }
}

pub const State = enum {
    public,
    constant_decl,
    fn_decl,
    none,
};

/// Traverses the ast to find the associated doc comments.
///
/// Retuns an empty string if none can be found.
fn eatDocComments(allocator: std.mem.Allocator, index: std.zig.Ast.TokenIndex, ast: std.zig.Ast, tokens: []const std.zig.Token.Tag) ![]const u8 {
    const start_index: usize = start_index: for (0..index) |i| {
        const reverse_i = index - i - 1;
        const token = tokens[reverse_i];
        if (token != .doc_comment) break :start_index reverse_i + 1;
    } else unreachable;

    var lines = std.ArrayList([]const u8).init(allocator);
    errdefer lines.deinit();

    for (start_index..index + 1) |doc_index| {
        const token = tokens[doc_index];

        if (token != .doc_comment)
            break;

        const slice = ast.tokenSlice(@intCast(doc_index));

        const comments = slice[3..];

        if (comments.len == 0)
            continue;

        try lines.append(if (comments[0] != ' ') comments else comments[1..]);
    }

    const lines_slice = try lines.toOwnedSlice();
    defer allocator.free(lines_slice);

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var writer = list.writer();

    for (lines_slice, 0..) |line, i| {
        try writer.writeAll(line);

        if (i < lines_slice.len - 1)
            try writer.writeAll("\\");

        try writer.writeAll("\n");
    }
    try writer.writeAll("\n");

    return list.toOwnedSlice();
}
