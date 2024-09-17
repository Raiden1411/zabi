const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Ast = @import("Ast.zig");
const AstError = Ast.Error;
const Node = Ast.Node;
const NodeList = Ast.NodeList;
const NodeOffset = Ast.Offset;
const Token = tokenizer.Token;
const Tokenizer = tokenizer.Tokenizer;
const TokenIndex = Ast.TokenIndex;
const Parser = @This();

/// Errors that can happing whilest parsing the source code.
pub const ParserErrors = error{ParsingError} || Allocator.Error;

const null_node: Node.Index = 0;

const Span = union(enum) {
    zero_one: Node.Index,
    multi: Node.Range,
};

/// Allocator used in parsing.
allocator: Allocator,
/// Source code to parse.
source: []const u8,
/// All of the token tags.
token_tags: []const Token.Tag,
/// All of the token starts in the source code.
token_starts: []const NodeOffset,
/// Struct of arrays that contain all of the nodes information
nodes: NodeList,
/// Current index in the `token_tags` slice.
token_index: TokenIndex,
/// List of ast errors that the parser catches but doesn't fail on.
errors: ArrayListUnmanaged(AstError),
/// Extra data for ast nodes.
extra_data: ArrayListUnmanaged(Node.Index),
/// Scratch space to temporaly use.
scratch: ArrayListUnmanaged(Node.Index),

