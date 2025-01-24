const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Allocator = std.mem.Allocator;
const Parser = @import("Parser.zig");
const Token = tokenizer.Token;

const Ast = @This();

/// Offset used in the parser.
pub const Offset = u32;

/// Index used for the parser.
pub const TokenIndex = u32;

/// Struct of arrays for the `Node` members.
pub const NodeList = std.MultiArrayList(Node);

/// Struct of arrays for the `Token.Tag` members.
pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
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
/// Slice of errors that appended in parsing.
errors: []const Error,

/// Clears any allocated memory from the `Ast`.
pub fn deinit(
    self: *Ast,
    allocator: Allocator,
) void {
    self.tokens.deinit(allocator);
    self.nodes.deinit(allocator);
    allocator.free(self.extra_data);
    allocator.free(self.errors);
}

/// Parses the source code and builds the ast.
pub fn parse(
    allocator: Allocator,
    source: [:0]const u8,
) Parser.ParserErrors!Ast {
    var tokens: Ast.TokenList = .{};
    defer tokens.deinit(allocator);

    var lexer = tokenizer.Tokenizer.init(source);

    outer: while (true) {
        const bytes_left = lexer.buffer.len - lexer.index;
        const estimated = @max(64, bytes_left / 8);
        try tokens.ensureUnusedCapacity(allocator, estimated);

        for (0..estimated) |_| {
            const token = lexer.next();
            tokens.appendAssumeCapacity(.{
                .tag = token.tag,
                .start = @intCast(token.location.start),
            });

            if (token.tag == .eof) break :outer;
        }
    }

    var parser: Parser = .{
        .source = source,
        .allocator = allocator,
        .token_index = 0,
        .token_tags = tokens.items(.tag),
        .token_starts = tokens.items(.start),
        .nodes = .{},
        .errors = .empty,
        .scratch = .empty,
        .extra_data = .empty,
    };
    defer parser.deinit();

    try parser.nodes.ensureTotalCapacity(allocator, tokens.len + 1);

    try parser.parseSource();

    parser.nodes.shrinkAndFree(allocator, parser.nodes.len);
    parser.extra_data.shrinkAndFree(allocator, parser.extra_data.items.len);
    parser.errors.shrinkAndFree(allocator, parser.errors.items.len);

    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra_data.toOwnedSlice(allocator),
        .errors = try parser.errors.toOwnedSlice(allocator),
    };
}
/// Ast representation of a `array_type` node.
pub fn arrayType(
    self: Ast,
    node: Node.Index,
) ast.ArrayType {
    std.debug.assert(self.nodes.items(.tag)[node] == .array_type);

    const data = self.nodes.items(.data)[node];
    const lbracket = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .expr = data.rhs,
            .type_expr = data.lhs,
        },
        .l_bracket = lbracket,
    };
}
/// Ast representation of a `variable_decl` node.
pub fn variableDecl(
    self: Ast,
    node: Node.Index,
) ast.VariableDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .variable_decl);

    const data = self.nodes.items(.data)[node];
    const type_expr = self.nodes.items(.main_token)[node];
    const token_tags = self.tokens.items(.tag);

    var result: ast.VariableDecl = .{
        .ast = .{
            .type_expr = type_expr,
        },
        .memory = null,
        .storage = null,
        .calldata = null,
        .name = if (data.rhs == 0) null else data.rhs,
    };

    if (data.lhs != 0) {
        switch (token_tags[data.lhs]) {
            .keyword_memory => result.memory = data.lhs,
            .keyword_storage => result.storage = data.lhs,
            .keyword_calldata => result.calldata = data.lhs,
            else => {},
        }
    }

    return result;
}
/// Ast representation of a `constant_variable_decl` node.
pub fn constantVariableDecl(
    self: Ast,
    node: Node.Index,
) ast.ConstantVariableDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .constant_variable_decl);

    const data = self.nodes.items(.data)[node];
    const identifier = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .type_token = data.lhs,
            .expression_node = data.rhs,
        },
        .name = identifier,
    };
}
/// Ast representation of a `state_variable_decl` node.
pub fn stateVariableDecl(
    self: Ast,
    node: Node.Index,
) ast.StateVariableDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .state_variable_decl);

    const nodes = self.nodes.items(.tag);
    const data = self.nodes.items(.data)[node];
    const state = self.nodes.items(.main_token)[node];
    const token_tags = self.tokens.items(.tag);

    var result: ast.StateVariableDecl = .{
        .ast = .{
            .type_token = data.lhs,
            .expression_node = data.rhs,
        },
        .constant = null,
        .public = null,
        .immutable = null,
        .private = null,
        .internal = null,
        .override = null,
    };

    std.debug.assert(token_tags.len > state);

    const modifier_range = self.extraData(state, Node.Range);
    const modifier_node = self.extra_data[modifier_range.start..modifier_range.end];

    for (modifier_node) |state_mod| {
        switch (token_tags[state_mod]) {
            .keyword_public => result.public = state_mod,
            .keyword_private => result.private = state_mod,
            .keyword_internal => result.internal = state_mod,
            .keyword_constant => result.constant = state_mod,
            .keyword_immutable => result.immutable = state_mod,
            .keyword_override => result.override = state_mod,
            else => {
                if (nodes.len > state and nodes[state] == .override_specifier) {
                    result.override = self.nodes.items(.main_token)[state];
                }
            },
        }
    }

    return result;
}
/// Ast representation of a `using_directive_multi` node.
pub fn usingDirectiveMulti(
    self: Ast,
    node: Node.Index,
) ast.UsingDirective {
    std.debug.assert(self.nodes.items(.tag)[node] == .using_directive_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.UsingDirectiveMulti);
    const aliases = self.extra_data[proto.aliases_start..proto.aliases_end];

    return .{
        .ast = .{
            .aliases = aliases,
            .target_type = proto.target_type,
        },
        .for_alias = proto.for_alias,
        .main_token = main,
        .global = data.rhs,
    };
}
/// Ast representation of a `using_directive` node.
///
/// Ask for a owned buffer so that it can represent the aliases slice.
pub fn usingDirective(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.UsingDirective {
    std.debug.assert(self.nodes.items(.tag)[node] == .using_directive);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.UsingDirective);
    node_buffer[0] = proto.aliases;

    return .{
        .ast = .{
            .aliases = if (proto.aliases == 0) node_buffer[0..0] else node_buffer[0..1],
            .target_type = proto.target_type,
        },
        .for_alias = proto.for_alias,
        .main_token = main,
        .global = data.rhs,
    };
}
/// Ast representation of a `do_while` node.
pub fn doWhileStatement(
    self: Ast,
    node: Node.Index,
) ast.DoWhileStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .do_while);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .then_expression = data.lhs,
            .while_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `while` node.
pub fn whileStatement(
    self: Ast,
    node: Node.Index,
) ast.WhileStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .@"while");

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .condition = data.lhs,
            .then_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `if_simple` node.
