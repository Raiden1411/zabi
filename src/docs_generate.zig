const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const abi_source = @embedFile("abi/abi.zig");

    var ast = try std.zig.Ast.parse(gpa.allocator(), abi_source, .zig);
    defer ast.deinit(gpa.allocator());

    const tokens: []const std.zig.Token.Tag = ast.tokens.items(.tag);

    var index: u32 = 0;
    var state: State = .none;

    var abi_file = try std.fs.cwd().createFile("src/foo.md", .{});
    defer abi_file.close();

    while (index < tokens.len) : (index += 1) {
        const token = tokens[index];

        switch (token) {
            .keyword_pub => state = .public,
            .keyword_const => state = if (state == .public) .constant_decl else continue,
            .keyword_fn => state = if (state == .public) .fn_decl else continue,
            .identifier => {
                switch (state) {
                    .fn_decl => {
                        try abi_file.writeAll("\n### ");
                        try abi_file.writeAll(ast.tokenSlice(index));
                        try abi_file.writeAll("\n");

                        const doc_comments = try eatDocComments(gpa.allocator(), index - 2, ast, tokens);
                        defer gpa.allocator().free(doc_comments);

                        try abi_file.writeAll(doc_comments);

                        state = .none;
                    },
                    .constant_decl => {
                        try abi_file.writeAll("\n## ");
                        try abi_file.writeAll(ast.tokenSlice(index));
                        try abi_file.writeAll("\n");

                        const doc_comments = try eatDocComments(gpa.allocator(), index - 2, ast, tokens);
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

        try lines.append(slice[3..]);
    }

    const lines_slice = try lines.toOwnedSlice();
    defer allocator.free(lines_slice);

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var writer = list.writer();

    for (lines_slice) |line| {
        try writer.writeAll(line);
        try writer.writeAll("\n");
    }

    return list.toOwnedSlice();
}