/// Deinits the parser allocated memory
pub fn deinit(self: *Parser) void {
    self.errors.deinit(self.allocator);
    self.nodes.deinit(self.allocator);
    self.extra_data.deinit(self.allocator);
    self.scratch.deinit(self.allocator);
}
/// .keyword_error, .identifier, .l_paren, (error_param?), .r_paren
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.errorDefinition)
pub fn parseError(self: *Parser) ParserErrors!Node.Index {
    const event = try self.expectToken(.keyword_error);
    const error_index = try self.reserveNode(.error_proto_multi);
    const identifier = try self.expectToken(.identifier);

    const params = try self.parseErrorParamDecls();

    return switch (params) {
        .zero_one => |elem| return self.setNode(error_index, .{
            .tag = .error_proto_simple,
            .main_token = event,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| return self.setNode(error_index, .{
            .tag = .error_proto_multi,
            .main_token = event,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.Range{
                    .start = elems.start,
                    .end = elems.end,
                }),
            },
        }),
    };
}
/// Parses all `error_variable_decl` nodes and returns the total amount of it.
pub fn parseErrorParamDecls(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        if (self.consumeToken(.r_paren)) |_| break;
        const field = try self.expectErrorParam();

        if (field != 0)
            try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `error_variable_decl` orelse it will fail.
pub fn expectErrorParam(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseErrorParam();

    if (field == 0)
        return self.fail(.expected_error_param);

    return field;
}
/// .TYPE, .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.errorParameter)
pub fn parseErrorParam(self: *Parser) ParserErrors!Node.Index {
    const field_index = try self.reserveNode(.error_variable_decl);
    const type_expr = try self.expectTypeExpr();
    const identifier = self.consumeToken(.identifier) orelse null_node;

    return self.setNode(field_index, .{
        .tag = .error_variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = identifier,
            .rhs = undefined,
        },
    });
}
/// .keyword_event, .identifier, .l_paren, (event_variable_decl_list)?, .r_paren, .keyword_anonymous
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.eventDefinition)
pub fn parseEvent(self: *Parser) ParserErrors!Node.Index {
    const event = try self.expectToken(.keyword_event);
    const event_index = try self.reserveNode(.event_proto_multi);
    const identifier = try self.expectToken(.identifier);

    const params = try self.parseEventParamDecls();

    const anonymous = self.consumeToken(.keyword_anonymous) orelse null_node;

    return switch (params) {
        .zero_one => |elem| return self.setNode(event_index, .{
            .tag = .event_proto_simple,
            .main_token = event,
            .data = .{
                .lhs = try self.addExtraData(Node.EventProtoOne{
                    .params = elem,
                    .anonymous = anonymous,
                }),
                .rhs = identifier,
            },
        }),
        .multi => |elems| return self.setNode(event_index, .{
            .tag = .event_proto_multi,
            .main_token = event,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.EventProto{
                    .params_start = elems.start,
                    .params_end = elems.end,
                    .anonymous = anonymous,
                }),
            },
        }),
    };
}
/// Parses all `event_variable_decl` nodes and returns the total amount of it.
pub fn parseEventParamDecls(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        if (self.consumeToken(.r_paren)) |_| break;
        const field = try self.expectEventParam();

        if (field != 0)
            try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `event_variable_decl` orelse it will fail.
pub fn expectEventParam(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseEventParam();

    if (field == 0)
        return self.fail(.expected_event_param);

    return field;
}
/// .TYPE, .keyword_indexed?, .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.eventParameter)
pub fn parseEventParam(self: *Parser) ParserErrors!Node.Index {
    const field_index = try self.reserveNode(.event_variable_decl);

    const type_expr = try self.expectTypeExpr();
    const indexed = self.consumeToken(.keyword_indexed) orelse null_node;
    const identifier = self.consumeToken(.identifier) orelse null_node;

    return self.setNode(field_index, .{
        .tag = .event_variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = indexed,
            .rhs = identifier,
        },
    });
}
/// .keyword_struct, .identifier, .l_brace, (struct_field_list), .r_brace
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.structDefinition)
pub fn parseStruct(self: *Parser) ParserErrors!Node.Index {
    const struct_token = try self.expectToken(.keyword_struct);
    const struct_index = try self.reserveNode(.struct_decl);
    const identifier = try self.expectToken(.identifier);

    const fields = try self.parseStructFields();

    return switch (fields) {
        .zero_one => |elem| self.setNode(struct_index, .{
            .tag = .struct_decl_one,
            .main_token = struct_token,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| self.setNode(struct_token, .{
            .tag = .struct_decl,
            .main_token = struct_token,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.Range{
                    .start = elems.start,
                    .end = elems.end,
                }),
            },
        }),
    };
}
/// Parses all `struct_field` nodes and returns the total amount of it.
pub fn parseStructFields(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_brace);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        if (self.consumeToken(.r_brace)) |_| break;

        const field = try self.expectStructField();

        if (field != 0)
            try self.scratch.append(self.allocator, field);
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `struct_field` orelse it will fail.
pub fn expectStructField(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseStructField();

    if (field == 0)
        return self.fail(.expected_struct_field);

    return field;
}
/// .TYPE, .identifier, .semicolon
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.structMember)
pub fn parseStructField(self: *Parser) ParserErrors!Node.Index {
    const field_index = try self.reserveNode(.struct_field);
    const type_expr = try self.expectTypeExpr();
    const identifier = try self.expectToken(.identifier);
    try self.expectSemicolon();

    return self.setNode(field_index, .{
        .tag = .struct_field,
        .main_token = type_expr,
        .data = .{
            .lhs = undefined,
            .rhs = identifier,
        },
    });
}

