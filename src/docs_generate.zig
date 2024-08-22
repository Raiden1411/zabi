const std = @import("std");

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const File = std.fs.File;
const Tag = std.zig.Token.Tag;
const TokenIndex = std.zig.Ast.TokenIndex;

/// The state the generator is in whilst traversing the AST.
pub const LookupState = enum {
    public,
    constant_decl,
    fn_decl,
    none,
};

/// Parses and generates based on the `doc_comments` on the provided source code.
/// This writes as markdown text. `pub const` are written as H2 and
/// `pub fn` are written as H3.
pub const DocsGenerator = struct {
    /// The allocator used to manage memory.
    allocator: Allocator,
    /// The ast of the parsed source code.
    ast: Ast,
    /// The state of the lookup.
    state: LookupState,

    /// Starts the generaton and pre parses the source code.
    pub fn init(allocator: Allocator, source: [:0]const u8) !DocsGenerator {
        const ast = try Ast.parse(allocator, source, .zig);

        return .{
            .allocator = allocator,
            .ast = ast,
            .state = .none,
        };
    }
    /// Clears the allocated memory from the ast.
    pub fn deinit(self: *DocsGenerator) void {
        self.ast.deinit(self.allocator);
    }
    /// Extracts the `doc_comments` from the source code and writes them to `out_file`.
    /// Also extracts the function names and public constants as headers for markdown.
    pub fn extractDocs(self: *DocsGenerator, out_file: File) !void {
        const tokens: []const Tag = self.ast.tokens.items(.tag);

        for (tokens, 0..) |token, index| {
            switch (token) {
                .keyword_pub => self.state = .public,
                .keyword_const => self.state = if (self.state == .public) .constant_decl else continue,
                .keyword_fn => self.state = if (self.state == .public) .fn_decl else continue,
                .identifier => {
                    switch (self.state) {
                        .fn_decl => {
                            try out_file.writeAll("## ");

                            const func_name = self.ast.tokenSlice(@intCast(index));
                            const upper = std.ascii.toUpper(func_name[0]);

                            try out_file.writer().writeByte(upper);
                            try out_file.writeAll(func_name[1..]);

                            try out_file.writeAll("\n");

                            const doc_comments = try self.eatDocComments(@intCast(index - 2));
                            defer self.allocator.free(doc_comments);

                            try out_file.writeAll(doc_comments);

                            self.state = .none;
                        },
                        .constant_decl => {
                            try out_file.writeAll("## ");
                            try out_file.writeAll(self.ast.tokenSlice(@intCast(index)));
                            try out_file.writeAll("\n");

                            const doc_comments = try self.eatDocComments(@intCast(index - 2));
                            defer self.allocator.free(doc_comments);

                            try out_file.writeAll(doc_comments);

                            self.state = .none;
                        },
                        else => continue,
                    }
                },
                else => continue,
            }
        }
    }
    /// Traverses the ast to find the associated doc comments.
    ///
    /// Retuns an empty string if none can be found.
    pub fn eatDocComments(self: DocsGenerator, index: TokenIndex) ![]const u8 {
        const tokens = self.ast.tokens.items(.tag);

        const start_index: usize = start_index: for (0..index) |i| {
            const reverse_i = index - i - 1;
            const token = tokens[reverse_i];
            if (token != .doc_comment) break :start_index reverse_i + 1;
        } else unreachable;

        var lines = std.ArrayList([]const u8).init(self.allocator);
        errdefer lines.deinit();

        for (start_index..index + 1) |doc_index| {
            const token = tokens[doc_index];

            if (token != .doc_comment)
                break;

            const slice = self.ast.tokenSlice(@intCast(doc_index));

            const comments = slice[3..];

            if (comments.len == 0)
                continue;

            try lines.append(if (comments[0] != ' ') comments else comments[1..]);
        }

        const lines_slice = try lines.toOwnedSlice();
        defer self.allocator.free(lines_slice);

        var list = std.ArrayList(u8).init(self.allocator);
        errdefer list.deinit();

        var writer = list.writer();

        for (lines_slice, 0..) |line, i| {
            try writer.writeAll(line);

            if (i < lines_slice.len - 1 and line[line.len - 1] == '.')
                try writer.writeAll("\\");

            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");

        return list.toOwnedSlice();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const exclude_files = std.StaticStringMap(void).initComptime(.{
        // Files
        .{ "ws_server.zig", {} },
        .{ "rpc_server.zig", {} },
        .{ "ipc_server.zig", {} },
        .{ "docs_generate.zig", {} },
        .{ "constants.zig", {} },
        .{ "server.zig", {} },
        .{ "root.zig", {} },

        // Folders
        .{ "wordlists", {} },
    });

    var dir = try std.fs.cwd().openDir("src", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(gpa.allocator());
    defer walker.deinit();

    while (try walker.next()) |sub_path| {
        if (std.mem.endsWith(u8, sub_path.basename, "test.zig"))
            continue;

        if (exclude_files.get(sub_path.basename) != null)
            continue;

        switch (sub_path.kind) {
            .directory => {
                var buffer: [std.fs.max_path_bytes]u8 = undefined;
                const real_path = try sub_path.dir.realpath(sub_path.basename, &buffer);

                const out_name = try std.mem.replaceOwned(u8, gpa.allocator(), real_path, "src", "docs/pages/api");
                defer gpa.allocator().free(out_name);

                std.fs.makeDirAbsolute(out_name) catch |err| switch (err) {
                    error.PathAlreadyExists => continue,
                    else => return err,
                };
            },
            .file => {
                var buffer: [std.fs.max_path_bytes]u8 = undefined;
                const real_path = try sub_path.dir.realpath(sub_path.basename, &buffer);

                var file = try std.fs.openFileAbsolute(real_path, .{});
                defer file.close();

                const source = try file.readToEndAllocOptions(gpa.allocator(), std.math.maxInt(u32), null, @alignOf(u8), 0);
                defer gpa.allocator().free(source);

                const out_absolute_path = try std.mem.replaceOwned(u8, gpa.allocator(), real_path, "src", "docs/pages/api");
                defer gpa.allocator().free(out_absolute_path);

                const out_name = try std.mem.replaceOwned(u8, gpa.allocator(), out_absolute_path, ".zig", ".md");
                defer gpa.allocator().free(out_name);

                var out_file = try std.fs.createFileAbsolute(out_name, .{});
                defer out_file.close();

                var docs_gen = try DocsGenerator.init(gpa.allocator(), source);
                defer docs_gen.deinit();

                try docs_gen.extractDocs(out_file);
            },
            else => continue,
        }
    }
}