pub fn ifSimpleStatement(
    self: Ast,
    node: Node.Index,
) ast.IfStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .if_simple);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .condition = data.lhs,
            .then_expression = data.rhs,
            .else_expression = null,
        },
        .main_token = main,
    };
}
/// Ast representation of a `if` node.
pub fn ifStatement(
    self: Ast,
    node: Node.Index,
) ast.IfStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .@"if");

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.If);

    return .{
        .ast = .{
            .condition = data.lhs,
            .then_expression = proto.then_expression,
            .else_expression = proto.else_expression,
        },
        .main_token = main,
    };
}
/// Ast representation of a `for` node.
pub fn forStatement(
    self: Ast,
    node: Node.Index,
) ast.ForStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .@"for");

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.For);

    return .{
        .ast = .{
            .assign_expr = proto.condition_one,
            .condition = proto.condition_two,
            .increment = proto.condition_three,
            .then_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `modifier_proto` node.
pub fn modifierProto(
    self: Ast,
    node: Node.Index,
) ast.ModifierProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .modifier_proto);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.ModifierProto);
    const params = self.extra_data[proto.params_start..proto.params_end];

    const specifiers_node = self.nodes.items(.main_token)[data.rhs];
    const range = self.extraData(specifiers_node, Node.Range);
    const specifiers = self.extra_data[range.start..range.end];

    return .{
        .main_token = main,
        .name = proto.identifier,
        .ast = .{
            .params = params,
            .specifiers = specifiers,
        },
    };
}
/// Ast representation of a `modifier_proto_one` node.
pub fn modifierProtoOne(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ModifierProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .modifier_proto_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.ModifierProtoOne);
    node_buffer[0] = proto.param;

    const extra = self.extraData(data.rhs, Node.Range);
    const specifiers = self.extra_data[extra.start..extra.end];

    return .{
        .main_token = main,
        .name = proto.identifier,
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .specifiers = specifiers,
        },
    };
}
/// Ast representation of a `user_defined_type` node.
pub fn userDefinedTypeDecl(
    self: Ast,
    node: Node.Index,
) ast.UserDefinedTypeDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .user_defined_type);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .target_type = data.rhs,
        },
        .main_token = main,
        .name = data.lhs,
    };
}
/// Ast representation of a `construct_decl_one` node.
pub fn constructorDecl(
    self: Ast,
    node: Node.Index,
) ast.ConstructorDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .construct_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.ConstructorProto);
    const extra = self.extraData(proto.specifiers, Node.Range);

    const params = self.extra_data[proto.params_start..proto.params_end];
    const specifiers = self.extra_data[extra.start..extra.end];

    return .{
        .main_token = main,
        .ast = .{
            .params = params,
            .body = data.rhs,
            .specifiers = specifiers,
        },
    };
}
/// Ast representation of a `construct_decl_one`.
pub fn constructorDeclOne(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ConstructorDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .construct_decl_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.ConstructorProtoOne);
    node_buffer[0] = proto.param;

    const extra = self.extraData(proto.specifiers, Node.Range);
    const specifiers = self.extra_data[extra.start..extra.end];

    return .{
        .main_token = main,
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .body = data.rhs,
            .specifiers = specifiers,
        },
    };
}
/// Ast representation of a `event_proto_simple` node.
pub fn eventProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.EventProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .event_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.rhs, Node.EventProtoOne);
    node_buffer[0] = proto.params;

    return .{
        .ast = .{
            .params = if (proto.params == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main,
        .name = data.lhs,
        .anonymous = if (proto.anonymous != 0) proto.anonymous else null,
    };
}
/// Ast representation of a `event_proto_multi` node.
pub fn eventProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.EventProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .event_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.rhs, Node.EventProto);
    const params = self.extra_data[proto.params_start..proto.params_end];

    return .{
        .ast = .{
            .params = params,
        },
        .main_token = main,
        .name = data.lhs,
        .anonymous = if (proto.anonymous != 0) proto.anonymous else null,
    };
}
/// Ast representation of a `error_proto_simple` node.
pub fn errorProtoSimple(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.ErrorProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .error_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .ast = .{
            .params = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main,
        .name = data.lhs,
    };
}
/// Ast representation of a `error_proto_multi` node.
pub fn errorProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.ErrorProto {
    std.debug.assert(self.nodes.items(.tag)[node] == .error_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const range = self.extraData(data.rhs, Node.Range);
    const fields = self.extra_data[range.start..range.end];

    return .{
        .ast = .{
            .params = fields,
        },
        .name = data.lhs,
        .main_token = main,
    };
}
/// Ast representation of a `enum_decl_one` node.
pub fn enumDeclOne(self: Ast, node_buffer: *[1]Node.Index, node: Node.Index) ast.EnumDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .enum_decl_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .fields = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        .main_token = main,
        .name = data.lhs,
    };
}
/// Ast representation of a `import_directive_symbol_one` node.
pub fn importDeclSymbolOne(
    self: Ast,
    buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ImportDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .import_directive_symbol_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.ImportSymbolOne);
    buffer[0] = extra.symbol;

    return .{
        .ast = .{
            .symbols = if (extra.symbol == 0) buffer[0..0] else buffer[0..1],
        },
        .name = null,
        .from = extra.from,
        .path = data.rhs,
        .main_token = main,
    };
}
/// Ast representation of a `import_directive_symbol` node.
pub fn importDeclSymbol(self: Ast, node: Node.Index) ast.ImportDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .import_directive_symbol);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.ImportSymbol);
    const symbols = self.extra_data[extra.symbol_start..extra.symbol_end];

    return .{
        .ast = .{
            .symbols = symbols,
        },
        .name = null,
        .from = extra.from,
        .path = data.rhs,
        .main_token = main,
    };
}
/// Ast representation of a `import_directive_asterisk` node.
pub fn importDeclAsterisk(
    self: Ast,
    node: Node.Index,
) ast.ImportDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .import_directive_asterisk);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.ImportAsterisk);

    return .{
        .ast = .{
            .symbols = null,
        },
        .name = extra.identifier,
        .from = extra.from,
        .path = data.rhs,
        .main_token = main,
    };
}
/// Ast representation of a `import_directive_path` node.
pub fn importDeclPath(self: Ast, node: Node.Index) ast.ImportDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .import_directive_path or
        self.nodes.items(.tag)[node] == .import_directive_path_identifier);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .symbols = null,
        },
        .name = if (data.rhs == 0) null else data.lhs,
        .path = data.lhs,
        .main_token = main,
        .from = null,
    };
}
/// Ast representation of a `mapping_decl` node.
pub fn mappingDecl(
    self: Ast,
    node: Node.Index,
) ast.MappingDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .mapping_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .left = data.lhs,
            .right = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `enum_decl` node.