/// .l_paren, .param_decl, .r_paren
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.parameterList)
pub fn parseParseDeclList(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        if (self.consumeToken(.r_paren)) |_| break;

        const param = try self.expectVariableDeclaration();

        if (param != 0)
            try self.scratch.append(self.allocator, param);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const params = self.scratch.items[scratch..];

    return switch (params.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = params[0] },
        else => Span{ .multi = try self.listToSpan(params) },
    };
}
/// Fails if no variable declaration is found.
pub fn expectVariableDeclaration(self: *Parser) ParserErrors!Node.Index {
    const variable = try self.parseVariableDeclaration();

    if (variable == 0)
        return self.fail(.expected_variable_decl);

    return variable;
}
/// .type_expr <- .storage_modifier? <- .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.variableDeclaration)
pub fn parseVariableDeclaration(self: *Parser) ParserErrors!Node.Index {
    const param_idx = try self.reserveNode(.variable_decl);

    const type_expr = try self.expectTypeExpr();
    const storage = self.consumeStorageLocation() orelse null_node;
    const identifier = self.consumeToken(.identifier) orelse null_node;

    return self.setNode(param_idx, .{
        .tag = .variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = storage,
            .rhs = identifier,
        },
    });
}
/// Parses a type expression or fails.
pub fn expectTypeExpr(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.parseTypeExpr();

    if (type_expr == 0)
        return self.fail(.expected_type_expr);

    return type_expr;
}
/// / .elementary_type
/// / .keyword_mapping
/// / .identifier_path
/// / .function_proto
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.typeName)
pub fn parseTypeExpr(self: *Parser) ParserErrors!Node.Index {
    return switch (self.token_tags[self.token_index]) {
        .keyword_function => self.parseFunctionType(),
        .keyword_mapping => self.parseMapping(false),
        .identifier => self.consumeIdentifierPath(),
        else => self.consumeElementaryType(),
    };
}
/// .keyword_function <- (?param_decl list) <- ?visibility <- ?mutability <- ?returns <- ?(param_decl list)
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.functionTypeName)
pub fn parseFunctionType(self: *Parser) ParserErrors!Node.Index {
    const function = self.consumeToken(.keyword_function) orelse return null_node;

    const fn_index = try self.reserveNode(.function_proto);

    const param_list = try self.parseParseDeclList();
    const visibility = self.consumeVisibilityModifier() orelse null_node;
    const mutability = self.consumeStateMutability() orelse null_node;

    const returns = self.consumeToken(.keyword_returns) orelse null_node;

    if (returns != 0) {
        const return_params = try self.parseParseDeclList();

        return switch (param_list) {
            .zero_one => |param| self.setNode(fn_index, .{
                .tag = .function_proto_one,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProtoOne{
                        .param = param,
                        .visibility = visibility,
                        .mutability = mutability,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| r_param,
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
            .multi => |params| self.setNode(fn_index, .{
                .tag = .function_proto,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProto{
                        .mutability = mutability,
                        .visibility = visibility,
                        .params_start = params.start,
                        .params_end = params.end,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| r_param,
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
        };
    }

    return switch (param_list) {
        .zero_one => |param| self.setNode(fn_index, .{
            .tag = .function_proto_simple,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProtoOne{
                    .param = param,
                    .visibility = visibility,
                    .mutability = mutability,
                }),
                .rhs = returns,
            },
        }),
        .multi => |params| self.setNode(fn_index, .{
            .tag = .function_proto_multi,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProto{
                    .mutability = mutability,
                    .visibility = visibility,
                    .params_start = params.start,
                    .params_end = params.end,
                }),
                .rhs = returns,
            },
        }),
    };
}
/// Pragma Keyword <- Solidity keyword <- version range <- semicolon
///
/// Pragma [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityLexer.PragmaToken)
pub fn parsePragmaDirective(self: *Parser) ParserErrors!Node.Index {
    const pragma = self.consumeToken(.keyword_pragma) orelse return null_node;

    _ = try self.expectToken(.keyword_solidity);

    const start = self.token_index;
    const end = try self.parsePragmaVersion();

    _ = try self.expectToken(.semicolon);

    if (start == end)
        return self.failMsg(.{
            .tag = .expected_pragma_version,
            .token = pragma,
            .extra = .{ .expected_tag = .number_literal },
        });

    return self.addNode(.{
        .tag = .pragma_directive,
        .main_token = pragma,
        .data = .{ .lhs = start, .rhs = end },
    });
}
/// Parses the pragma version. Breaks instantly if version is just the number literal.
pub fn parsePragmaVersion(self: *Parser) ParserErrors!TokenIndex {
    const end = while (true) {
        switch (self.token_tags[self.token_index]) {
            .equal,
            .angle_bracket_right,
            .angle_bracket_right_equal,
            .angle_bracket_left,
            .angle_bracket_left_equal,
            => {
                self.token_index += 1;
                _ = try self.expectToken(.number_literal);
            },
            .number_literal => break self.nextToken() + 1,
            else => break self.token_index,
        }
    };

    return end;
}
/// keyword_import
///     <- .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
///      \ .string_literal (path)
///         \ semicolon
///         \ keyword_as <- identifier <- semicolon
///     \ .l_brace <- (Symbols)* <- .r_brace <- .identifier (from) <- .string_literal (path)
///
/// Import [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.importDirective)
pub fn parseImportDirective(self: *Parser) ParserErrors!Node.Index {
    const import = self.consumeToken(.keyword_import) orelse return null_node;

    switch (self.token_tags[self.token_index]) {
        .asterisk => return self.parseImportAsterisk(import),
        .l_brace => return self.parseImportSymbol(import),
        .string_literal => return self.parseImportPath(import),
        else => return self.fail(.expected_import_path_alias_asterisk),
    }
}
/// .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
pub fn parseImportAsterisk(self: *Parser, import: TokenIndex) ParserErrors!Node.Index {
    _ = self.consumeToken(.asterisk);

    _ = try self.expectToken(.keyword_as);
    const identifier = try self.expectToken(.identifier);
    const from = try self.expectToken(.identifier);
    const path = try self.expectToken(.string_literal);

    return self.addNode(.{
        .main_token = import,
        .tag = .import_directive_asterisk,
        .data = .{
            .lhs = try self.addExtraData(Node.ImportAsterisk{
                .identifier = identifier,
                .from = from,
            }),
            .rhs = path,
        },
    });
}
/// .string_literal
///     | semicolon
///     | keyword_as <- identifier <- semicolon
pub fn parseImportPath(self: *Parser, import: TokenIndex) ParserErrors!Node.Index {
    const literal = try self.expectToken(.string_literal);

    switch (self.token_tags[self.token_index]) {
        .semicolon => return self.addNode(.{
            .tag = .import_directive_path,
            .main_token = import,
            .data = .{ .lhs = 0, .rhs = literal },
        }),
        .keyword_as => {
            _ = self.consumeToken(.keyword_as);
            const identifier = try self.expectToken(.identifier);
            _ = try self.expectSemicolon();

            return self.addNode(.{
                .tag = .import_directive_path_identifier,
                .main_token = import,
                .data = .{ .lhs = literal, .rhs = identifier },
            });
        },
        else => return self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_tag = .semicolon },
        }),
    }
}
/// Symbols <- .identifier <- .string_literal
pub fn parseImportSymbol(self: *Parser, import: Node.Index) ParserErrors!Node.Index {
    const span = try self.parseIdentifierBlock();

    const from = try self.expectToken(.identifier);
    const path = try self.expectToken(.string_literal);
    _ = try self.expectToken(.semicolon);

    return switch (span) {
        .zero_one => |symbol| return self.addNode(.{
            .main_token = import,
            .tag = .import_directive_symbol_one,
            .data = .{
                .lhs = try self.addExtraData(Node.ImportSymbolOne{
                    .from = from,
                    .symbol = symbol,
                }),
                .rhs = path,
            },
        }),
        .multi => |symbols| return self.addNode(.{
            .main_token = import,
            .tag = .import_directive_symbol,
            .data = .{
                .lhs = try self.addExtraData(Node.ImportSymbol{
                    .from = from,
                    .symbol_start = symbols.start,
                    .symbol_end = symbols.end,
                }),
                .rhs = path,
            },
        }),
    };
}
/// .l_brace <- .identifier (COMMA)* <- .r_brace
pub fn parseIdentifierBlock(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_brace);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        const identifier = try self.expectToken(.identifier);
        try self.scratch.append(self.allocator, identifier);

        switch (self.token_tags[self.token_index]) {
            .comma => self.token_index += 1,
            .r_brace => {
                self.token_index += 1;
                break;
            },
            .colon, .r_bracket, .r_paren => return self.failMsg(.{
                .tag = .expected_r_brace,
                .token = self.token_index,
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const identifiers = self.scratch.items[scratch..];

    return switch (identifiers.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = identifiers[0] },
        else => Span{ .multi = try self.listToSpan(identifiers) },
    };
}
/// .keyword_enum <- .identifier <- .l_brace <- (BLOCK)* <- r_brace.
///
/// Enum [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.enumDefinition)
pub fn parseEnum(self: *Parser) ParserErrors!Node.Index {
    const main = try self.expectToken(.keyword_enum);
    const name = try self.expectToken(.identifier);

    const members = try self.parseIdentifierBlock();

    return switch (members) {
        .zero_one => |identifier| return self.addNode(.{
            .main_token = main,
            .tag = .enum_decl_one,
            .data = .{
                .lhs = name,
                .rhs = identifier,
            },
        }),
        .multi => |identifiers| return self.addNode(.{
            .main_token = main,
            .tag = .enum_decl,
            .data = .{
                .lhs = name,
                .rhs = try self.addExtraData(Node.Range{
                    .start = identifiers.start,
                    .end = identifiers.end,
                }),
            },
        }),
    };
}
/// .identifier (.period)*
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.identifierPath)
pub fn parseIdentifierPath(self: *Parser, lhs: Node.Index) Allocator.Error!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .period => switch (self.token_tags[self.token_index + 1]) {
            .identifier => return self.addNode(.{
                .tag = .field_access,
                .main_token = self.nextToken(),
                .data = .{
                    .lhs = lhs,
                    .rhs = self.nextToken(),
                },
            }),
            else => {
                self.token_index += 1;
                try self.warn(.expected_suffix);

                return null_node;
            },
        },
        else => return null_node,
    }
}
/// .keyword_mapping <- .l_paren <- .mapping_elements <- .equal_bracket_right <- .mapping_elements <- .r_paren <- (if not nested).semicolon;
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.mappingType)
pub fn parseMapping(self: *Parser, nested: bool) ParserErrors!Node.Index {
    const mapping = try self.expectToken(.keyword_mapping);
    _ = try self.expectToken(.l_paren);

    const mapping_index = try self.reserveNode(.mapping_decl);

    const child_one = try self.parseMappingTypes();

    if (child_one == 0)
        return self.fail(.expected_elementary_or_identifier_path);

    _ = try self.expectToken(.equal_bracket_right);

    const child_two = switch (self.token_tags[self.token_index]) {
        .keyword_mapping => try self.parseMapping(true),
        else => try self.parseMappingTypes(),
    };

    if (child_two == 0)
        return self.fail(.expected_elementary_or_identifier_path);

    _ = try self.expectToken(.r_paren);
    _ = try self.expectToken(.identifier);

    if (!nested) {
        _ = try self.expectSemicolon();
    }

    return self.setNode(mapping_index, .{
        .tag = .mapping_decl,
        .main_token = mapping,
        .data = .{
            .lhs = child_one,
            .rhs = child_two,
        },
    });
}
/// Mapping types
///     <- .elementary_type
///      / .identifier_path (.identifier, .period, .identifier ...)
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.mappingKeyType)
pub fn parseMappingTypes(self: *Parser) Allocator.Error!Node.Index {
    const elementary_type = try self.consumeElementaryType();

    if (elementary_type == 0)
        return self.consumeIdentifierPath();

    return elementary_type;
}
/// .identifier, .period, .identifier ...
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.identifierPath)
pub fn consumeIdentifierPath(self: *Parser) Allocator.Error!Node.Index {
    var identifier = self.consumeToken(.identifier) orelse return null_node;

    while (true) {
        const suffix = try self.parseIdentifierPath(identifier);

        if (suffix != 0) {
            identifier = suffix;
            continue;
        }

        return identifier;
    }
}
/// Consume a solidity primary type.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.elementaryTypeName)
pub fn consumeElementaryType(self: *Parser) Allocator.Error!Node.Index {
    return switch (self.token_tags[self.token_index]) {
        .keyword_address,
        .keyword_bool,
        .keyword_string,
        .keyword_bytes,
        .keyword_bytes1,
        .keyword_bytes2,
        .keyword_bytes3,
        .keyword_bytes4,
        .keyword_bytes5,
        .keyword_bytes6,
        .keyword_bytes7,
        .keyword_bytes8,
        .keyword_bytes9,
        .keyword_bytes10,
        .keyword_bytes11,
        .keyword_bytes12,
        .keyword_bytes13,
        .keyword_bytes14,
        .keyword_bytes15,
        .keyword_bytes16,
        .keyword_bytes17,
        .keyword_bytes18,
        .keyword_bytes19,
        .keyword_bytes20,
        .keyword_bytes21,
        .keyword_bytes22,
        .keyword_bytes23,
        .keyword_bytes24,
        .keyword_bytes25,
        .keyword_bytes26,
        .keyword_bytes27,
        .keyword_bytes28,
        .keyword_bytes29,
        .keyword_bytes30,
        .keyword_bytes31,
        .keyword_bytes32,
        .keyword_uint,
        .keyword_uint8,
        .keyword_uint16,
        .keyword_uint24,
        .keyword_uint32,
        .keyword_uint40,
        .keyword_uint48,
        .keyword_uint56,
        .keyword_uint64,
        .keyword_uint72,
        .keyword_uint80,
        .keyword_uint88,
        .keyword_uint96,
        .keyword_uint104,
        .keyword_uint112,
        .keyword_uint120,
        .keyword_uint128,
        .keyword_uint136,
        .keyword_uint144,
        .keyword_uint152,
        .keyword_uint160,
        .keyword_uint168,
        .keyword_uint176,
        .keyword_uint184,
        .keyword_uint192,
        .keyword_uint200,
        .keyword_uint208,
        .keyword_uint216,
        .keyword_uint224,
        .keyword_uint232,
        .keyword_uint240,
        .keyword_uint248,
        .keyword_uint256,
        .keyword_int,
        .keyword_int8,
        .keyword_int16,
        .keyword_int24,
        .keyword_int32,
        .keyword_int40,
        .keyword_int48,
        .keyword_int56,
        .keyword_int64,
        .keyword_int72,
        .keyword_int80,
        .keyword_int88,
        .keyword_int96,
        .keyword_int104,
        .keyword_int112,
        .keyword_int120,
        .keyword_int128,
        .keyword_int136,
        .keyword_int144,
        .keyword_int152,
        .keyword_int160,
        .keyword_int168,
        .keyword_int176,
        .keyword_int184,
        .keyword_int192,
        .keyword_int200,
        .keyword_int208,
        .keyword_int216,
        .keyword_int224,
        .keyword_int232,
        .keyword_int240,
        .keyword_int248,
        .keyword_int256,
        => self.addNode(.{
            .tag = .elementary_type,
            .main_token = self.nextToken(),
            .data = .{
                .rhs = undefined,
                .lhs = undefined,
            },
        }),
        else => null_node,
    };
}
/// Consume visibility modifiers.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.visibility)
pub fn consumeVisibilityModifier(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_external,
        .keyword_internal,
        .keyword_private,
        .keyword_public,
        => self.nextToken(),

        else => null,
    };
}
/// Consume state mutability modifiers.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.stateMutability)
pub fn consumeStateMutability(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_payable,
        .keyword_view,
        .keyword_pure,
        => self.nextToken(),

        else => null,
    };
}
/// Consumes storage location modifiers.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.dataLocation)
pub fn consumeStorageLocation(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_memory,
        .keyword_storage,
        .keyword_calldata,
        => self.nextToken(),
        else => null,
    };
}
/// Consumes all doc_comment tokens.
pub fn consumeDocComments(self: *Parser) Allocator.Error!?TokenIndex {
    if (self.consumeToken(.doc_comment)) |token| {
        var first_token = token;

        if (token > 0 and self.tokensOnSameLine(first_token - 1, token)) {
            try self.warnMessage(.{ .tag = .same_line_doc_comment, .token = token });

            first_token = self.consumeToken(.doc_comment) orelse return null;
        }

        while (self.consumeToken(.doc_comment)) |_| {}
        return first_token;
    }

    return null;
}

