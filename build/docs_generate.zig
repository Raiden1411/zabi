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

/// Set of possible errors from the generation.
const CreateFolderErrors = Dir.MakeError || Allocator.Error || Dir.RealPathError;

/// Set of possible errors from the generation.
const CreateFileErrors = Allocator.Error || Dir.RealPathError || File.OpenError || File.ReadError || File.WriteError;

/// Set of possible errors when running the script.
const RunnerErrors = CreateFileErrors || CreateFolderErrors;

/// Files and folder to be excluded from the docs generation.
const excludes = std.StaticStringMap(void).initComptime(.{
    // Files
    .{ "abi_ens.zig", {} },
    .{ "abi_optimism.zig", {} },
    .{ "blst.h", {} },
    .{ "blst_aux.h", {} },
    .{ "build.zig", {} },
    .{ "build.zig.zon", {} },
    .{ "c.zig", {} },
    .{ "channel.zig", {} },
    .{ "constants.zig", {} },
    .{ "contracts.zig", {} },
    .{ "ipc_server.zig", {} },
    .{ "pipe.zig", {} },
    .{ "root.zig", {} },
    .{ "root_wasm.zig", {} },
    .{ "rpc_server.zig", {} },
    .{ "state_mutability.zig", {} },
    .{ "server.zig", {} },
    .{ "ws_server.zig", {} },

    // Folders
    .{ ".zig-cache", {} },
    .{ "blst", {} },
    .{ "tests_blobs", {} },
    .{ "tests", {} },
    .{ "wordlists", {} },
    .{ "wasm", {} },
    .{ "zig-out", {} },

    // Function declarations. Only used on `container_decl` tokens and alike.
    .{ "format", {} },
    .{ "jsonParseFromValue", {} },
    .{ "jsonParse", {} },
    .{ "jsonStringify", {} },
});

/// The state the generator is in whilst traversing the AST.
const LookupState = enum {
    public,
    constant_decl,
    fn_decl,
    none,
};

/// Root folders to generate documentation from.
const RootFolders = enum {
    src,
    pkg,
};