pub fn enumDecl(self: Ast, node: Node.Index) ast.EnumDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .enum_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const range = self.extraData(data.rhs, Node.Range);
    const fields = self.extra_data[range.start..range.end];

    return .{
        .fields = fields,
        .name = data.lhs,
        .main_token = main,
    };
}
/// Ast representation of a `function_proto` node.
///
/// Asks for a owned buffer to pass as the slice of return values.
pub fn functionProto(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_proto);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProto);
    const extra = self.extraData(data.rhs, Node.Range);

    const specifiers_node = self.nodes.items(.main_token)[proto.specifiers];
    const range = self.extraData(specifiers_node, Node.Range);
    const specifiers = self.extra_data[range.start..range.end];

    const params = self.extra_data[proto.params_start..proto.params_end];
    node_buffer[0] = extra.start;

    return .{
        .ast = .{
            .params = params,
            .returns = if (extra.start == extra.end) node_buffer[0..1] else self.extra_data[extra.start..extra.end],
            .specifiers = specifiers,
        },
        .main_token = main,
        .name = proto.identifier,
    };
}
/// Ast representation of a `function_proto_one` node.
///
/// Asks for a owned buffer to pass as the slice of return and param values.
pub fn functionProtoOne(
    self: Ast,
    node_buffer: *[2]Node.Index,
    node: Node.Index,
) ast.FunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_proto_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoOne);
    const extra = self.extraData(data.rhs, Node.Range);

    const specifiers_node = self.nodes.items(.main_token)[proto.specifiers];
    const range = self.extraData(specifiers_node, Node.Range);
    const specifiers = self.extra_data[range.start..range.end];

    node_buffer[0] = proto.param;
    node_buffer[1] = extra.start;

    return .{
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .returns = if (extra.start == extra.end) node_buffer[1..2] else self.extra_data[extra.start..extra.end],
            .specifiers = specifiers,
        },
        .main_token = main,
        .name = proto.identifier,
    };
}
/// Ast representation of a `function_proto_multi` node.
pub fn functionMulti(
    self: Ast,
    node: Node.Index,
) ast.FunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_proto_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProto);

    const specifiers_node = self.nodes.items(.main_token)[proto.specifiers];
    const range = self.extraData(specifiers_node, Node.Range);
    const specifiers = self.extra_data[range.start..range.end];

    const params = self.extra_data[proto.params_start..proto.params_end];

    return .{
        .ast = .{
            .params = params,
            .specifiers = specifiers,
            .returns = null,
        },
        .main_token = main,
        .name = proto.identifier,
    };
}
/// Ast representation of a `function_proto_simple` node.
///
/// Asks for a owned buffer to pass as the slice of param values.
pub fn functionProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_proto_simple);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoOne);

    const specifiers_node = self.nodes.items(.main_token)[proto.specifiers];
    const range = self.extraData(specifiers_node, Node.Range);

    const specifiers = self.extra_data[range.start..range.end];
    node_buffer[0] = proto.param;

    return .{
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .returns = null,
            .specifiers = specifiers,
        },
        .main_token = main,
        .name = proto.identifier,
    };
}
/// Ast representation of a `function_type` node.
///
/// Asks for a owned buffer to pass as the slice of return values.
pub fn functionTypeProto(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionTypeDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_type);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoType);
    const extra = self.extraData(data.rhs, Node.Range);

    const params = self.extra_data[proto.params_start..proto.params_end];
    node_buffer[0] = extra.start;

    return .{
        .ast = .{
            .params = params,
            .returns = if (extra.start == extra.end) node_buffer[0..1] else self.extra_data[extra.start..extra.end],
        },
        .visibility = if (proto.visibility != 0) proto.visibility else null,
        .mutability = if (proto.mutability != 0) proto.mutability else null,
        .main_token = main,
    };
}
/// Ast representation of a `function_type_one`.
///
/// Asks for a owned buffer to pass as the slice of return and param values.
pub fn functionTypeProtoOne(
    self: Ast,
    node_buffer: *[2]Node.Index,
    node: Node.Index,
) ast.FunctionTypeDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_type_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoTypeOne);
    const extra = self.extraData(data.rhs, Node.Range);

    node_buffer[0] = proto.param;
    node_buffer[1] = extra.start;

    return .{
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .returns = if (extra.start == extra.end) node_buffer[1..2] else self.extra_data[extra.start..extra.end],
        },
        .visibility = if (proto.visibility != 0) proto.visibility else null,
        .mutability = if (proto.mutability != 0) proto.mutability else null,
        .main_token = main,
    };
}
/// Ast representation of a `function_type_multi` node.
pub fn functionTypeMulti(
    self: Ast,
    node: Node.Index,
) ast.FunctionTypeDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_type_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoType);

    const params = self.extra_data[proto.params_start..proto.params_end];

    return .{
        .ast = .{
            .params = params,
            .returns = null,
        },
        .visibility = if (proto.visibility != 0) proto.visibility else null,
        .mutability = if (proto.mutability != 0) proto.mutability else null,
        .main_token = main,
    };
}
/// Ast representation of a `function_type_simple` node.
///
/// Asks for a owned buffer to pass as the slice of return and param values.
pub fn functionTypeProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionTypeDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .function_type_simple);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.FnProtoTypeOne);
    node_buffer[0] = proto.param;

    return .{
        .ast = .{
            .params = if (proto.param == 0) node_buffer[0..0] else node_buffer[0..1],
            .returns = null,
        },
        .visibility = if (proto.visibility != 0) proto.visibility else null,
        .mutability = if (proto.mutability != 0) proto.mutability else null,
        .main_token = main,
    };
}
/// Ast representation of a `contract_decl`, `interface_decl`, `abstract_decl`
pub fn structDeclOne(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.StructDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .struct_decl_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];
    node_buffer[0] = data.rhs;

    return .{
        .ast = .{
            .fields = if (data.rhs == 0) node_buffer[0..0] else node_buffer[0..1],
        },
        .main_token = main,
        .name = data.lhs,
    };
}
/// Ast representation of a `struct_decl` node.
pub fn structDecl(
    self: Ast,
    node: Node.Index,
) ast.StructDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .struct_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];
    const range = self.extraData(data.rhs, Node.Range);
    const fields = self.extra_data[range.start..range.end];

    return .{
        .ast = .{
            .fields = fields,
        },
        .name = data.lhs,
        .main_token = main,
    };
}
/// Ast representation of a `contract_decl`, `interface_decl`, `abstract_decl` and `library_decl`.
pub fn contractDecl(
    self: Ast,
    node: Node.Index,
) ast.ContractDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .contract_decl or
        nodes[node] == .library_decl or
        nodes[node] == .interface_decl or
        nodes[node] == .abstract_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .body = data.rhs,
            .inheritance = null,
        },
        .main_token = main,
        .name = data.lhs,
    };
}
/// Ast representation of a `contract_decl_one`, `interface_decl_inheritance_one`, `abstract_decl_inheritance_one`
///
/// Asks for a owned buffer so that we can use as the slice of inheritance nodes.
pub fn contractDeclInheritanceOne(
    self: Ast,
    buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ContractDecl {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .contract_decl_inheritance_one or
        nodes[node] == .interface_decl_inheritance_one or
        nodes[node] == .abstract_decl_inheritance_one);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.ContractInheritanceOne);
    buffer[0] = extra.inheritance;

    return .{
        .ast = .{
            .body = data.rhs,
            .inheritance = if (extra.inheritance == 0) buffer[0..0] else buffer[0..1],
        },
        .main_token = main,
        .name = extra.identifier,
    };
}
/// Ast representation of a `contract_decl_inheritance`, `interface_decl_inheritance`, `abstract_decl_inheritance`.
pub fn contractDeclInheritance(
    self: Ast,
    node: Node.Index,
) ast.ContractDeclInheritance {
    const nodes = self.nodes.items(.tag);
    std.debug.assert(nodes[node] == .contract_decl_inheritance or
        nodes[node] == .interface_decl_inheritance or
        nodes[node] == .abstract_decl_inheritance);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.ContractInheritance);
    const slice = self.extra_data[extra.inheritance_start..extra.inheritance_end];

    return .{
        .ast = .{
            .body = data.rhs,
            .inheritance = slice,
        },
        .main_token = main,
        .name = extra.identifier,
    };
}

// Yul representation

/// Ast representation of a `assembly_decl` node.
pub fn assemblyDecl(
    self: Ast,
    node: Node.Index,
) ast.AssemblyDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .assembly_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .flags = data.lhs,
            .body = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_var_decl` node.
pub fn yulFunctionDecl(
    self: Ast,
    node: Node.Index,
) ast.YulFunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_function_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.YulFnProto);

    return .{
        .ast = .{
            .name = extra.identifier,
            .params_start = extra.params_start,
            .params_end = extra.params_end,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_var_decl` node.
