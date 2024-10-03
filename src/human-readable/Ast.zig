const std = @import("std");
const token = @import("tokens.zig");
const tokenizer = @import("lexer.zig");

const Allocator = std.mem.Allocator;
const Parser = @import("ParserNew.zig");
const TokenTag = token.Tag.SoliditySyntax;

const Ast = @This();

/// Offset used in the parser.
pub const Offset = u32;

/// Index used for the parser.
pub const TokenIndex = u32;

/// Struct of arrays for the `Node` members.
pub const NodeList = std.MultiArrayList(Node);

/// Struct of arrays for the `Token.Tag` members.
pub const TokenList = std.MultiArrayList(struct {
    tag: TokenTag,
    start: Offset,
});

/// Source code slice.
source: [:0]const u8,
/// Struct of arrays containing the token tags
/// and token starts.
tokens: TokenList.Slice,
/// Struct of arrays containing all node information.
nodes: NodeList.Slice,
/// Slice of extra data produces by the parser.
extra_data: []const Node.Index,

pub fn parse(allocator: Allocator, source: [:0]const u8) Parser.ParserErrors!Ast {
    var tokens: TokenList = .{};
    var lexer = tokenizer.Lexer.init(source);

    while (true) {
        const tok = lexer.scan();
        try tokens.append(allocator, .{
            .tag = tok.syntax,
            .start = @intCast(tok.location.start),
        });

        if (tok.syntax == .EndOfFileToken) break;
    }

    var parser: Parser = .{
        .source = source,
        .allocator = allocator,
        .token_index = 0,
        .token_tags = tokens.items(.tag),
        .nodes = .{},
        .scratch = .empty,
        .extra = .empty,
    };
    defer parser.deinit();

    try parser.parseSource();

    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra.toOwnedSlice(allocator),
    };
}

/// Clears any allocated memory from the `Ast`.
pub fn deinit(self: *Ast, allocator: Allocator) void {
    self.tokens.deinit(allocator);
    self.nodes.deinit(allocator);
    allocator.free(self.extra_data);
}