// Internal parser actions.

/// Checks if the given tokens are on the same line.
fn tokensOnSameLine(self: *Parser, token1: TokenIndex, token2: TokenIndex) bool {
    return std.mem.indexOfScalar(u8, self.source[self.token_starts[token1]..self.token_starts[token2]], '\n') == null;
}
/// Same as `consumeToken` but returns error instead.
fn expectToken(self: *Parser, token: Token.Tag) ParserErrors!TokenIndex {
    if (self.token_tags[self.token_index] != token) {
        return self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_tag = token },
        });
    }
    return self.nextToken();
}
/// Returns error if current token is not semicolon.
fn expectSemicolon(self: *Parser) ParserErrors!void {
    if (self.token_tags[self.token_index] != .semicolon) {
        return self.failMsg(.{
            .tag = .expected_semicolon,
            .token = self.token_index,
        });
    }
    _ = self.nextToken();
    return;
}
/// Advances the parser index if the token matches else return null
fn consumeToken(self: *Parser, token: Token.Tag) ?TokenIndex {
    return if (self.token_tags[self.token_index] == token) self.nextToken() else null;
}
/// Advances the parser index and returns old.
fn nextToken(self: *Parser) TokenIndex {
    const index = self.token_index;
    self.token_index += 1;

    return index;
}