pub fn yulFullFunctionDecl(
    self: Ast,
    node: Node.Index,
) ast.YulFullFunctionDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_full_function_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.YulFullFnProto);

    return .{
        .ast = .{
            .name = extra.identifier,
            .params_start = extra.params_start,
            .params_end = extra.params_end,
            .returns_start = extra.returns_start,
            .returns_end = extra.returns_end,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_var_decl` node.
pub fn yulVariableDecl(
    self: Ast,
    node: Node.Index,
) ast.YulVariableDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_var_decl);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .name = data.lhs,
            .expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_multi_var_decl` node.
pub fn yulMultiVariableDecl(
    self: Ast,
    node: Node.Index,
) ast.YulMultiVariableDecl {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_var_decl_multi);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.lhs, Node.Range);

    return .{
        .ast = .{
            .name_start = extra.start,
            .name_end = extra.end,
            .call_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_for` node.
pub fn yulForStatement(
    self: Ast,
    node: Node.Index,
) ast.ForStatement {
    const nodes = self.nodes.items(.tag);

    std.debug.assert(nodes[node] == .yul_for);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const proto = self.extraData(data.lhs, Node.For);

    return .{
        .ast = .{
            .assign_expr = proto.condition_one,
            .condition = proto.condition_two,
            .increment = proto.condition_three,
            .then_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_if` node.
pub fn yulIfStatement(
    self: Ast,
    node: Node.Index,
) ast.YulIfStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_if);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    return .{
        .ast = .{
            .condition = data.lhs,
            .then_expression = data.rhs,
        },
        .main_token = main,
    };
}
/// Ast representation of a `yul_switch` node.
pub fn yulSwitchStatement(
    self: Ast,
    node: Node.Index,
) ast.yulSwitchStatement {
    std.debug.assert(self.nodes.items(.tag)[node] == .yul_if);

    const data = self.nodes.items(.data)[node];
    const main = self.nodes.items(.main_token)[node];

    const extra = self.extraData(data.rhs, Node.Range);

    return .{
        .ast = .{
            .condition = data.lhs,
            .case_start = extra.start,
            .case_end = extra.end,
        },
        .main_token = main,
    };
}

// Extra functions

/// Converts the indexes in `extra_data` into the expected `T`
/// `T` must be a struct and it's members must be of `Node.Index` type.
pub fn extraData(
    self: Ast,
    index: usize,
    comptime T: type,
) T {
    var result: T = undefined;

    inline for (std.meta.fields(T), 0..) |field, i| {
        comptime std.debug.assert(field.type == Node.Index);
        @field(result, field.name) = self.extra_data[index + i];
    }

    return result;
}
/// Finds the first token tag based on the node index.
pub fn firstToken(
    self: Ast,
    node: Node.Index,
) TokenIndex {
    const node_tags = self.nodes.items(.tag);
    const data = self.nodes.items(.data);
    const main_token = self.nodes.items(.main_token);

    var current_node = node;

    while (true) {
        switch (node_tags[current_node]) {
            .root,
            => return 0,

            .using_directive,
            .using_directive_multi,
            .elementary_type,
            .function_type_simple,
            .function_type_multi,
            .function_type,
            .function_type_one,
            .struct_decl,
            .enum_decl,
            .enum_decl_one,
            .event_proto_multi,
            .event_proto_simple,
            .error_proto_simple,
            .error_proto_multi,
            .modifier_proto_one,
            .modifier_proto,
            .abstract_decl,
            .abstract_decl_inheritance_one,
            .abstract_decl_inheritance,
            .contract_decl,
            .contract_decl_inheritance,
            .contract_decl_inheritance_one,
            .interface_decl,
            .interface_decl_inheritance,
            .interface_decl_inheritance_one,
            .library_decl,
            .@"if",
            .@"while",
            .@"for",
            .@"break",
            .@"continue",
            .@"return",
            .@"try",
            .@"catch",
            .leave,
            .do_while,
            .user_defined_type,
            .mapping_decl,
            .pragma_directive,
            .import_directive_path,
            .import_directive_asterisk,
            .import_directive_symbol,
            .import_directive_symbol_one,
            .import_directive_path_identifier,
            .identifier,
            .number_literal,
            .number_literal_sub_denomination,
            .string_literal,
            .delete,
            .type_decl,
            .new_decl,
            .contract_block,
            .contract_block_semicolon,
            .contract_block_two,
            .contract_block_two_semicolon,
            .block,
            .block_two,
            .block_two_semicolon,
            .unchecked_block,
            .function_decl,
            .modifier_decl,
            .array_init_one,
            .array_init,
            .tuple_init_one,
            .tuple_init,
            .conditional_not,
            .bit_not,
            .negation,
            .emit,
            .override_specifier,
            .unreachable_node,
            .struct_decl_one,
            .construct_decl,
            .construct_decl_one,
            .function_proto_one,
            .function_proto_simple,
            .function_proto_multi,
            .function_proto,
            .if_simple,
            .block_semicolon,
            .payable_decl,
            .struct_init,
            .struct_init_one,
            .yul_full_function_decl,
            .yul_function_decl,
            .yul_switch,
            .yul_switch_case,
            .yul_switch_default,
            .yul_var_decl,
            .yul_var_decl_multi,
            .yul_for,
            .yul_if,
            .yul_assign_multi,
            .assembly_decl,
            .assembly_flags,
            .asm_block,
            .asm_block_two,
            => return main_token[current_node],

            .error_variable_decl,
            .event_variable_decl,
            .struct_field,
            .variable_decl,
            => current_node = main_token[current_node],

            .call,
            .call_one,
            .yul_call,
            .yul_call_one,
            .array_access,
            .field_access,
            .assign,
            .assign_add,
            .assign_sub,
            .assign_mul,
            .assign_div,
            .assign_shl,
            .assign_sar,
            .assign_shr,
            .assign_mod,
            .assign_bit_or,
            .assign_bit_and,
            .assign_bit_xor,
            .greater_or_equal,
            .greater_than,
            .less_than,
            .less_or_equal,
            .equal_equal,
            .bang_equal,
            .mul,
            .div,
            .add,
            .sub,
            .mod,
            .shr,
            .sar,
            .shl,
            .yul_assign,
            .bit_and,
            .bit_xor,
            .bit_or,
            .array_type,
            .conditional_or,
            .conditional_and,
            .increment,
            .decrement,
            .state_variable_decl,
            .constant_variable_decl,
            => current_node = data[current_node].lhs,

            .exponent,
            => current_node = data[current_node].rhs,

            .modifier_specifiers,
            .specifiers,
            .state_modifiers,
            => {
                const extra = self.extraData(main_token[current_node], Node.Range);

                return self.extra_data[extra.start];
            },
            .using_alias_operator,
            => return data[current_node].rhs,
        }
    }
}
/// Finds the last token tag based on the node index.
pub fn lastToken(self: Ast, node: Node.Index) TokenIndex {
    const node_tags = self.nodes.items(.tag);
    const data = self.nodes.items(.data);
    const main_token = self.nodes.items(.main_token);
    const token_tags = self.tokens.items(.tag);

    var current_node = node;
    var end_offset: u32 = 0;

    while (true) {
        switch (node_tags[current_node]) {
            .root,
            => return @as(TokenIndex, @intCast(self.tokens.len - 1)),

            .string_literal,
            .number_literal,
            .unreachable_node,
            .increment,
            .identifier,
            .decrement,
            .elementary_type,
            .@"continue",
            .@"break",
            .leave,
            => return main_token[current_node] + end_offset,

            .number_literal_sub_denomination,
            => return data[current_node].lhs + end_offset,

            .@"return",
            => if (data[current_node].lhs != 0) {
                current_node = data[current_node].lhs;
            } else return main_token[current_node] + end_offset,

            .state_variable_decl,
            => {
                end_offset += 1;
                if (data[current_node].rhs != 0) {
                    current_node = data[current_node].rhs;
                    // Main token is the state so the next are identifier and semicolon.
                } else if (main_token[current_node] != 0) {
                    end_offset += 1;
                    const elements = self.extraData(main_token[current_node], Node.Range);
                    std.debug.assert(elements.end - elements.start > 0);

                    end_offset += 1;
                    current_node = self.extra_data[elements.end - 1];
                } else current_node = data[current_node].lhs;
            },

            .variable_decl,
            .error_variable_decl,
            .event_variable_decl,
            => {
                if (data[current_node].rhs != 0) {
                    return data[current_node].rhs + end_offset;
                } else if (data[current_node].lhs != 0) {
                    return data[current_node].lhs + end_offset;
                } else current_node = main_token[current_node];
            },

            .yul_var_decl_multi,
            => {
                if (data[current_node].rhs != 0) {
                    current_node = data[current_node].rhs;
                } else if (data[current_node].lhs != 0) {
                    const extra = self.extraData(data[current_node].lhs, Node.Range);
                    std.debug.assert(extra.end > extra.start);

                    current_node = self.extra_data[extra.end - 1];
                } else current_node = main_token[current_node];
            },

            .bit_not,
            .conditional_not,
            .delete,
            .negation,
            .emit,
            .assign,
            .assign_add,
            .assign_sub,
            .assign_mul,
            .assign_div,
            .assign_shl,
            .assign_sar,
            .assign_shr,
            .assign_mod,
            .assign_bit_or,
            .assign_bit_and,
            .assign_bit_xor,
            .greater_or_equal,
            .greater_than,
            .less_than,
            .less_or_equal,
            .equal_equal,
            .bang_equal,
            .mul,
            .div,
            .add,
            .sub,
            .mod,
            .shr,
            .sar,
            .shl,
            .yul_assign,
            .bit_and,
            .bit_xor,
            .bit_or,
            .array_type,
            .conditional_or,
            .conditional_and,
            .contract_decl_inheritance_one,
            .contract_decl_inheritance,
            .contract_decl,
            .abstract_decl_inheritance,
            .abstract_decl_inheritance_one,
            .abstract_decl,
            .library_decl,
            .interface_decl,
            .interface_decl_inheritance,
            .interface_decl_inheritance_one,
            .construct_decl,
            .construct_decl_one,
            .user_defined_type,
            .unchecked_block,
            .@"while",
            .do_while,
            .if_simple,
            .@"for",
            .@"catch",
            .yul_if,
            .yul_assign_multi,
            .yul_for,
            .yul_function_decl,
            .yul_full_function_decl,
            .yul_switch_default,
            .yul_switch_case,
            .assembly_decl,
            => current_node = data[current_node].rhs,

            .exponent,
            => current_node = data[current_node].lhs,

            .mapping_decl,
            .error_proto_simple,
            .constant_variable_decl,
            => {
                end_offset += 1;
                current_node = data[current_node].rhs;
            },

            .payable_decl,
            .type_decl,
            .new_decl,
            => {
                end_offset += 1;
                current_node = data[current_node].lhs;
            },

            .import_directive_path,
            => {
                end_offset += 1;
                return data[current_node].lhs + end_offset;
            },

            .import_directive_symbol,
            .import_directive_symbol_one,
            .import_directive_asterisk,
            .import_directive_path_identifier,
            => {
                end_offset += 1;
                return data[current_node].rhs + end_offset;
            },

            .struct_init_one,
            => {
                end_offset += 1;

                if (data[current_node].lhs != 0)
                    current_node = data[current_node].lhs;

                return main_token[current_node] + end_offset;
            },

            .struct_init,
            => {
                const elements = self.extraData(data[current_node].rhs, Node.Range);
                std.debug.assert(elements.end - elements.start > 0);

                end_offset += 1;
                current_node = self.extra_data[elements.end - 1];
            },

            .using_directive_multi,
            => {
                end_offset += 1;
                if (data[current_node].rhs != 0)
                    return data[current_node].rhs + end_offset;

                const elems = self.extraData(data[current_node].lhs, Node.UsingDirectiveMulti);

                current_node = elems.target_type;
            },

            .using_directive,
            => {
                end_offset += 1;
                if (data[current_node].rhs != 0)
                    return data[current_node].rhs + end_offset;

                const elems = self.extraData(data[current_node].lhs, Node.UsingDirective);

                if (token_tags[elems.target_type] == .asterisk)
                    return elems.target_type + end_offset;

                current_node = elems.target_type;
            },

            .call_one,
            .yul_call_one,
            .array_access,
            => {
                end_offset += 1;
                if (data[current_node].rhs == 0)
                    return main_token[current_node] + end_offset;

                current_node = data[current_node].rhs;
            },

            .function_decl,
            .modifier_decl,
            .yul_var_decl,
            => {
                if (data[current_node].rhs != 0) {
                    current_node = data[current_node].rhs;
                } else current_node = data[current_node].lhs;
            },

            .modifier_proto_one,
            => {
                end_offset += 1;

                const proto = self.extraData(data[current_node].lhs, Node.ModifierProtoOne);
                const specifiers_node = main_token[data[current_node].rhs];
                const range = self.extraData(specifiers_node, Node.Range);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    if (proto.param == 0) {
                        end_offset += 2;
                        return main_token[proto.identifier] + end_offset;
                    } else {
                        current_node = self.extra_data[proto.param - 1];
                    }
                } else current_node = data[current_node].rhs;
            },

            .modifier_proto,
            => {
                end_offset += 1;

                const proto = self.extraData(data[current_node].lhs, Node.ModifierProto);
                const specifiers_node = main_token[data[current_node].rhs];
                const range = self.extraData(specifiers_node, Node.Range);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    current_node = self.extra_data[proto.params_end - 1];
                } else current_node = specifiers_node;
            },

            .enum_decl,
            => {
                end_offset += 1;
                const extra = self.extraData(data[current_node].rhs, Node.Range);

                return self.extra_data[extra.end - 1] + end_offset;
            },

            .struct_decl,
            => {
                end_offset += 1;
                const extra = self.extraData(data[current_node].rhs, Node.Range);

                current_node = self.extra_data[extra.end - 1];
            },

            .assembly_flags,
            => return data[current_node].rhs + end_offset,

            .enum_decl_one,
            => {
                end_offset += 1;

                return data[current_node].rhs + end_offset;
            },

            .struct_decl_one,
            => {
                end_offset += 1;

                current_node = data[current_node].rhs;
            },

            .struct_field,
            => {
                end_offset += 1;
                return data[current_node].rhs + end_offset;
            },

            .function_type_multi,
            => {
                const extra = self.extraData(data[current_node].lhs, Node.FnProtoType);

                if (extra.mutability == 0 and extra.visibility == 0) {
                    end_offset += 1;

                    current_node = self.extra_data[extra.params_end - 1];
                } else if (extra.mutability == 0) {
                    return extra.visibility + end_offset;
                } else return extra.mutability + end_offset;
            },

            .function_type_simple,
            => {
                const extra = self.extraData(data[current_node].lhs, Node.FnProtoTypeOne);

                if (extra.mutability == 0 and extra.visibility == 0) {
                    if (extra.param != 0) {
                        const param_end = self.extra_data[extra.param];
                        current_node = param_end;
                    } else {
                        end_offset += 2;
                        return main_token[current_node];
                    }
                } else if (extra.mutability == 0) {
                    return extra.visibility + end_offset;
                } else return extra.mutability + end_offset;
            },

            .block,
            .contract_block,
            .asm_block,
            => {
                std.debug.assert(data[current_node].rhs - data[current_node].lhs > 0);
                end_offset += 1;

                current_node = self.extra_data[data[current_node].rhs - 1];
            },

            .block_semicolon,
            .contract_block_semicolon,
            => {
                std.debug.assert(data[current_node].rhs - data[current_node].lhs > 0);
                end_offset += 2;

                current_node = self.extra_data[data[current_node].rhs - 1];
            },

            .block_two,
            .contract_block_two,
            .asm_block_two,
            => {
                end_offset += 1;

                if (data[current_node].rhs != 0) {
                    current_node = data[current_node].rhs;
                } else if (data[current_node].lhs != 0) {
                    current_node = data[current_node].lhs;
                } else {
                    return main_token[current_node] + end_offset;
                }
            },

            .block_two_semicolon,
            .contract_block_two_semicolon,
            => {
                end_offset += 2;

                if (data[current_node].rhs != 0) {
                    current_node = data[current_node].rhs;
                } else if (data[current_node].lhs != 0) {
                    current_node = data[current_node].lhs;
                } else unreachable;
            },

            .@"if",
            => {
                const extra = self.extraData(data[current_node].rhs, Node.If);
                std.debug.assert(extra.else_expression != 0);

                current_node = extra.else_expression;
            },

            .@"try",
            .yul_switch,
            => {
                const extra = self.extraData(data[current_node].rhs, Node.Range);

                std.debug.assert(extra.end > extra.start);

                current_node = self.extra_data[extra.end - 1];
            },

            .event_proto_simple,
            => {
                end_offset += 1;

                const extra = self.extraData(data[current_node].lhs, Node.EventProtoOne);

                if (extra.anonymous != 0)
                    return main_token[extra.anonymous] + end_offset;

                current_node = extra.params;
            },

            .event_proto_multi => {
                end_offset += 1;

                const extra = self.extraData(data[current_node].rhs, Node.EventProto);

                if (extra.anonymous != 0)
                    return main_token[extra.anonymous] + end_offset;

                std.debug.assert(extra.params_end - extra.params_start > 0);

                current_node = self.extra_data[extra.params_end - 1];
            },

            .error_proto_multi,
            => {
                end_offset += 1;

                const extra = self.extraData(data[current_node].rhs, Node.Range);

                std.debug.assert(extra.end - extra.start > 0);

                current_node = self.extra_data[extra.end - 1];
            },

            .function_proto_one,
            .function_type_one,
            => {
                end_offset += 1;
                const returns = self.extraData(data[current_node].rhs, Node.Range);

                if (returns.end > self.extra_data.len)
                    current_node = returns.end
                else
                    current_node = self.extra_data[returns.end];
            },

            .function_proto,
            .function_type,
            => {
                end_offset += 1;
                const returns = self.extraData(data[current_node].rhs, Node.Range);

                if (returns.end > self.extra_data.len)
                    current_node = returns.end
                else if (returns.start == returns.end)
                    current_node = self.extra_data[returns.end - 1] + end_offset
                else
                    current_node = self.extra_data[returns.end - 1];
            },

            .function_proto_multi,
            => {
                end_offset += 1;
                const proto = self.extraData(data[current_node].lhs, Node.FnProto);
                const specifiers_node = main_token[proto.specifiers];
                const range = self.extraData(specifiers_node, Node.Range);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    current_node = self.extra_data[proto.params_end - 1];
                } else current_node = proto.specifiers;
            },

            .function_proto_simple,
            => {
                end_offset += 1;
                const proto = self.extraData(data[current_node].lhs, Node.FnProtoOne);
                const specifiers_node = main_token[proto.specifiers];
                const range = self.extraData(specifiers_node, Node.Range);
                const slice = self.extra_data[range.start..range.end];

                if (slice.len == 0) {
                    if (proto.param == 0) {
                        end_offset += 2;
                        return main_token[proto.identifier] + end_offset;
                    }
                    current_node = self.extra_data[proto.param - 1];
                } else current_node = proto.specifiers;
            },

            .field_access,
            .array_init_one,
            .tuple_init_one,
            .tuple_init,
            .array_init,
            .pragma_directive,
            => return data[current_node].rhs + end_offset,

            .call,
            .yul_call,
            => {
                end_offset += 1;
                const extra = self.extraData(data[current_node].rhs, Node.Range);

                if (extra.end - extra.start == 0)
                    return main_token[current_node] + end_offset;

                current_node = self.extra_data[extra.end - 1];
            },

            .specifiers,
            .modifier_specifiers,
            .state_modifiers,
            => {
                const extra = self.extraData(main_token[current_node], Node.Range);

                const slice = self.extra_data[extra.start..extra.end];

                if (slice.len == 0)
                    return self.extra_data[extra.end];

                const tag = self.nodes.items(.tag);

                if (self.extra_data[extra.end - 1] >= tag.len)
                    return self.extra_data[extra.end - 1];

                switch (tag[self.extra_data[extra.end - 1]]) {
                    .override_specifier,
                    .identifier,
                    => current_node = self.extra_data[extra.end - 1],
                    else => return self.extra_data[extra.end - 1],
                }
            },

            .override_specifier,
            => {
                end_offset += 1;
                const extra = self.extraData(data[current_node].lhs, Node.Range);

                current_node = self.extra_data[extra.end - 1];
            },

            .using_alias_operator,
            => return data[current_node].lhs,
        }
    }
}
/// Grabs the source from the provided token index.
pub fn tokenSlice(
    self: Ast,
    token_index: TokenIndex,
) []const u8 {
    const token_tag = self.tokens.items(.tag)[token_index];
    const token_start = self.tokens.items(.start)[token_index];

    var lexer: tokenizer.Tokenizer = .{
        .index = token_start,
        .buffer = self.source,
    };

    if (token_tag.lexToken()) |token|
        return token;

    const token = lexer.next();
    std.debug.assert(token.tag == token_tag);

    return self.source[token.location.start..token.location.end];
}
/// Gets the full node source based on the provided index.
pub fn getNodeSource(
    self: Ast,
    node: Node.Index,
) []const u8 {
    const token_start = self.tokens.items(.start);

    const first = self.firstToken(node);
    const last = self.lastToken(node);

    const start = token_start[first];
    const end = token_start[last] + self.tokenSlice(last).len;

    return self.source[start..end];
}
/// Renders a parsing error into a more readable definition.
pub fn renderError(
    self: Ast,
    parsing_error: Error,
    writer: anytype,
) @TypeOf(writer).Error!void {
    const token_tags = self.tokens.items(.tag);

    switch (parsing_error.tag) {
        .same_line_doc_comment => return writer.writeAll("same line documentation comment"),
        .unattached_doc_comment => return writer.writeAll("unattached documentation comment"),
        .expected_else_or_semicolon => return writer.writeAll("expected ';' or 'else' after statement"),
        .expected_comma_after => return writer.writeAll("expected comma after"),
        .trailing_comma => return writer.writeAll("trailing comma found and they are not supported"),
        .expected_semicolon_or_lbrace => return writer.writeAll("expected ';' or l_brace after definition"),
        .expected_pragma_version => return writer.writeAll("expected a valid pragma version semantic"),
        .expected_import_path_alias_asterisk => return writer.writeAll("expected valid import directive"),
        .expected_function_call => return writer.writeAll("emit statement only supports function calls"),
        .chained_comparison_operators => return writer.writeAll("comparison operators cannot be chained"),
        .already_seen_specifier => return writer.writeAll("specifier cannot be repeated"),
        .expected_expr => return writer.print("expected an expression but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_yul_expression => return writer.print("expected an yul expression but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_yul_literal => return writer.print("expected an yul literal but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_yul_function_call => return writer.print("expected an yul function call but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_yul_statement => return writer.print("expected an yul statement but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_yul_assignment => return writer.print("expected an yul assignment but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_suffix => return writer.print("expected 'field_access' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_type_expr => return writer.print("expected type expression but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_statement => return writer.print("expected statement but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_semicolon => return writer.print("expected ';' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_elementary_or_identifier_path => return writer.print("expected 'elementary_type', 'identifier' or 'field_access' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_r_brace => return writer.print("expected r_brace but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_event_param => return writer.print("expected 'event_variable_decl' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_error_param => return writer.print("expected 'error_variable_decl' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_struct_field => return writer.print("expected 'struct_field' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_variable_decl => return writer.print("expected 'variable_decl' but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_prefix_expr => return writer.print("expected a prefix expression but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_return_type => return writer.print("expected a return type but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_contract_block => return writer.print("expected contract block  but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_contract_element => return writer.print("expected contract elemenent but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_block_or_assignment_statement => return writer.print("expected block or assignment but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_operator => return writer.print("expected a overridable operator but found '{s}'", .{
            token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol(),
        }),
        .expected_source_unit_expr => return writer.print(
            "expected either a constant variable, function, struct, contract, library, interface declaration or a using and import directive, but found '{s}'",
            .{token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)].symbol()},
        ),
        .expected_token,
        => {
            const tag = token_tags[parsing_error.token + @intFromBool(parsing_error.token_is_prev)];
            const expected = parsing_error.extra.expected_tag.symbol();

            switch (tag) {
                .invalid => return writer.print("expected '{s}', found invalid bytes", .{
                    expected,
                }),
                else => return writer.print("expected '{s}', found '{s}'", .{
                    expected, tag.symbol(),
                }),
            }
        },
    }
}

/// Ast representation of some of the principal AST nodes.
pub const ast = struct {
    pub const UsingDirective = struct {
        ast: Components,
        main_token: TokenIndex,
        for_alias: TokenIndex,
        global: TokenIndex,

        pub const Components = struct {
            aliases: []const Node.Index,
            target_type: Node.Index,
        };
    };

    pub const DoWhileStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            then_expression: Node.Index,
            while_expression: Node.Index,
        };
    };

    pub const WhileStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            condition: Node.Index,
            then_expression: Node.Index,
        };
    };

    pub const IfStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            condition: Node.Index,
            then_expression: Node.Index,
            else_expression: ?Node.Index,
        };
    };

    pub const YulIfStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            condition: Node.Index,
            then_expression: Node.Index,
        };
    };

    pub const yulSwitchStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            condition: Node.Index,
            case_start: Node.Index,
            case_end: Node.Index,
        };
    };

    pub const ForStatement = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            assign_expr: Node.Index,
            condition: Node.Index,
            increment: Node.Index,
            then_expression: Node.Index,
        };
    };

    pub const StructField = struct {
        ast: Components,
        name: TokenIndex,

        pub const Components = struct {
            type_expr: Node.Index,
        };
    };

    pub const ArrayType = struct {
        ast: Components,
        l_bracket: TokenIndex,

        pub const Components = struct {
            expr: Node.Index,
            type_expr: Node.Index,
        };
    };

    pub const VariableDecl = struct {
        ast: Components,
        name: ?TokenIndex,
        storage: ?TokenIndex,
        memory: ?TokenIndex,
        calldata: ?TokenIndex,

        pub const Components = struct {
            type_expr: Node.Index,
        };
    };

    pub const YulVariableDecl = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            name: Node.Index,
            expression: Node.Index,
        };
    };

    pub const YulMultiVariableDecl = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            name_start: Node.Index,
            name_end: Node.Index,
            call_expression: Node.Index,
        };
    };

    pub const StateVariableDecl = struct {
        ast: Components,
        constant: ?TokenIndex,
        public: ?TokenIndex,
        immutable: ?TokenIndex,
        private: ?TokenIndex,
        internal: ?TokenIndex,
        override: ?TokenIndex,

        pub const Components = struct {
            type_token: Node.Index,
            expression_node: Node.Index,
        };
    };

    pub const ConstantVariableDecl = struct {
        ast: Components,
        name: TokenIndex,

        pub const Components = struct {
            type_token: Node.Index,
            expression_node: Node.Index,
        };
    };

    pub const UserDefinedTypeDecl = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            target_type: Node.Index,
        };
    };

    pub const EnumDecl = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        fields: []const TokenIndex,
    };

    pub const MappingDecl = struct {
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            left: Node.Index,
            right: Node.Index,
        };
    };

    pub const ImportDecl = struct {
        ast: Components,
        main_token: TokenIndex,
        path: TokenIndex,
        name: ?TokenIndex,
        from: ?TokenIndex,

        pub const Components = struct {
            symbols: ?[]const Node.Index,
        };
    };

    pub const FunctionDecl = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
            specifiers: []const Node.Index,
            returns: ?[]const Node.Index,
        };
    };

    pub const YulFunctionDecl = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            name: Node.Index,
            params_start: Node.Index,
            params_end: Node.Index,
        };
    };

    pub const YulFullFunctionDecl = struct {
        ast: Components,
        main_token: TokenIndex,

        pub const Components = struct {
            name: Node.Index,
            params_start: Node.Index,
            params_end: Node.Index,
            returns_start: Node.Index,
            returns_end: Node.Index,
        };
    };

    pub const FunctionTypeDecl = struct {
        visibility: ?TokenIndex,
        mutability: ?TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
            returns: ?[]const Node.Index,
        };
    };

    pub const StructDecl = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            fields: []const Node.Index,
        };
    };

    pub const ConstructorDecl = struct {
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
            /// This can also reference a node in case of `override`.
            specifiers: []const TokenIndex,
            body: Node.Index,
        };
    };

    pub const ErrorProto = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
        };
    };

    pub const ModifierProto = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
            /// This can also reference a node in case of `override`.
            specifiers: []const TokenIndex,
        };
    };

    pub const EventProto = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        anonymous: ?TokenIndex,
        ast: Components,

        pub const Components = struct {
            params: []const Node.Index,
        };
    };

    pub const ContractDeclInheritance = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            inheritance: []const Node.Index,
            body: Node.Index,
        };
    };

    pub const ContractDecl = struct {
        name: TokenIndex,
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            body: Node.Index,
            inheritance: ?[]const Node.Index,
        };
    };

    pub const AssemblyDecl = struct {
        main_token: TokenIndex,
        ast: Components,

        pub const Components = struct {
            flags: Node.Index,
            body: Node.Index,
        };
    };
};