pub fn functionProto(self: Ast, node: Node.Index) ast.ConstructorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .function_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const params = self.extraData(Node.FunctionProto, data.lhs);
    const return_params = self.extraData(Node.Range, data.rhs);

    var result: ast.FunctionDecl = .{
        .ast = .{
            .params = self.extra_data[params.params_start..params.params_end],
            .return_params = self.extra_data[return_params.start..return_params.end],
        },
        .main_token = main_token,
        .name = params.identifier,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[params.specifiers];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn functionProtoOne(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.FunctionDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .function_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];

    const params = self.extraData(Node.FunctionProtoOne, data.lhs);
    const return_params = self.extraData(Node.Range, data.rhs);
    node_buffer[0] = params.param;

    var result: ast.FunctionDecl = .{
        .ast = .{
            .params = if (params.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .return_params = self.extra_data[return_params.start..return_params.end],
        },
        .main_token = main_token,
        .name = params.identifier,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[params.specifiers];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn functionProtoMulti(self: Ast, node: Node.Index) ast.ConstructorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .function_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const params = self.extraData(Node.FunctionProtoMulti, data.lhs);

    var result: ast.FunctionDecl = .{
        .ast = .{
            .params = self.extra_data[params.params_start..params.params_end],
            .return_params = null,
        },
        .main_token = main_token,
        .name = params.identifier,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[data.rhs];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn functionProtoSimple(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.FunctionDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .function_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const params = self.extraData(Node.FunctionProtoSimple, data.lhs);
    node_buffer[0] = params.param;

    var result: ast.FunctionDecl = .{
        .ast = .{
            .params = if (params.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .return_params = null,
        },
        .main_token = main_token,
        .name = params.identifier,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[data.rhs];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn constructorProtoMulti(self: Ast, node: Node.Index) ast.ConstructorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .constructor_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const params = self.extraData(Node.Range, data.lhs);

    var result: ast.ConstructorDecl = .{
        .ast = .{
            .params = self.extra_data[params.start..params.end],
        },
        .main_token = main_token,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[data.rhs];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn constructorProtoSimple(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.ConstructorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .constructor_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.lhs;

    var result: ast.ConstructorDecl = .{
        .ast = .{
            .params = if (data.lhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main_token,
        .payable = null,
        .pure = null,
        .view = null,
        .external = null,
        .public = null,
        .override = null,
        .virtual = null,
    };

    const node_specifier = self.nodes.items(.main_token)[data.rhs];
    const specifiers = self.extraData(Node.Range, node_specifier);

    for (self.extra_data[specifiers.start..specifiers.end]) |index| {
        switch (self.tokens.items(.tag)[index]) {
            .Virtual => result.virtual = index,
            .Override => result.override = index,
            .Pure => result.pure = index,
            .Public => result.public = index,
            .View => result.view = index,
            .Payable => result.payable = index,
            .External => result.external = index,
        }
    }

    return result;
}

pub fn eventProtoMulti(self: Ast, node: Node.Index) ast.EventDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .event_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const extra = self.extraData(Node.Range, data.rhs);

    return .{
        .ast = .{
            .params = self.extra_data[extra.start..extra.end],
        },
        .main_token = main_token,
        .name = data.lhs,
        .anonymous = null,
    };
}

pub fn eventProtoSimple(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.ErrorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .event_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .ast = .{
            .params = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main_token,
        .name = data.lhs,
        .anonymous = null,
    };
}

pub fn errorProtoMulti(self: Ast, node: Node.Index) ast.ErrorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .error_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const extra = self.extraData(Node.Range, data.rhs);

    return .{
        .ast = .{
            .params = self.extra_data[extra.start..extra.end],
        },
        .main_token = main_token,
        .name = data.lhs,
    };
}

pub fn errorProtoSimple(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.ErrorDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .error_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .ast = .{
            .params = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main_token,
        .name = data.lhs,
    };
}

pub fn structDecl(self: Ast, node: Node.Index) ast.StructDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .struct_decl);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    const extra = self.extraData(Node.Range, data.rhs);

    return .{
        .ast = .{
            .members = self.extra_data[extra.start..extra.end],
        },
        .main_token = main_token,
        .name = data.lhs,
    };
}

pub fn structDeclOne(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.StructDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .struct_decl_one);

    const data = self.nodes.items(.data)[node];
    const main_token = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .ast = .{
            .members = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main_token,
        .name = data.lhs,
    };
}

pub fn extraData(self: Ast, comptime T: type, node: Node.Index) T {
    const fields = std.meta.fields(T);
    var result: T = undefined;

    inline for (fields, 0..) |field, i| {
        comptime std.debug.assert(field.type == Node.Index);

        @field(result, field.name) = self.extra_data[node + i];
    }

    return result;
}

pub fn firstToken(self: Ast, node: Node.Index) TokenIndex {
    const main = self.nodes.items(.main_token);
    const data = self.nodes.items(.data);
    const nodes = self.nodes.items(.tag);

    var current_node = node;

    while (true) {
        switch (nodes[current_node]) {
            .root => return 0,

            .elementary_type,
            .identifier,
            .function_proto_simple,
            .function_proto_multi,
            .function_proto_one,
            .function_proto,
            .constructor_proto_simple,
            .constructor_proto_multi,
            .error_proto_multi,
            .error_proto_simple,
            .event_proto_multi,
            .event_proto_simple,
            .tuple_type,
            .tuple_type_one,
            .struct_decl,
            .struct_decl_one,
            .unreachable_node,
            => return main[current_node],

            .array_type,
            .struct_field,
            .error_var_decl,
            .event_var_decl,
            .var_decl,
            => current_node = data[current_node].lhs,

            .specifiers,
            => {
                const extra = self.extraData(Node.Range, main[current_node]);

                return self.extra_data[extra.start];
            },
        }
    }
}

pub fn lastToken(self: Ast, node: Node.Index) TokenIndex {
    const main = self.nodes.items(.main_token);
    const data = self.nodes.items(.data);
    const nodes = self.nodes.items(.tag);

    var current_node = node;

    var end_offset: u32 = 0;

    while (true) {
        switch (nodes[current_node]) {
            .root => return @as(TokenIndex, @intCast(self.tokens.len - 1)),

            .array_type,
            .tuple_type,
            .tuple_type_one,
            => return 0 + end_offset,

            .elementary_type,
            .identifier,
            .unreachable_node,
            => return main[current_node] + end_offset,

            .error_var_decl,
            => {
                if (main[current_node] != 0)
                    return main[current_node] + end_offset;

                current_node = data[current_node].lhs;
            },

            .constructor_proto_simple,
            => {
                end_offset += 1;
                const specifiers_node = main[data[current_node].rhs];
                const range = self.extraData(Node.Range, specifiers_node);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    current_node = data[current_node].lhs;
                } else current_node = data[current_node].rhs;
            },
            .constructor_proto_multi,
            => {
                end_offset += 1;
                const specifiers_node = main[data[current_node].rhs];
                const range = self.extraData(Node.Range, specifiers_node);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    const proto = self.extraData(Node.Range, data[current_node].lhs);
                    current_node = self.extra_data[proto.end - 1];
                } else current_node = data[current_node].rhs;
            },
            .function_proto_simple,
            => {
                end_offset += 1;
                const specifiers_node = main[data[current_node].rhs];
                const range = self.extraData(Node.Range, specifiers_node);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    const proto = self.extraData(Node.FunctionProtoSimple, data[current_node].lhs);
                    current_node = proto.param;
                } else current_node = data[current_node].rhs;
            },
            .function_proto_multi,
            => {
                end_offset += 1;
                const specifiers_node = main[data[current_node].rhs];
                const range = self.extraData(Node.Range, specifiers_node);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    const proto = self.extraData(Node.FunctionProtoMulti, data[current_node].lhs);
                    current_node = self.extra_data[proto.params_end - 1];
                } else current_node = data[current_node].rhs;
            },

            .function_proto_one,
            .function_proto,
            .error_proto_multi,
            .event_proto_multi,
            .struct_decl,
            => {
                end_offset += 1;

                const extra = self.extraData(Node.Range, data[current_node].rhs);
                current_node = self.extra_data[extra.end - 1];
            },

            .error_proto_simple,
            .event_proto_simple,
            .struct_decl_one,
            => {
                end_offset += 1;
                current_node = data[current_node].rhs;
            },

            .struct_field,
            => {
                end_offset += 1;
                return main[current_node] + end_offset;
            },

            .event_var_decl,
            .var_decl,
            => {
                if (data[current_node].rhs != 0) {
                    return data[current_node].rhs + end_offset;
                } else if (main[current_node] != 0) {
                    return main[current_node] + end_offset;
                } else current_node = data[current_node].lhs;
            },

            .specifiers,
            => {
                const extra = self.extraData(Node.Range, main[current_node]);

                if (extra.end == 0)
                    return extra.end;

                return self.extra_data[extra.end - 1];
            },
        }
    }
}

pub fn tokenSlice(self: Ast, token_index: TokenIndex) []const u8 {
    const token_tag = self.tokens.items(.tag)[token_index];
    const token_start = self.tokens.items(.start)[token_index];

    var lexer: tokenizer.Lexer = .{
        .position = token_start,
        .currentText = self.source,
    };

    if (token_tag.lexToken()) |tok|
        return tok;

    const tok = lexer.scan();
    std.debug.assert(tok.syntax == token_tag);

    return self.source[tok.location.start..tok.location.end];
}

pub fn getNodeSource(self: Ast, node: Node.Index) []const u8 {
    const token_start = self.tokens.items(.start);

    const first = self.firstToken(node);
    const last = self.lastToken(node);

    const start = token_start[first];
    const end = token_start[last] + self.tokenSlice(last).len;

    return self.source[start..end];
}

pub const ast = struct {
    pub const ConstructorDecl = struct {
        ast: ComponentDecl,
        main_token: TokenIndex,
        view: ?TokenIndex,
        pure: ?TokenIndex,
        payable: ?TokenIndex,
        public: ?TokenIndex,
        external: ?TokenIndex,
        virtual: ?TokenIndex,
        override: ?TokenIndex,

        const ComponentDecl = struct {
            params: []const Node.Index,
        };
    };

    pub const FunctionDecl = struct {
        ast: ComponentDecl,
        main_token: TokenIndex,
        name: TokenIndex,
        view: ?TokenIndex,
        pure: ?TokenIndex,
        payable: ?TokenIndex,
        public: ?TokenIndex,
        external: ?TokenIndex,
        virtual: ?TokenIndex,
        override: ?TokenIndex,

        const ComponentDecl = struct {
            params: []const Node.Index,
            return_params: ?[]const Node.Index,
        };
    };

    pub const ErrorDecl = struct {
        ast: ComponentDecl,
        main_token: TokenIndex,
        name: TokenIndex,

        const ComponentDecl = struct {
            params: []const Node.Index,
        };
    };

    pub const EventDecl = struct {
        ast: ComponentDecl,
        main_token: TokenIndex,
        name: TokenIndex,
        anonymous: ?TokenIndex,

        const ComponentDecl = struct {
            params: []const Node.Index,
        };
    };

    pub const StructDecl = struct {
        ast: ComponentDecl,
        main_token: TokenIndex,
        name: TokenIndex,

        const ComponentDecl = struct {
            members: []const Node.Index,
        };
    };
};

pub const Node = struct {
    tag: Tag,
    data: Data,
    main_token: TokenIndex,

    pub const Index = u32;

    // Assert that out tag is always size 1.
    comptime {
        std.debug.assert(@sizeOf(Tag) == 1);
    }

    pub const Tag = enum {
        root,
        identifier,
        unreachable_node,

        constructor_proto_simple,
        constructor_proto_multi,

        event_proto_simple,
        event_proto_multi,

        error_proto_simple,
        error_proto_multi,

        function_proto,
        function_proto_one,
        function_proto_multi,
        function_proto_simple,

        array_type,
        elementary_type,
        tuple_type,
        tuple_type_one,

        specifiers,

        struct_decl,
        struct_decl_one,
        struct_field,

        var_decl,
        error_var_decl,
        event_var_decl,
    };

    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };

    pub const Range = struct {
        start: Index,
        end: Index,
    };

    pub const FunctionProto = struct {
        specifiers: Node.Index,
        identifier: TokenIndex,
        params_start: Node.Index,
        params_end: Node.Index,
    };

    pub const FunctionProtoOne = struct {
        specifiers: Node.Index,
        identifier: TokenIndex,
        param: Node.Index,
    };

    pub const FunctionProtoMulti = struct {
        identifier: TokenIndex,
        params_start: Node.Index,
        params_end: Node.Index,
    };

    pub const FunctionProtoSimple = struct {
        identifier: TokenIndex,
        param: Node.Index,
    };
};