/// Parses and generates based on the `doc_comments` on the provided source code.
/// This writes the contents as markdown text.
///
/// Member functions are written as H3.
/// Functions from struct file like `Client.zig` are written as H2.
/// Structs, Unions and Enums `container_field_init` and `simple_var_decl` nodes will be written
/// with markdown support for shiki.
///
/// All functions will have their `Signature` exported so that it's possible
/// to see the arguments and return types.
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

    /// ArrayList writer used by the generator.
    pub const GeneratorWriter = std.ArrayList(u8).Writer;

    /// Starts the generaton and pre parses the source code.
    pub fn init(allocator: Allocator, source: [:0]const u8) Allocator.Error!DocsGenerator {
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
    pub fn extractDocs(self: *DocsGenerator) Allocator.Error![]const u8 {
        var content = std.ArrayList(u8).init(self.allocator);
        errdefer content.deinit();

        var duplicate = std.StringHashMap(void).init(self.allocator);
        defer duplicate.deinit();

        for (self.nodes, 0..) |node, index| {
            switch (node) {
                .simple_var_decl => try self.extractFromSimpleVar(content.writer(), @intCast(index), &duplicate),
                .fn_decl => {
                    self.state = .fn_decl;
                    try self.extractFromFnProto(@intCast(index), content.writer(), &duplicate);
                },
                else => continue,
            }
        }

        return content.toOwnedSlice();
    }
    /// Traverses the ast to find the associated doc comments.
    ///
    /// Retuns an empty string if none can be found.
    pub fn extractDocComments(self: DocsGenerator, index: TokenIndex) Allocator.Error![]const u8 {
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

            try lines.append(if (comments[0] != ' ') comments else comments[1..]);
        }

        const lines_slice = try lines.toOwnedSlice();
        defer self.allocator.free(lines_slice);

        var list = std.ArrayList(u8).init(self.allocator);
        errdefer list.deinit();

        var writer = list.writer();

        for (lines_slice) |line| {
            try writer.writeAll(line);

            try writer.writeAll("\n");
        }

        if (lines_slice.len > 0)
            try writer.writeAll("\n");

        return list.toOwnedSlice();
    }
    /// Extracts the source and builds the mardown file when we have a `container_decl*`, `tagged_union` or `merge_error_sets` node.
    pub fn extractFromContainerDecl(
        self: *DocsGenerator,
        out_file: GeneratorWriter,
        init_node: NodeIndex,
        duplicate: *std.StringHashMap(void),
    ) Allocator.Error!void {
        const container = self.ast.fullContainerDecl(@constCast(&.{ init_node, init_node }), init_node) orelse
            std.debug.panic("Unexpected token found: {s}\n", .{@tagName(self.nodes[init_node])});

        const container_token = self.ast.firstToken(init_node);

        try out_file.writeAll("### Properties\n\n");
        try out_file.writeAll("```zig\n");

        switch (self.tokens[container_token]) {
            .keyword_enum => try out_file.writeAll("enum {\n"),
            .keyword_struct => try out_file.writeAll("struct {\n"),
            .keyword_union => try out_file.writeAll("union(enum) {\n"),
            else => std.debug.panic("Unexpected node token found: {s}", .{@tagName(self.tokens[container_token])}),
        }

        for (container.ast.members) |member| {
            switch (self.nodes[member]) {
                .container_field_init => try self.extractFromContainerField(out_file, member),
                .fn_decl, .simple_var_decl => continue,
                else => std.debug.panic("Unexpected node token found: {s}", .{@tagName(self.nodes[member])}),
            }
        }
        try out_file.writeAll("}\n```\n\n");

        for (container.ast.members) |member| {
            switch (self.nodes[member]) {
                .fn_decl => try self.extractFromFnProto(member, out_file, duplicate),
                .simple_var_decl => try self.extractFromSimpleVar(out_file, member, duplicate),
                .container_field_init => continue,
                else => std.debug.panic("Unexpected node token found: {s}", .{@tagName(self.nodes[member])}),
            }
        }
    }
    /// Writes a container field from a `struct`, `union` or `enum` with their `doc_comment` tokens.
    pub fn extractFromContainerField(self: *DocsGenerator, out_file: GeneratorWriter, member: NodeIndex) Allocator.Error!void {
        const field = self.ast.containerFieldInit(member);
        const first_token = field.firstToken();

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
    }
    /// Extracts the source and builds the mardown file when we have a `fn_decl` node.
    pub fn extractFromFnProto(
        self: *DocsGenerator,
        index: NodeIndex,
        out_file: GeneratorWriter,
        duplicate: *std.StringHashMap(void),
    ) Allocator.Error!void {
        var buffer = [_]u32{@intCast(index)};
        const fn_proto = self.ast.fullFnProto(&buffer, @intCast(index)) orelse return;

        if (self.tokens[fn_proto.visib_token orelse return] != .keyword_pub)
            return;

        const func_name = self.ast.tokenSlice(fn_proto.name_token orelse return);
        const upper = std.ascii.toUpper(func_name[0]);

        switch (self.state) {
            .fn_decl => {
                if (duplicate.get(func_name) != null)
                    return;

                try out_file.writeAll("## ");
            },
            .constant_decl => {
                try duplicate.put(func_name, {});

                if (excludes.get(func_name) != null)
                    return;

                try out_file.writeAll("### ");
            },
            .none,
            .public,
            => unreachable,
        }

        try out_file.writeByte(upper);
        try out_file.writeAll(func_name[1..]);
        try out_file.writeAll("\n");

        // Writes the docs
        const docs = try self.extractDocComments(fn_proto.firstToken());
        defer self.allocator.free(docs);

        try out_file.writeAll(docs);

        // Writes the signature
        try out_file.writeAll("### Signature\n\n");
        try out_file.writeAll("```zig\n");
        try self.formatFnProto(fn_proto.ast.proto_node, out_file);
        // try out_file.writeAll(self.ast.getNodeSource(fn_proto.ast.proto_node));
        try out_file.writeAll("\n```\n\n");
    }
    /// Extracts the source and builds the mardown file when we have a `simple_var_decl` node.
    pub fn extractFromSimpleVar(
        self: *DocsGenerator,
        out_file: std.ArrayList(u8).Writer,
        node_index: NodeIndex,
        duplicate: *std.StringHashMap(void),
    ) Allocator.Error!void {
        const variable = self.ast.simpleVarDecl(node_index);
        const first_token = variable.firstToken();

        if (self.tokens[first_token] != .keyword_pub)
            return;

        switch (self.nodes[variable.ast.init_node]) {
            .container_decl,
            .container_decl_trailing,
            .container_decl_arg_trailing,
            .container_decl_arg,
            .container_decl_two_trailing,
            .container_decl_two,
            .tagged_union,
            .tagged_union_trailing,
            .tagged_union_two,
            .tagged_union_enum_tag,
            .tagged_union_enum_tag_trailing,
            => {
                try self.extractNameFromVariable(out_file, first_token);

                self.state = .constant_decl;
                return self.extractFromContainerDecl(out_file, variable.ast.init_node, duplicate);
            },
            .merge_error_sets,
            .call,
            .call_one,
            .error_set_decl,
            .array_type,
            .ptr_type,
            .identifier,
            .ptr_type_aligned,
            .struct_init,
            .struct_init_dot,
            .struct_init_one,
            .struct_init_comma,
            .struct_init_one_comma,
            .struct_init_dot_two,
            .struct_init_dot_two_comma,
            .@"catch",
            .field_access,
            .tagged_union_two_trailing,
            .struct_init_dot_comma,
            .address_of,
            .builtin_call_two,
            .switch_comma,
            => {
                try self.extractNameFromVariable(out_file, first_token);
                try out_file.writeAll("```zig\n");
                try out_file.writeAll(self.ast.getNodeSource(variable.ast.init_node));
                return out_file.writeAll("\n```\n\n");
            },
            .number_literal,
            .sub,
            .string_literal,
            => return,
            else => std.debug.panic("Unexpected token found: {s}\n", .{@tagName(self.nodes[variable.ast.init_node])}),
        }
    }
    /// Extracts the name from the token and writes it as H2 markdown file.
    pub fn extractNameFromVariable(self: *DocsGenerator, out_file: GeneratorWriter, first_token: TokenIndex) Allocator.Error!void {
        try out_file.writeAll("## ");
        // Format -> .keyword_pub, .keyword_const, .identifier
        // So we move ahead by 2 tokens
        std.debug.assert(self.tokens[first_token + 2] == .identifier); // Unexpected token.
        try out_file.writeAll(self.ast.tokenSlice(first_token + 2));
        try out_file.writeAll("\n\n");

        const comments = try self.extractDocComments(first_token);
        defer self.allocator.free(comments);

        try out_file.writeAll(comments);
    }
    /// Format function with 4 space indent for arguments if necessary.
    pub fn formatFnProto(self: *DocsGenerator, index: NodeIndex, writer: GeneratorWriter) !void {
        const source = self.ast.getNodeSource(index);
        var iter = std.mem.tokenizeAny(u8, source, "\n");

        const first = iter.next() orelse unreachable; // Expected at least one.
        try writer.writeAll(first);

        while (iter.next()) |slice| {
            const trimmed = std.mem.trimLeft(u8, slice, " ");

            switch (trimmed[0]) {
                ')', '}' => {
                    try writer.writeAll("\n");
                    try writer.writeAll(trimmed);
                },
                else => {
                    try writer.writeAll("\n");
                    try writer.writeAll("    ");
                    try writer.writeAll(trimmed);
                },
            }
        }
    }
};

