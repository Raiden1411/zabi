const std = @import("std");

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Dir = std.fs.Dir;
const File = std.fs.File;
const FnProto = Ast.full.FnProto;
const Tag = std.zig.Token.Tag;
const NodeIndex = Ast.Node.Index;
const NodeTag = Ast.Node.Tag;
const TokenIndex = std.zig.Ast.TokenIndex;

/// Files and folder to be excluded from the docs generation.
const exclude_files_and_folders = std.StaticStringMap(void).initComptime(.{
    // Files
    .{ "ws_server.zig", {} },
    .{ "rpc_server.zig", {} },
    .{ "ipc_server.zig", {} },
    .{ "docs_generate.zig", {} },
    .{ "constants.zig", {} },
    .{ "server.zig", {} },
    .{ "state_mutability.zig", {} },
    .{ "english.txt", {} },
    .{ "pipe.zig", {} },
    .{ "channel.zig", {} },
    .{ "root.zig", {} },

    // Folders
    .{ "wordlists", {} },
});

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
    /// The ast nodes from the souce file.
    nodes: []const NodeTag,
    /// The state of the lookup.
    state: LookupState,
    /// The token tags produced by zig's lexer.
    tokens: []const Tag,

    /// Starts the generaton and pre parses the source code.
    pub fn init(allocator: Allocator, source: [:0]const u8) !DocsGenerator {
        const ast = try Ast.parse(allocator, source, .zig);

        return .{
            .allocator = allocator,
            .ast = ast,
            .state = .none,
            .nodes = ast.nodes.items(.tag),
            .tokens = ast.tokens.items(.tag),
        };
    }
    /// Clears the allocated memory from the ast.
    pub fn deinit(self: *DocsGenerator) void {
        self.ast.deinit(self.allocator);
    }
    /// Extracts the `doc_comments` from the source code and writes them to `out_file`.
    /// Also extracts the function names and public constants as headers for markdown.
    pub fn extractDocs(self: *DocsGenerator, out_file: File) !void {
        var duplicate = std.StringHashMap(void).init(self.allocator);
        defer duplicate.deinit();

        for (self.nodes, 0..) |node, i| {
            switch (node) {
                .simple_var_decl => try self.extractFromSimpleVar(out_file, @intCast(i), &duplicate),
                .fn_decl => {
                    var buffer = [_]u32{@intCast(i)};
                    const fn_proto = self.ast.fullFnProto(&buffer, @intCast(i));

                    const proto = fn_proto orelse continue;

                    if (self.tokens[proto.visib_token orelse continue] != .keyword_pub)
                        continue;

                    const func_name = self.ast.tokenSlice(proto.name_token orelse continue);

                    if (duplicate.get(func_name) != null)
                        continue;

                    self.state = .fn_decl;
                    try self.extractFromFnProto(proto, out_file);
                },
                else => continue,
            }
        }
    }
    /// Traverses the ast to find the associated doc comments.
    ///
    /// Retuns an empty string if none can be found.
    pub fn extractDocComments(self: DocsGenerator, index: TokenIndex) ![]const u8 {
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

        if (lines_slice.len > 0)
            try writer.writeAll("\n");

        return list.toOwnedSlice();
    }
    /// Extracts the source and builds the mardown file when we have a `container_decl` or `tagged_union` node.
    pub fn extractFromContainerDecl(self: *DocsGenerator, out_file: File, init_node: NodeIndex, duplicate: *std.StringHashMap(void)) !void {
        const container = switch (self.nodes[init_node]) {
            .container_decl, .container_decl_trailing => self.ast.containerDecl(init_node),
            .tagged_union => self.ast.taggedUnion(init_node),
            .merge_error_sets => {
                try out_file.writeAll("```zig\n");
                try out_file.writeAll(self.ast.getNodeSource(init_node));
                try out_file.writeAll("\n```\n\n");
                return;
            },
            .container_decl_arg_trailing, .container_decl_arg => self.ast.containerDeclArg(init_node),
            .container_decl_two, .container_decl_two_trailing => self.ast.containerDeclTwo(@constCast(&.{ init_node, init_node }), init_node),
            // std.debug.print("FOOOO: {s}\n", .{self.ast.getNodeSource(init_node)});
            // return;
            else => return,
        };

        const container_token = self.ast.firstToken(init_node);

        switch (self.tokens[container_token]) {
            .keyword_struct, .keyword_union, .keyword_enum => {
                try out_file.writeAll("### Properties\n\n");
                try out_file.writeAll("```zig\n");

                switch (self.tokens[container_token]) {
                    .keyword_enum => try out_file.writeAll("enum {\n"),
                    .keyword_struct => try out_file.writeAll("struct {\n"),
                    .keyword_union => try out_file.writeAll("union(enum) {\n"),
                    else => unreachable,
                }

                var fn_idx: usize = 0;
                for (container.ast.members, 0..) |member, mem_idx| {
                    const first_token = self.ast.firstToken(member);

                    switch (self.tokens[first_token]) {
                        .identifier => {
                            // Grabs the first `doc_comment` index
                            const start_index: usize = start_index: for (0..first_token) |i| {
                                const reverse_i = first_token - i - 1;
                                const token = self.tokens[reverse_i];
                                if (token != .doc_comment) break :start_index reverse_i + 1;
                            } else unreachable;

                            for (start_index..first_token) |idx| {
                                try out_file.writeAll("  ");
                                try out_file.writeAll(self.ast.tokenSlice(@intCast(idx)));
                                try out_file.writeAll("\n");
                            }

                            try out_file.writeAll("  ");
                            try out_file.writeAll(self.ast.getNodeSource(member));
                            try out_file.writeAll("\n");
                        },
                        .keyword_pub => {
                            fn_idx = mem_idx;
                            break;
                        },
                        else => break,
                    }
                }
                try out_file.writeAll("}\n```\n\n");

                for (container.ast.members[fn_idx..]) |member| {
                    var buffer = [_]u32{member};

                    if (self.nodes[member] != .fn_decl)
                        return;

                    const fn_proto = self.ast.fullFnProto(&buffer, member);

                    const proto = fn_proto orelse return;

                    if (self.tokens[proto.visib_token orelse return] != .keyword_pub)
                        continue;

                    const func_name = self.ast.tokenSlice(proto.name_token orelse return);
                    try duplicate.put(func_name, {});

                    try self.extractFromFnProto(proto, out_file);
                }
            },
            else => return,
        }
    }
    /// Extracts the source and builds the mardown file when we have a `fn_decl` node.
    pub fn extractFromFnProto(self: *DocsGenerator, proto: FnProto, out_file: File) !void {
        const func_name = self.ast.tokenSlice(proto.name_token orelse unreachable);
        const upper = std.ascii.toUpper(func_name[0]);

        // Writes the function name
        switch (self.state) {
            .constant_decl => try out_file.writeAll("### "),
            .fn_decl => try out_file.writeAll("## "),
            .none, .public => unreachable,
        }

        try out_file.writer().writeByte(upper);
        try out_file.writeAll(func_name[1..]);
        try out_file.writeAll("\n");

        // Writes the docs
        const docs = try self.extractDocComments(proto.firstToken());
        defer self.allocator.free(docs);

        try out_file.writeAll(docs);

        // Writes the signature
        try out_file.writeAll("### Signature\n\n");
        try out_file.writeAll("```zig\n");
        try out_file.writeAll(self.ast.getNodeSource(proto.ast.proto_node));
        try out_file.writeAll("\n```\n\n");
    }
    /// Extracts the source and builds the mardown file when we have a `simple_var_decl` node.
    pub fn extractFromSimpleVar(self: *DocsGenerator, out_file: File, node_index: NodeIndex, duplicate: *std.StringHashMap(void)) !void {
        const variable = self.ast.simpleVarDecl(node_index);
        const first_token = variable.firstToken();

        if (self.tokens[first_token] != .keyword_pub)
            return;

        self.state = .constant_decl;

        try out_file.writeAll("## ");
        // Format -> .keyword_pub, .keyword_const, .identifier
        // So we move ahead by 2 tokens
        try out_file.writeAll(self.ast.tokenSlice(first_token + 2));
        try out_file.writeAll("\n\n");

        const comments = try self.extractDocComments(first_token);
        defer self.allocator.free(comments);

        try out_file.writeAll(comments);

        return self.extractFromContainerDecl(out_file, variable.ast.init_node, duplicate);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var dir = try std.fs.cwd().openDir("src", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(gpa.allocator());
    defer walker.deinit();

    while (try walker.next()) |sub_path| {
        if (std.mem.endsWith(u8, sub_path.basename, "test.zig"))
            continue;

        if (exclude_files_and_folders.get(sub_path.basename) != null)
            continue;

        switch (sub_path.kind) {
            .directory => createFolders(gpa.allocator(), sub_path.dir, sub_path.basename) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return err,
            },
            .file => try generateMarkdownFile(gpa.allocator(), sub_path.dir, sub_path.basename),
            else => continue,
        }
    }
}

/// Creates the folder that will contain the `md` files.
fn createFolders(allocator: Allocator, sub_path: Dir, basename: []const u8) !void {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const real_path = try sub_path.realpath(basename, &buffer);

    const out_name = try std.mem.replaceOwned(u8, allocator, real_path, "src", "docs/pages/api");
    defer allocator.free(out_name);

    try std.fs.makeDirAbsolute(out_name);
}
/// Generates the `md` files on the `docs` folder location.
fn generateMarkdownFile(allocator: Allocator, sub_path: Dir, basename: []const u8) !void {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const real_path = try sub_path.realpath(basename, &buffer);

    var file = try std.fs.openFileAbsolute(real_path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer allocator.free(source);

    const out_absolute_path = try std.mem.replaceOwned(u8, allocator, real_path, "src", "docs/pages/api");
    defer allocator.free(out_absolute_path);

    const out_name = try std.mem.replaceOwned(u8, allocator, out_absolute_path, ".zig", ".md");
    defer allocator.free(out_name);

    var out_file = try std.fs.createFileAbsolute(out_name, .{});
    defer out_file.close();

    var docs_gen = try DocsGenerator.init(allocator, source);
    defer docs_gen.deinit();

    try docs_gen.extractDocs(out_file);
}