// Node actions.

fn addExtraData(self: *Parser, extra: anytype) Allocator.Error!Node.Index {
    const fields = std.meta.fields(@TypeOf(extra));

    try self.extra_data.ensureUnusedCapacity(self.allocator, fields.len);
    const result: u32 = @intCast(self.extra_data.items.len);

    inline for (fields) |field| {
        comptime std.debug.assert(field.type == Node.Index);
        self.extra_data.appendAssumeCapacity(@field(extra, field.name));
    }

    return result;
}

fn listToSpan(self: *Parser, list: []const Node.Index) Allocator.Error!Node.Range {
    try self.extra_data.appendSlice(self.allocator, list);

    return Node.Range{
        .start = @as(Node.Index, @intCast(self.extra_data.items.len - list.len)),
        .end = @as(Node.Index, @intCast(self.extra_data.items.len)),
    };
}

fn addNode(self: *Parser, child: Node) Allocator.Error!Node.Index {
    const index = @as(Node.Index, @intCast(self.nodes.len));
    try self.nodes.append(self.allocator, child);

    return index;
}

fn setNode(self: *Parser, index: usize, child: Node) Node.Index {
    self.nodes.set(index, child);

    return @as(Node.Index, @intCast(index));
}

fn reserveNode(self: *Parser, tag: Ast.Node.Tag) !usize {
    try self.nodes.resize(self.allocator, self.nodes.len + 1);
    self.nodes.items(.tag)[self.nodes.len - 1] = tag;
    return self.nodes.len - 1;
}

fn warn(self: *Parser, fail_tag: Ast.Error.Tag) Allocator.Error!void {
    @branchHint(.cold);

    try self.warnMessage(.{
        .tag = fail_tag,
        .token = self.token_index,
    });
}

fn warnMessage(self: *Parser, message: Ast.Error) Allocator.Error!void {
    @branchHint(.cold);

    switch (message.tag) {
        .expected_semicolon,
        .expected_token,
        .expected_r_brace,
        .expected_comma_after,
        .same_line_doc_comment,
        .expected_suffix,
        .trailing_comma,
        => if (message.token != 0 and !self.tokensOnSameLine(message.token - 1, message.token)) {
            var copy = message;
            copy.token_is_prev = true;
            copy.token -= 1;
            return self.errors.append(self.allocator, copy);
        },
        else => {},
    }
    try self.errors.append(self.allocator, message);
}

fn fail(self: *Parser, fail_tag: Ast.Error.Tag) ParserErrors {
    @branchHint(.cold);

    return self.failMsg(.{
        .tag = fail_tag,
        .token = self.token_index,
    });
}

fn failMsg(self: *Parser, message: Ast.Error) ParserErrors {
    @branchHint(.cold);
    try self.warnMessage(message);

    return error.ParsingError;
}