/// Main runner that will extract the documentation from `zabi` source code.
/// Will create folders and files as needed. It overrides all previous information on
/// any previously created file.
const Runner = struct {
    /// The runners allocator.
    allocator: Allocator,

    /// Creates the runners initial state.
    pub fn init(allocator: Allocator) Runner {
        return .{ .allocator = allocator };
    }
    /// Runs the generation for all targeted root folders.
    pub fn run(self: Runner) RunnerErrors!void {
        // Makes it easier if we want to add a new root folder to search from.
        inline for (@typeInfo(RootFolders).@"enum".fields) |field| {

            // Creates the documentation tree based on the current `RootFolders`.
            try self.generateDocumentationFromFolder(@enumFromInt(field.value));
        }
    }
    /// Creates the folder that will contain the `md` files.
    pub fn createFolders(self: Runner, sub_path: Dir.Walker.Entry) CreateFolderErrors!void {
        var path = std.ArrayList(u8).init(self.allocator);
        errdefer path.deinit();

        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        var path_writer = path.writer();

        try path_writer.print("{s}{s}{s}", .{
            try std.fs.cwd().realpath(".", &buffer),
            "/docs/pages/api/",
            sub_path.path,
        });

        const joined = try path.toOwnedSlice();
        defer self.allocator.free(joined);

        try std.fs.makeDirAbsolute(joined);
    }
    /// Generates the `md` files on the `docs/pages/api` folder location.
    pub fn createMarkdownFile(self: Runner, sub_path: Dir.Walker.Entry) CreateFileErrors!void {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const real_path = try sub_path.dir.realpath(sub_path.basename, &buffer);

        var file = try std.fs.openFileAbsolute(real_path, .{});
        defer file.close();

        const source = try file.readToEndAllocOptions(self.allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
        defer self.allocator.free(source);

        var path = std.ArrayList(u8).init(self.allocator);
        errdefer path.deinit();

        var path_writer = path.writer();

        try path_writer.print("{s}{s}{s}{s}", .{
            try std.fs.cwd().realpath(".", &buffer),
            "/docs/pages/api/",
            sub_path.path[0 .. sub_path.path.len - 3],
            "md",
        });

        const joined = try path.toOwnedSlice();

        var out_file = try std.fs.createFileAbsolute(joined, .{});
        defer out_file.close();

        var docs_gen = try DocsGenerator.init(self.allocator, source);
        defer docs_gen.deinit();

        const slice = try docs_gen.extractDocs();
        defer self.allocator.free(slice);

        try out_file.writeAll(slice);
    }
    /// Generates the documentation based on a `RootFolders` member.
    pub fn generateDocumentationFromFolder(self: Runner, search_root_folder: RootFolders) RunnerErrors!void {
        var dir = try std.fs.cwd().openDir(@tagName(search_root_folder), .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |sub_path| {
            switch (sub_path.kind) {
                .directory => {
                    if (excludes.get(sub_path.basename) != null) {
                        var curr = walker.stack.pop();
                        curr.iter.dir.close();

                        continue;
                    }

                    self.createFolders(sub_path) catch |err| switch (err) {
                        error.PathAlreadyExists => continue,
                        else => return err,
                    };
                },
                .file => {
                    if (excludes.get(sub_path.basename) != null)
                        continue;

                    try self.createMarkdownFile(sub_path);
                },
                else => continue,
            }
        }
    }
};

pub fn main() RunnerErrors!void {
    const allocator = std.heap.c_allocator;
    const runner = Runner.init(allocator);

    try runner.run();
}