/// Ast Node representation.
///
/// `data` may contain indexes to extra_data to help build the syntax tree.
pub const Node = struct {
    /// Node tag of the parsed element.
    tag: Tag,
    /// Index into the main token of the node.
    main_token: TokenIndex,
    /// Left and right indexes into more information about the node.
    data: Data,

    /// Node index into the struct of arrays.
    pub const Index = u32;

    // Assert that out tag is always size 1.
    comptime {
        std.debug.assert(@sizeOf(Tag) == 1);
    }

    pub const Tag = enum {
        /// lhs is the first index to the first node
        /// rhs is the first index to the last node.
        root,
        /// lhs and rhs are undefined.
        /// main_token is the identifier token.
        identifier,
        /// `lhs.a`. `main_token` is the dot and rhs is the identifier token index.
        field_access,
        /// `lhs == rhs`.
        equal_equal,
        /// `lhs != rhs`.
        bang_equal,
        /// `lhs < rhs`
        less_than,
        /// `lhs <= rhs`
        less_or_equal,
        /// `lhs > rhs`
        greater_than,
        /// `lhs >= rhs`
        greater_or_equal,
        /// `lhs = rhs`
        assign,
        /// `lhs += rhs`
        assign_add,
        /// `lhs -= rhs`
        assign_sub,
        /// `lhs *= rhs`
        assign_mul,
        /// `lhs %= rhs`
        assign_mod,
        /// `lhs /= rhs`
        assign_div,
        /// `lhs <<= rhs`
        assign_shl,
        /// `lhs >>= rhs`
        assign_sar,
        /// `lhs >>>= rhs`
        assign_shr,
        /// `lhs &= rhs`
        assign_bit_and,
        /// `lhs |= rhs`
        assign_bit_or,
        /// `lhs ^= rhs`
        assign_bit_xor,
        /// `lhs := rhs`
        yul_assign,
        yul_assign_multi,
        /// `lhs + rhs`
        add,
        /// `lhs - rhs`
        sub,
        /// `lhs * rhs`
        mul,
        /// `lhs % rhs`
        mod,
        /// `lhs / rhs`
        div,
        /// `lhs << rhs`
        shl,
        /// `lhs >> rhs`
        sar,
        /// `lhs >>> rhs`
        shr,
        /// `lhs ** rhs`
        exponent,
        /// `lhs & rhs`
        bit_and,
        /// `lhs | rhs`
        bit_or,
        /// `lhs ^ rhs`
        bit_xor,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        bit_not,
        /// `lhs && rhs`
        conditional_and,
        /// `lhs || rhs`
        conditional_or,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        conditional_not,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        negation,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        increment,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        decrement,
        /// main_token is the keyword.
        /// lhs is the expr and rhs is unused.
        delete,
        /// main token is the keyword.
        /// lhs is the node index to the type expression.
        /// rhs is unused.
        type_decl,
        /// main token is the keyword.
        /// lhs is the node index to the type expression.
        /// rhs is unused.
        new_decl,
        /// main token is `l_bracket`
        /// lhs is the expression
        /// rhs is `r_bracket`
        array_type,
        /// `lhs[rhs]`
        array_access,
        /// main token is `l_bracket`
        /// lhs is the expression
        /// rhs is `r_bracket`
        array_init_one,
        /// main token is `l_bracket`
        /// lhs is the index into extra data.
        /// rhs is `r_bracket`
        array_init,
        /// main token is `l_paren`
        /// lhs is the expression
        /// rhs is `r_paren`
        tuple_init_one,
        /// main token is `l_paren`
        /// lhs is the index into extra data.
        /// rhs is `r_paren`
        tuple_init,
        /// main token is `l_brace`
        /// lhs is the expression
        /// rhs is `r_brace`
        struct_init_one,
        /// main token is `l_brace`
        /// lhs is the index into extra data.
        /// rhs is `r_brace`
        struct_init,
        /// main token is the keyword.
        /// lhs is the expression
        /// rhs is unused.
        payable_decl,
        /// main token is the keyword.
        /// both lhs and rhs are unused.
        string_literal,
        /// main token is the keyword.
        /// both lhs and rhs are unused.
        number_literal,
        /// main token is the keyword.
        /// lhs is the denomination keywords (gwei, wei, hours, etc)
        number_literal_sub_denomination,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the index into extra data.
        call,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the parameter.
        call_one,
        /// main token is keyword.
        /// lhs is the condition expression.
        /// rhs is then_expression.
        @"while",
        /// main token is keyword.
        /// lhs is the condition expression.
        /// rhs is while statement.
        do_while,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is then expression.
        @"for",
        /// main token is keyword.
        /// lhs is then expression.
        /// rhs is the index into extra data.
        @"if",
        /// main token is keyword.
        /// lhs is then expression.
        /// rhs is the then_expression.
        if_simple,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the index into extra data.
        @"try",
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the index into block expression.
        @"catch",
        /// main token is keyword.
        /// both rhs and lhs are unused.
        @"break",
        /// main token is keyword.
        /// lhs is the expression
        /// rhs is unused.
        @"return",
        /// main token is keyword.
        /// both rhs and lhs are unused.
        @"continue",
        /// main token is keyword.
        /// both rhs and lhs are unused.
        leave,
        /// main token is keyword.
        /// lhs is the expression to a call or call_one node.
        /// rhs is unused.
        emit,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the block statement.
        function_decl,
        /// main token is keyword.
        /// lhs and rhs are indexes into statements.
        block_two,
        /// main token is keyword.
        /// lhs and rhs are indexes into statements that end with semicolon.
        block_two_semicolon,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements.
        block,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        block_semicolon,
        /// main token is keyword.
        /// lhs is the index to the block node.
        /// rhs is unused.
        unchecked_block,
        /// main token is keyword.
        /// lhs is the index to extra data.
        /// rhs is the identifier.
        using_directive,
        /// main token is keyword.
        /// lhs is the index to extra data.
        /// rhs is the identifier.
        using_directive_multi,
        /// main token is the operand.
        /// lhs is the identifier path.
        /// rhs is the as keyword.
        using_alias_operator,
        /// main token is `l_brace`.
        /// lhs and rhs are indexes into elements.
        contract_block_two,
        /// main token is `l_brace`.
        /// lhs and rhs are indexes into elements that end with semicolon.
        contract_block_two_semicolon,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        contract_block,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        contract_block_semicolon,
        /// Throw away node used for unreserving nodes.
        unreachable_node,
        /// main token is the keyword or the index into `override_specifier`.
        /// lhs and rhs are unused.
        specifiers,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        override_specifier,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        abstract_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        abstract_decl_inheritance,
        abstract_decl_inheritance_one,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        contract_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        contract_decl_inheritance,
        contract_decl_inheritance_one,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        interface_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        interface_decl_inheritance,
        interface_decl_inheritance_one,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        library_decl,
        /// `lhs` is undefined.
        /// `rhs` is the index to `path`.
        import_directive_path,
        /// `lhs` is the index into `path`
        /// `rhs` is the index into `identifier`
        import_directive_path_identifier,
        /// `lhs` is the index into extra data
        /// `rhs` is the `path`.
        import_directive_symbol,
        /// `lhs` is the index into extra data
        /// `rhs` is the `path`.
        import_directive_symbol_one,
        /// `lhs` is the  index into extra data.
        /// `rhs` is the index into `path`
        import_directive_asterisk,
        /// `lhs` is the start of the version range.
        /// `rhs` is the end of the version range.
        pragma_directive,
        /// main token is the keyword.
        /// `lhs` is the first child types.
        /// `rhs` is the second child types.
        ///
        /// Can have nested `mapping_decl` on rhs.
        mapping_decl,
        /// `lhs` and `rhs` are undefined.
        /// `main_token` is the type.
        elementary_type,
        /// `lhs` is the index to the storage modifier
        /// `rhs` is the index to the identifier
        variable_decl,
        /// `lhs` is the index to the identifier
        /// `rhs` is the index to the `elementary_type` node.
        user_defined_type,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the index into extra data.
        struct_decl,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the field.
        struct_decl_one,
        /// main token is the type
        /// lhs is unused.
        /// rhs is identifier.
        struct_field,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        event_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data.
        /// rhs is identifier.
        event_proto_simple,
        /// main token is the type
        /// lhs is the indexed keyword if exists or null node.
        /// rhs is identifier.
        event_variable_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        error_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        error_proto_simple,
        /// main token is the type
        /// lhs is identifier.
        /// rhs is unused.
        error_variable_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with param and with no return.
        /// rhs is identifier.
        function_proto_simple,
        /// main token is the keyword
        /// lhs is the index into extra data with params range with no return.
        /// rhs is identifier.
        function_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data with param and with return params.
        /// rhs is identifier.
        function_proto_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range and returns params range.
        /// rhs is identifier.
        function_proto,
        /// main token is the keyword
        /// lhs is the index into extra data with param and specifiers.
        /// rhs is the return.
        function_type_simple,
        /// main token is the keyword
        /// lhs is the index into extra data with param and specifiers.
        /// rhs is the return.
        function_type_multi,
        /// main token is the keyword
        /// lhs is the index into extra data with param and specifiers.
        /// rhs is the return.
        function_type_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range and returns params range.
        /// rhs is the return.
        function_type,
        /// main token is the keyword
        /// lhs is identifier.
        /// rhs is unused.
        enum_decl_one,
        /// main token is the keyword
        /// lhs is the index into extra data.
        /// rhs is unused.
        enum_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with param and specifiers.
        /// rhs is the block statements.
        construct_decl_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range and specifiers.
        /// rhs is the block statements.
        construct_decl,
        /// main token is the keyword
        /// lhs is the index to the param
        /// rhs is the specifiers.
        modifier_proto_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is the specifiers.
        modifier_proto,
        /// main token is the keyword
        /// lhs is the proto.
        /// rhs is the block statements.
        modifier_decl,
        /// main token is the index into extra data.
        /// lhs and rhs are unused.
        modifier_specifiers,
        /// main token is the state keyword or null_node
        /// lhs is the type index
        /// rhs is the expression or null_node.
        state_variable_decl,
        constant_variable_decl,
        /// main token is the state keywords range.
        /// lhs and rhs are undefined.
        state_modifiers,

        // Yul nodes

        /// main token is the assembly keyword
        /// lhs is the flags
        /// rhs is the block
        assembly_decl,
        /// main token is the l_paren
        /// lhs is the slice of string_literals
        /// rhs is the r_paren
        assembly_flags,
        /// main token is the l_bracket
        /// lhs is the start of the statements
        /// rhs is the end of the statements
        asm_block,
        /// main token is the l_bracket
        /// lhs is the start of the statements
        /// rhs is the end of the statements. This can be 0.
        asm_block_two,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the index into extra_data
        yul_call,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the parameter.
        yul_call_one,
        /// main token is the let keyword
        /// lhs is the type index
        /// rhs is the expression or null_node.
        yul_var_decl,
        /// main token is the let keyword
        /// lhs is the index into extra_data
        /// rhs is the expression or a null_node.
        yul_var_decl_multi,
        /// main token is the if keyword
        /// lhs is the expression
        /// rhs is the block
        yul_if,
        /// main token is the for keyword
        /// lhs is the index into extra_data
        /// rhs is the block
        yul_for,
        /// main token is the switch keyword
        /// lhs is the expression
        /// rhs is the index into extra_data
        yul_switch,
        /// main token is the case keyword
        /// lhs is the literal
        /// rhs is the block
        yul_switch_case,
        /// main token is the default keyword
        /// lhs is a null_node
        /// rhs is the block
        yul_switch_default,
        /// main token is the function keyword
        /// lhs is the index into extra_data
        /// rhs is the block
        yul_function_decl,
        /// main token is the function keyword
        /// lhs is the index into extra_data
        /// rhs is the block
        yul_full_function_decl,
    };

    /// Range used for params and others
    pub const Range = struct {
        start: Index,
        end: Index,
    };
    /// Node lhs and rhs index data.
    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };
    /// if expressions extra data.
    pub const If = struct {
        then_expression: Index,
        else_expression: Index,
    };

    /// For expression extra data.
    pub const For = struct {
        condition_one: Index,
        condition_two: Index,
        condition_three: Index,
    };

    /// Try expression extra data.
    pub const Try = struct {
        returns: Index,
        expression: Index,
        block_statement: Index,
    };

    /// Constructor definition extra data.
    /// Mostly used if the constructor has multiple params.
    pub const ConstructorProto = struct {
        params_start: Index,
        params_end: Index,
        specifiers: Index,
    };

    /// Modifier definition extra data.
    pub const ModifierProtoOne = struct {
        param: Index,
        identifier: Index,
    };

    /// Modifier definition extra data.
    /// Mostly used if the modifier has multiple params.
    pub const ModifierProto = struct {
        params_start: Index,
        params_end: Index,
        identifier: Index,
    };

    /// Constructor definition extra data.
    /// Mostly used if the constructor has a single param.
    pub const ConstructorProtoOne = struct {
        param: Index,
        specifiers: Index,
    };

    /// Function types definition extra data.
    /// Mostly used if the function has a single param.
    pub const FnProtoTypeOne = struct {
        param: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    /// Function types definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const FnProtoType = struct {
        params_start: Index,
        params_end: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a single param.
    pub const FnProtoOne = struct {
        param: Index,
        specifiers: Index,
        identifier: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const FnProto = struct {
        params_start: Index,
        params_end: Index,
        specifiers: Index,
        identifier: Index,
    };

    /// Yul Function definition extra data.
    /// Mostly used if the function doesn't have a return type definition
    pub const YulFnProto = struct {
        params_start: Index,
        params_end: Index,
        identifier: Index,
    };

    /// Yul Function definition extra data.
    /// Mostly used if the function has a return type.
    pub const YulFullFnProto = struct {
        returns_start: Index,
        returns_end: Index,
        params_start: Index,
        params_end: Index,
        identifier: Index,
    };

    /// Contract, Interface inheritance definition extra data.
    /// Mostly used if its a single.
    pub const ContractInheritanceOne = struct {
        identifier: Index,
        inheritance: Index,
    };

    /// Contract, Interface inheritance definition extra data.
    /// Mostly used if its it has multiple ones.
    pub const ContractInheritance = struct {
        identifier: Index,
        inheritance_start: Index,
        inheritance_end: Index,
    };

    /// Event definition extra data.
    /// Mostly used if the function has a single param.
    pub const EventProtoOne = struct {
        params: Index,
        anonymous: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const EventProto = struct {
        params_start: Index,
        params_end: Index,
        anonymous: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with a asterisk
    pub const ImportAsterisk = struct {
        identifier: TokenIndex,
        from: TokenIndex,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with an symbol.
    pub const ImportSymbolOne = struct {
        symbol: Index,
        from: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with multiple symbols.
    pub const ImportSymbol = struct {
        symbol_start: Index,
        symbol_end: Index,
        from: Index,
    };

    /// Extra data structure for nodes where
    /// the using directive as a single alias
    pub const UsingDirective = struct {
        aliases: Index,
        for_alias: Index,
        target_type: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with multiple alias.
    pub const UsingDirectiveMulti = struct {
        aliases_start: Index,
        aliases_end: Index,
        for_alias: Index,
        target_type: Index,
    };
};

/// Ast error structure used to keep track of parsing errors.
pub const Error = struct {
    tag: Tag,
    is_note: bool = false,
    /// True if `token` points to the token before the token causing an issue.
    token_is_prev: bool = false,
    token: TokenIndex,
    extra: union {
        none: void,
        expected_tag: Token.Tag,
    } = .{ .none = {} },

    /// Ast error tags.
    pub const Tag = enum {
        same_line_doc_comment,
        expected_token,
        expected_semicolon,
        expected_pragma_version,
        expected_import_path_alias_asterisk,
        expected_comma_after,
        expected_r_brace,
        expected_elementary_or_identifier_path,
        expected_suffix,
        expected_variable_decl,
        expected_struct_field,
        expected_event_param,
        expected_error_param,
        expected_type_expr,
        expected_prefix_expr,
        trailing_comma,
        chained_comparison_operators,
        expected_expr,
        expected_statement,
        expected_function_call,
        expected_block_or_assignment_statement,
        expected_semicolon_or_lbrace,
        expected_else_or_semicolon,
        already_seen_specifier,
        expected_contract_element,
        expected_contract_block,
        unattached_doc_comment,
        expected_source_unit_expr,
        expected_operator,
        expected_return_type,
        expected_yul_statement,
        expected_yul_assignment,
        expected_yul_expression,
        expected_yul_function_call,
        expected_yul_literal,
    };
};
